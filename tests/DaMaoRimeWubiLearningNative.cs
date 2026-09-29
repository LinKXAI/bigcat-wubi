using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class DaMaoRimeWubiLearningNative
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct RimeTraits
    {
        public int data_size;
        [MarshalAs(UnmanagedType.LPStr)] public string shared_data_dir;
        [MarshalAs(UnmanagedType.LPStr)] public string user_data_dir;
        [MarshalAs(UnmanagedType.LPStr)] public string distribution_name;
        [MarshalAs(UnmanagedType.LPStr)] public string distribution_code_name;
        [MarshalAs(UnmanagedType.LPStr)] public string distribution_version;
        [MarshalAs(UnmanagedType.LPStr)] public string app_name;
        public IntPtr modules;
        public int min_log_level;
        [MarshalAs(UnmanagedType.LPStr)] public string log_dir;
        [MarshalAs(UnmanagedType.LPStr)] public string prebuilt_data_dir;
        [MarshalAs(UnmanagedType.LPStr)] public string staging_dir;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RimeCandidate
    {
        public IntPtr text;
        public IntPtr comment;
        public IntPtr reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RimeCandidateListIterator
    {
        public IntPtr ptr;
        public int index;
        public RimeCandidate candidate;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RimeCommit
    {
        public int data_size;
        public IntPtr text;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string path);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr GetApiDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void TraitsDelegate(ref RimeTraits traits);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void TraitsPointerDelegate(IntPtr traits);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void VoidDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int NoArgBoolDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate UIntPtr CreateSessionDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SessionBoolDelegate(UIntPtr session);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ProcessKeyDelegate(UIntPtr session, int keycode, int mask);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ClearCompositionDelegate(UIntPtr session);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int GetCommitDelegate(UIntPtr session, ref RimeCommit commit);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int FreeCommitDelegate(ref RimeCommit commit);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void SetOptionDelegate(UIntPtr session, [MarshalAs(UnmanagedType.LPStr)] string option, int value);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private delegate int SelectSchemaDelegate(UIntPtr session, [MarshalAs(UnmanagedType.LPStr)] string schemaId);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CandidateListBeginDelegate(UIntPtr session, ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CandidateListNextDelegate(ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void CandidateListEndDelegate(ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetSchemaDelegate(UIntPtr session, StringBuilder buffer, UIntPtr length);

    private static IntPtr api;
    private static RimeTraits traits;
    private static TraitsPointerDelegate initialize;
    private static VoidDelegate finalize;
    private static VoidDelegate joinMaintenance;
    private static NoArgBoolDelegate deployWorkspace;
    private static NoArgBoolDelegate syncUserData;
    private static CreateSessionDelegate createSession;
    private static SessionBoolDelegate destroySession;
    private static ProcessKeyDelegate processKey;
    private static ClearCompositionDelegate clearComposition;
    private static GetCommitDelegate getCommit;
    private static FreeCommitDelegate freeCommit;
    private static SetOptionDelegate setOption;
    private static SelectSchemaDelegate selectSchema;
    private static CandidateListBeginDelegate candidateListBegin;
    private static CandidateListNextDelegate candidateListNext;
    private static CandidateListEndDelegate candidateListEnd;
    private static TraitsDelegate deployerInitialize;

    private static T Function<T>(int index) where T : class
    {
        int firstFunctionOffset = IntPtr.Size == 8 ? 8 : 4;
        IntPtr address = Marshal.ReadIntPtr(api, firstFunctionOffset + index * IntPtr.Size);
        if (address == IntPtr.Zero)
            throw new InvalidOperationException("Rime API function is unavailable at index " + index + ".");
        return Marshal.GetDelegateForFunctionPointer(address, typeof(T)) as T;
    }

    private static string Utf8(IntPtr value)
    {
        if (value == IntPtr.Zero) return String.Empty;
        int length = 0;
        while (Marshal.ReadByte(value, length) != 0) length++;
        byte[] bytes = new byte[length];
        Marshal.Copy(value, bytes, 0, length);
        return Encoding.UTF8.GetString(bytes);
    }

    public static void Load(string dllPath, string sharedDataDir, string userDataDir, string stagingDir)
    {
        IntPtr module = LoadLibrary(dllPath);
        if (module == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Cannot load rime.dll.");
        IntPtr entry = GetProcAddress(module, "rime_get_api");
        if (entry == IntPtr.Zero) throw new MissingMethodException("rime_get_api is not exported by rime.dll.");
        GetApiDelegate getApi = (GetApiDelegate)Marshal.GetDelegateForFunctionPointer(entry, typeof(GetApiDelegate));
        api = getApi();

        TraitsDelegate setup = Function<TraitsDelegate>(0);
        initialize = Function<TraitsPointerDelegate>(2);
        finalize = Function<VoidDelegate>(3);
        joinMaintenance = Function<VoidDelegate>(6);
        deployerInitialize = Function<TraitsDelegate>(7);
        deployWorkspace = Function<NoArgBoolDelegate>(9);
        syncUserData = Function<NoArgBoolDelegate>(12);
        createSession = Function<CreateSessionDelegate>(13);
        destroySession = Function<SessionBoolDelegate>(15);
        processKey = Function<ProcessKeyDelegate>(18);
        clearComposition = Function<ClearCompositionDelegate>(20);
        getCommit = Function<GetCommitDelegate>(21);
        freeCommit = Function<FreeCommitDelegate>(22);
        setOption = Function<SetOptionDelegate>(27);
        selectSchema = Function<SelectSchemaDelegate>(34);
        candidateListBegin = Function<CandidateListBeginDelegate>(75);
        candidateListNext = Function<CandidateListNextDelegate>(76);
        candidateListEnd = Function<CandidateListEndDelegate>(77);

        traits = new RimeTraits {
            data_size = Marshal.SizeOf(typeof(RimeTraits)) - sizeof(int),
            shared_data_dir = sharedDataDir,
            user_data_dir = userDataDir,
            distribution_name = "DaMao Native Learning Runtime",
            distribution_code_name = "DaMaoFormalWubiLearning",
            distribution_version = "0.9.1-dev.4",
            app_name = "rime.damao_formal_learning",
            modules = IntPtr.Zero,
            min_log_level = 1,
            log_dir = "",
            prebuilt_data_dir = sharedDataDir,
            staging_dir = stagingDir
        };
        setup(ref traits);
        deployerInitialize(ref traits);
    }

    public static bool DeployWorkspace() { return deployWorkspace() != 0; }
    public static void StartService() { initialize(IntPtr.Zero); }

    public static ulong CreateSession(string schemaId)
    {
        UIntPtr session = createSession();
        if (session == UIntPtr.Zero) throw new InvalidOperationException("Rime failed to create a session.");
        if (selectSchema(session, schemaId) == 0)
            throw new InvalidOperationException("Rime failed to select schema " + schemaId + ".");
        return session.ToUInt64();
    }

    public static ulong CreateDefaultSession()
    {
        ulong session = createSession().ToUInt64();
        if (session == 0 || CurrentSchema(session) != "damao_wubi")
            throw new InvalidOperationException("Actual default schema is not formal damao_wubi.");
        return session;
    }

    [StructLayout(LayoutKind.Sequential)] private struct Composition {
        public int length, cursor, start, end; public IntPtr preedit;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Menu {
        public int size, page, last, highlighted, count; public IntPtr candidates, keys;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Context {
        public int data_size; public Composition composition; public Menu menu;
        public IntPtr preview, labels;
    }
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ContextDelegate(UIntPtr session, ref Context context);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void FreeContextDelegate(ref Context context);
    public static string[] View(ulong session) {
        Context c = new Context(); c.data_size = Marshal.SizeOf(typeof(Context)) - sizeof(int);
        if (Function<ContextDelegate>(23)(new UIntPtr(session), ref c) == 0) throw new Exception("No context");
        try { return new string[] { Utf8(c.composition.preedit), c.menu.size.ToString(), c.menu.page.ToString() }; }
        finally { Function<FreeContextDelegate>(24)(ref c); }
    }

    [StructLayout(LayoutKind.Sequential)] private struct FileInfo {
        public uint attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME creation, access, write;
        public uint volume, sizeHigh, sizeLow, links, indexHigh, indexLow;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateFile(string path, uint access, uint share, IntPtr security, uint mode, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(IntPtr handle, out FileInfo info);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    public static string DirectoryIdentity(string path) {
        IntPtr handle = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
        if (handle == new IntPtr(-1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        try {
            FileInfo info;
            if (!GetFileInformationByHandle(handle, out info)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            return info.volume.ToString("X8") + ":" + info.indexHigh.ToString("X8") + info.indexLow.ToString("X8");
        } finally { CloseHandle(handle); }
    }

    public static void DestroySession(ulong session) { destroySession(new UIntPtr(session)); }
    public static void Restart() { finalize(); deployerInitialize(ref traits); initialize(IntPtr.Zero); }
    public static void Shutdown() { if (finalize != null) finalize(); }

    public static string CurrentSchema(ulong value)
    {
        StringBuilder buffer = new StringBuilder(256);
        if (Function<GetSchemaDelegate>(33)(new UIntPtr(value), buffer, new UIntPtr(256)) == 0)
            throw new InvalidOperationException("Rime failed to report the current schema.");
        return buffer.ToString();
    }

    public static bool SyncUserData()
    {
        if (syncUserData() == 0) return false;
        joinMaintenance();
        return true;
    }

    // Probe-only candidate inspection after input created by rime_process_key.
    public static string[] CurrentCandidates(ulong value, int limit)
    {
        UIntPtr session = new UIntPtr(value);
        RimeCandidateListIterator iterator = new RimeCandidateListIterator();
        if (candidateListBegin(session, ref iterator) == 0) return new string[0];
        try {
            List<string> result = new List<string>();
            while (result.Count < limit && candidateListNext(ref iterator) != 0)
                result.Add(Utf8(iterator.candidate.text));
            return result.ToArray();
        }
        finally { candidateListEnd(ref iterator); }
    }

    public static void Clear(ulong value)
    {
        clearComposition(new UIntPtr(value));
    }

    public static string ReadPendingCommit(ulong value)
    {
        return ReadCommit(new UIntPtr(value));
    }

    public static bool ProcessKey(ulong value, int keycode, int mask)
    {
        return processKey(new UIntPtr(value), keycode, mask) != 0;
    }

    public static void SetOption(ulong value, string option, bool enabled)
    {
        setOption(new UIntPtr(value), option, enabled ? 1 : 0);
    }

    public static string ReadCommit(UIntPtr session)
    {
        RimeCommit commit = new RimeCommit();
        commit.data_size = Marshal.SizeOf(typeof(RimeCommit)) - sizeof(int);
        if (getCommit(session, ref commit) == 0) return String.Empty;
        try { return Utf8(commit.text); }
        finally { freeCommit(ref commit); }
    }
}
