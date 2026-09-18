using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public sealed class DaMaoRimeP3Exception : Exception
{
    public string ErrorCode { get; private set; }

    public DaMaoRimeP3Exception(string errorCode, string message)
        : base(message)
    {
        ErrorCode = errorCode;
    }

    public DaMaoRimeP3Exception(string errorCode, string message, Exception inner)
        : base(message, inner)
    {
        ErrorCode = errorCode;
    }
}

public static class DaMaoRimeRestoreAdapter
{
    private const string SupportedVersion = "1.13.1";
    private static readonly object Gate = new object();

    [StructLayout(LayoutKind.Sequential)]
    private struct RimeTraits
    {
        public int data_size;
        public IntPtr shared_data_dir;
        public IntPtr user_data_dir;
        public IntPtr distribution_name;
        public IntPtr distribution_code_name;
        public IntPtr distribution_version;
        public IntPtr app_name;
        public IntPtr modules;
        public int min_log_level;
        public IntPtr log_dir;
        public IntPtr prebuilt_data_dir;
        public IntPtr staging_dir;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string path);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeLibrary(IntPtr module);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr GetApiDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void TraitsDelegate(ref RimeTraits traits);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void VoidDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr FindModuleDelegate(IntPtr moduleNameUtf8);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int RunTaskDelegate(IntPtr taskNameUtf8);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr GetCustomApiDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr GetVersionDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int RestoreUserDictDelegate(IntPtr snapshotPathUtf8);

    private static IntPtr nativeModule = IntPtr.Zero;
    private static IntPtr mainApi = IntPtr.Zero;
    private static VoidDelegate finalize;
    private static RestoreUserDictDelegate restoreUserDict;
    private static readonly List<IntPtr> allocations = new List<IntPtr>();
    private static bool initialized;

    public static string LibrimeVersion { get; private set; }
    public static int MainApiDataSize { get; private set; }
    public static int LeversApiDataSize { get; private set; }
    public static int RestoreCallCount { get; private set; }
    public static string SupportedArchitecture { get { return "x64"; } }
    public static bool IsInitialized { get { return initialized; } }

