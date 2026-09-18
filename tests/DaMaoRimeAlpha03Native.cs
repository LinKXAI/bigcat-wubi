using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class DaMaoRimeAlpha03Native
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
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SelectCandidateDelegate(UIntPtr session, UIntPtr index);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CandidateListBeginDelegate(UIntPtr session, ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CandidateListNextDelegate(ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void CandidateListEndDelegate(ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private delegate int SetInputDelegate(UIntPtr session, [MarshalAs(UnmanagedType.LPStr)] string input);

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
    private static SessionBoolDelegate commitComposition;
    private static ClearCompositionDelegate clearComposition;
    private static GetCommitDelegate getCommit;
    private static FreeCommitDelegate freeCommit;
    private static SetOptionDelegate setOption;
    private static SelectSchemaDelegate selectSchema;
    private static SelectCandidateDelegate selectCandidate;
    private static CandidateListBeginDelegate candidateListBegin;
    private static CandidateListNextDelegate candidateListNext;
    private static CandidateListEndDelegate candidateListEnd;
    private static SetInputDelegate setInput;
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
        commitComposition = Function<SessionBoolDelegate>(19);
        clearComposition = Function<ClearCompositionDelegate>(20);
        getCommit = Function<GetCommitDelegate>(21);
        freeCommit = Function<FreeCommitDelegate>(22);
        setOption = Function<SetOptionDelegate>(27);
        selectSchema = Function<SelectSchemaDelegate>(34);
        selectCandidate = Function<SelectCandidateDelegate>(71);
        candidateListBegin = Function<CandidateListBeginDelegate>(75);
        candidateListNext = Function<CandidateListNextDelegate>(76);
        candidateListEnd = Function<CandidateListEndDelegate>(77);
        setInput = Function<SetInputDelegate>(89);

        traits = new RimeTraits {
            data_size = Marshal.SizeOf(typeof(RimeTraits)) - sizeof(int),
            shared_data_dir = sharedDataDir,
            user_data_dir = userDataDir,
            distribution_name = "DaMao Native Learning Runtime",
            distribution_code_name = "DaMaoAlpha03LearningRuntime",
            distribution_version = "0.3.0-alpha.2",
            app_name = "rime.damao_alpha03_learning_runtime",
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

    public static void DestroySession(ulong session) { destroySession(new UIntPtr(session)); }
    public static void Restart() { finalize(); deployerInitialize(ref traits); initialize(IntPtr.Zero); }
    public static void Shutdown() { if (finalize != null) finalize(); }

    public static bool SyncUserData()
    {
        if (syncUserData() == 0) return false;
        joinMaintenance();
        return true;
    }

    public static string[] Candidates(ulong value, string code, int limit)
    {
        UIntPtr session = new UIntPtr(value);
        clearComposition(session);
        if (setInput(session, code) == 0) return new string[0];
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

    public static string CommitCandidate(ulong value, string code, string text, int limit)
    {
        UIntPtr session = new UIntPtr(value);
        string[] items = Candidates(value, code, limit);
        int index = Array.IndexOf(items, text);
        if (index < 0) throw new InvalidOperationException("Candidate '" + text + "' is absent for '" + code + "'.");
        if (selectCandidate(session, new UIntPtr((uint)index)) == 0)
            throw new InvalidOperationException("Rime failed to select candidate " + index + ".");
        commitComposition(session);
        return ReadCommit(session);
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