    private static IntPtr Utf8Alloc(string value)
    {
        if (value == null)
            return IntPtr.Zero;
        byte[] bytes = Encoding.UTF8.GetBytes(value + "\0");
        IntPtr memory = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, memory, bytes.Length);
        allocations.Add(memory);
        return memory;
    }

    private static string Utf8Read(IntPtr value)
    {
        if (value == IntPtr.Zero)
            return String.Empty;
        int length = 0;
        while (Marshal.ReadByte(value, length) != 0)
            length++;
        byte[] bytes = new byte[length];
        Marshal.Copy(value, bytes, 0, length);
        return Encoding.UTF8.GetString(bytes);
    }

    private static int FirstPointerOffset
    {
        get { return IntPtr.Size == 8 ? 8 : 4; }
    }

    private static IntPtr ReadVersionedFunction(IntPtr api, int dataSize, int index,
                                                 string errorCode, string functionName)
    {
        if (api == IntPtr.Zero || dataSize < 0)
            throw new DaMaoRimeP3Exception(errorCode,
                functionName + " API structure is unavailable.");
        int offset = FirstPointerOffset + (index * IntPtr.Size);
        if (sizeof(int) + dataSize <= offset)
            throw new DaMaoRimeP3Exception(errorCode,
                functionName + " is outside the advertised API boundary.");
        IntPtr function = Marshal.ReadIntPtr(api, offset);
        if (function == IntPtr.Zero)
            throw new DaMaoRimeP3Exception(errorCode,
                functionName + " is not provided by this API.");
        return function;
    }

    private static T Function<T>(IntPtr api, int dataSize, int index,
                                  string errorCode, string functionName) where T : class
    {
        IntPtr address = ReadVersionedFunction(api, dataSize, index, errorCode, functionName);
        T result = Marshal.GetDelegateForFunctionPointer(address, typeof(T)) as T;
        if (result == null)
            throw new DaMaoRimeP3Exception(errorCode,
                functionName + " has an incompatible function pointer.");
        return result;
    }

    private static void ReleaseAllocations()
    {
        for (int index = allocations.Count - 1; index >= 0; index--)
            Marshal.FreeHGlobal(allocations[index]);
        allocations.Clear();
    }

    private static void ClearManagedState()
    {
        restoreUserDict = null;
        finalize = null;
        mainApi = IntPtr.Zero;
        MainApiDataSize = 0;
        LeversApiDataSize = 0;
        LibrimeVersion = null;
        initialized = false;
    }

    public static void Initialize(string dllPath, string sharedDataDir,
                                  string userDataDir, string stagingDir)
    {
        lock (Gate)
        {
            if (initialized)
                throw new DaMaoRimeP3Exception("P3_NATIVE_INITIALIZATION_FAILED",
                    "The restore adapter is already initialized.");
            if (IntPtr.Size != 8)
                throw new DaMaoRimeP3Exception("P3_NATIVE_ARCHITECTURE_UNSUPPORTED",
                    "The P3 restore adapter supports only x64 librime.");
            try
            {
                nativeModule = LoadLibraryW(dllPath);
                if (nativeModule == IntPtr.Zero)
                    throw new DaMaoRimeP3Exception("P3_RIME_API_UNAVAILABLE",
                        "Unable to load the requested rime.dll.",
                        new Win32Exception(Marshal.GetLastWin32Error()));
                IntPtr entry = GetProcAddress(nativeModule, "rime_get_api");
                if (entry == IntPtr.Zero)
                    throw new DaMaoRimeP3Exception("P3_RIME_API_UNAVAILABLE",
                        "rime_get_api is unavailable.");
                GetApiDelegate getApi = (GetApiDelegate)Marshal.GetDelegateForFunctionPointer(
                    entry, typeof(GetApiDelegate));
                mainApi = getApi();
                if (mainApi == IntPtr.Zero)
                    throw new DaMaoRimeP3Exception("P3_RIME_API_UNAVAILABLE",
                        "rime_get_api returned a null API pointer.");
                MainApiDataSize = Marshal.ReadInt32(mainApi);

                TraitsDelegate setup = Function<TraitsDelegate>(mainApi, MainApiDataSize, 0,
                    "P3_RIME_API_UNAVAILABLE", "setup");
                TraitsDelegate initialize = Function<TraitsDelegate>(mainApi, MainApiDataSize, 2,
                    "P3_RIME_API_UNAVAILABLE", "initialize");
                finalize = Function<VoidDelegate>(mainApi, MainApiDataSize, 3,
                    "P3_RIME_API_UNAVAILABLE", "finalize");
                FindModuleDelegate findModule = Function<FindModuleDelegate>(mainApi,
                    MainApiDataSize, 49, "P3_RIME_API_UNAVAILABLE", "find_module");
                RunTaskDelegate runTask = Function<RunTaskDelegate>(mainApi,
                    MainApiDataSize, 50, "P3_RIME_API_UNAVAILABLE", "run_task");
                GetVersionDelegate getVersion = Function<GetVersionDelegate>(mainApi,
                    MainApiDataSize, 72, "P3_RIME_API_UNAVAILABLE", "get_version");

                LibrimeVersion = Utf8Read(getVersion());
                if (!String.Equals(LibrimeVersion, SupportedVersion, StringComparison.Ordinal))
                    throw new DaMaoRimeP3Exception("P3_LIBRIME_MUTATION_UNVERIFIED",
                        "Mutation-capable restore requires verified librime " +
                        SupportedVersion + ".");

                IntPtr deployerName = Utf8Alloc("deployer");
                IntPtr moduleArray = Marshal.AllocHGlobal(IntPtr.Size * 2);
                allocations.Add(moduleArray);
                Marshal.WriteIntPtr(moduleArray, 0, deployerName);
                Marshal.WriteIntPtr(moduleArray, IntPtr.Size, IntPtr.Zero);

                RimeTraits traits = new RimeTraits();
                traits.data_size = Marshal.SizeOf(typeof(RimeTraits)) - sizeof(int);
                traits.shared_data_dir = Utf8Alloc(sharedDataDir);
                traits.user_data_dir = Utf8Alloc(userDataDir);
                traits.distribution_name = Utf8Alloc("DaMao UserDB Portability P3");
                traits.distribution_code_name = Utf8Alloc("DaMaoUserDbPortabilityP3");
                traits.distribution_version = Utf8Alloc("3");
                traits.app_name = Utf8Alloc("rime.damao_userdb_portability_p3");
                traits.modules = moduleArray;
                traits.min_log_level = 2;
                traits.log_dir = Utf8Alloc("");
                traits.prebuilt_data_dir = Utf8Alloc(sharedDataDir);
                traits.staging_dir = Utf8Alloc(stagingDir);
                setup(ref traits);
                initialize(ref traits);
                initialized = true;

                IntPtr installationUpdate = Utf8Alloc("installation_update");
                if (runTask(installationUpdate) == 0)
                    throw new DaMaoRimeP3Exception("P3_NATIVE_INITIALIZATION_FAILED",
                        "The librime installation_update task failed.");

                IntPtr leversName = Utf8Alloc("levers");
                IntPtr module = findModule(leversName);
                if (module == IntPtr.Zero)
                    throw new DaMaoRimeP3Exception("P3_LEVERS_MODULE_UNAVAILABLE",
                        "The levers module is unavailable.");
                int moduleDataSize = Marshal.ReadInt32(module);
                int getApiOffset = FirstPointerOffset + (3 * IntPtr.Size);
                if (sizeof(int) + moduleDataSize <= getApiOffset)
                    throw new DaMaoRimeP3Exception("P3_LEVERS_MODULE_UNAVAILABLE",
                        "The levers module does not advertise get_api.");
                IntPtr getCustomApiAddress = Marshal.ReadIntPtr(module, getApiOffset);
                if (getCustomApiAddress == IntPtr.Zero)
                    throw new DaMaoRimeP3Exception("P3_LEVERS_MODULE_UNAVAILABLE",
                        "The levers module get_api pointer is unavailable.");
                GetCustomApiDelegate getCustomApi = (GetCustomApiDelegate)
                    Marshal.GetDelegateForFunctionPointer(getCustomApiAddress,
                        typeof(GetCustomApiDelegate));
                IntPtr leversApi = getCustomApi();
                if (leversApi == IntPtr.Zero)
                    throw new DaMaoRimeP3Exception("P3_LEVERS_API_INCOMPATIBLE",
                        "The levers module returned a null API pointer.");
                LeversApiDataSize = Marshal.ReadInt32(leversApi);
                restoreUserDict = Function<RestoreUserDictDelegate>(leversApi,
                    LeversApiDataSize, 28, "P3_RESTORE_API_UNAVAILABLE",
                    "restore_user_dict");
            }
            catch (DaMaoRimeP3Exception)
            {
                ShutdownInternal();
                throw;
            }
            catch (Exception ex)
            {
                ShutdownInternal();
                throw new DaMaoRimeP3Exception("P3_NATIVE_INITIALIZATION_FAILED",
                    "librime restore initialization failed.", ex);
            }
        }
    }

    public static bool RestoreUserDictionary(string snapshotPath)
    {
        lock (Gate)
        {
            if (!initialized || restoreUserDict == null)
                throw new DaMaoRimeP3Exception("P3_RESTORE_API_UNAVAILABLE",
                    "restore_user_dict is unavailable because the adapter is not initialized.");
            IntPtr path = IntPtr.Zero;
            try
            {
                path = Utf8Alloc(snapshotPath);
                RestoreCallCount++;
                return restoreUserDict(path) != 0;
            }
            catch (DaMaoRimeP3Exception) { throw; }
            catch (Exception ex)
            {
                throw new DaMaoRimeP3Exception("P3_NATIVE_RESTORE_FAILED",
                    "The native restore call failed.", ex);
            }
        }
    }

    private static void ShutdownInternal()
    {
        try
        {
            if (initialized && finalize != null)
                finalize();
        }
        finally
        {
            initialized = false;
            ReleaseAllocations();
            if (nativeModule != IntPtr.Zero)
            {
                FreeLibrary(nativeModule);
                nativeModule = IntPtr.Zero;
            }
            ClearManagedState();
        }
    }

    public static void Shutdown()
    {
        lock (Gate)
        {
            ShutdownInternal();
        }
    }
}
