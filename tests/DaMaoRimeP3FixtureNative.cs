using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

// Test-only real-librime fixture for synthetic learning and candidate probes.
public static class DaMaoRimeP3FixtureNative
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
    private static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr GetApiDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void TraitsDelegate(ref RimeTraits traits);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void TraitsPointerDelegate(IntPtr traits);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void VoidDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int NoArgBoolDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate UIntPtr CreateSessionDelegate();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SessionBoolDelegate(UIntPtr session);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SessionIndexBoolDelegate(UIntPtr session, UIntPtr index);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SetInputDelegate(UIntPtr session, [MarshalAs(UnmanagedType.LPStr)] string input);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SelectSchemaDelegate(UIntPtr session, [MarshalAs(UnmanagedType.LPStr)] string schemaId);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CandidateBeginDelegate(UIntPtr session, ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CandidateNextDelegate(ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void CandidateEndDelegate(ref RimeCandidateListIterator iterator);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int GetCommitDelegate(UIntPtr session, ref RimeCommit commit);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int FreeCommitDelegate(ref RimeCommit commit);

    private static IntPtr api;
    private static TraitsPointerDelegate initialize;
    private static VoidDelegate finalize;
    private static NoArgBoolDelegate deploy;
    private static CreateSessionDelegate createSession;
    private static SessionBoolDelegate destroySession;
    private static SessionBoolDelegate commitComposition;
    private static SetInputDelegate setInput;
    private static SelectSchemaDelegate selectSchema;
    private static SessionIndexBoolDelegate selectCandidate;
    private static SessionIndexBoolDelegate deleteCandidate;
    private static CandidateBeginDelegate candidateBegin;
    private static CandidateNextDelegate candidateNext;
    private static CandidateEndDelegate candidateEnd;
    private static GetCommitDelegate getCommit;
    private static FreeCommitDelegate freeCommit;

    private static T Function<T>(int index) where T : class
    {
        int first = IntPtr.Size == 8 ? 8 : 4;
        int dataSize = Marshal.ReadInt32(api);
        int offset = first + index * IntPtr.Size;
        if (sizeof(int) + dataSize <= offset)
            throw new InvalidOperationException("Fixture API boundary failure.");
        IntPtr address = Marshal.ReadIntPtr(api, offset);
        if (address == IntPtr.Zero)
            throw new InvalidOperationException("Fixture API function unavailable.");
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

    public static void Load(string dllPath, string sharedDataDir,
                            string userDataDir, string stagingDir)
    {
        if (IntPtr.Size != 8)
            throw new InvalidOperationException("P3 fixture requires x64.");
        IntPtr module = LoadLibraryW(dllPath);
        if (module == IntPtr.Zero)
            throw new InvalidOperationException("Cannot load fixture rime.dll.");
        IntPtr entry = GetProcAddress(module, "rime_get_api");
        if (entry == IntPtr.Zero)
            throw new InvalidOperationException("Fixture rime_get_api unavailable.");
        GetApiDelegate getApi = (GetApiDelegate)Marshal.GetDelegateForFunctionPointer(
            entry, typeof(GetApiDelegate));
        api = getApi();
        TraitsDelegate setup = Function<TraitsDelegate>(0);
        initialize = Function<TraitsPointerDelegate>(2);
        finalize = Function<VoidDelegate>(3);
        TraitsDelegate deployerInitialize = Function<TraitsDelegate>(7);
        deploy = Function<NoArgBoolDelegate>(9);
        createSession = Function<CreateSessionDelegate>(13);
        destroySession = Function<SessionBoolDelegate>(15);
        commitComposition = Function<SessionBoolDelegate>(19);
        getCommit = Function<GetCommitDelegate>(21);
        freeCommit = Function<FreeCommitDelegate>(22);
        selectSchema = Function<SelectSchemaDelegate>(34);
        selectCandidate = Function<SessionIndexBoolDelegate>(71);
        candidateBegin = Function<CandidateBeginDelegate>(75);
        candidateNext = Function<CandidateNextDelegate>(76);
        candidateEnd = Function<CandidateEndDelegate>(77);
        deleteCandidate = Function<SessionIndexBoolDelegate>(86);
        setInput = Function<SetInputDelegate>(89);

        RimeTraits traits = new RimeTraits();
        traits.data_size = Marshal.SizeOf(typeof(RimeTraits)) - sizeof(int);
        traits.shared_data_dir = sharedDataDir;
        traits.user_data_dir = userDataDir;
        traits.distribution_name = "DaMao P3 Fixture";
        traits.distribution_code_name = "DaMaoP3Fixture";
        traits.distribution_version = "3";
        traits.app_name = "rime.damao_p3_fixture";
        traits.modules = IntPtr.Zero;
        traits.min_log_level = 2;
        traits.log_dir = "";
        traits.prebuilt_data_dir = sharedDataDir;
        traits.staging_dir = stagingDir;
        setup(ref traits);
        deployerInitialize(ref traits);
    }

    public static bool Deploy() { return deploy() != 0; }
    public static void Start() { initialize(IntPtr.Zero); }

    public static ulong OpenSession(string schemaId)
    {
        UIntPtr session = createSession();
        if (session == UIntPtr.Zero || selectSchema(session, schemaId) == 0)
            throw new InvalidOperationException("Cannot open fixture schema.");
        return session.ToUInt64();
    }

    public static string[] Candidates(ulong value, string input)
    {
        UIntPtr session = new UIntPtr(value);
        if (setInput(session, input) == 0) return new string[0];
        RimeCandidateListIterator iterator = new RimeCandidateListIterator();
        if (candidateBegin(session, ref iterator) == 0) return new string[0];
        List<string> result = new List<string>();
        try
        {
            while (candidateNext(ref iterator) != 0)
                result.Add(Utf8(iterator.candidate.text));
        }
        finally { candidateEnd(ref iterator); }
        return result.ToArray();
    }

    public static string CommitAt(ulong value, string input, ulong index)
    {
        UIntPtr session = new UIntPtr(value);
        string[] candidates = Candidates(value, input);
        if (index >= (ulong)candidates.Length ||
            selectCandidate(session, new UIntPtr(index)) == 0 ||
            commitComposition(session) == 0)
            throw new InvalidOperationException("Cannot commit the fixture candidate.");
        RimeCommit commit = new RimeCommit();
        commit.data_size = Marshal.SizeOf(typeof(RimeCommit)) - sizeof(int);
        if (getCommit(session, ref commit) == 0) return String.Empty;
        try { return Utf8(commit.text); }
        finally { freeCommit(ref commit); }
    }

    public static bool DeleteAt(ulong value, string input, ulong index)
    {
        UIntPtr session = new UIntPtr(value);
        string[] candidates = Candidates(value, input);
        return index < (ulong)candidates.Length &&
            deleteCandidate(session, new UIntPtr(index)) != 0;
    }

    public static void CloseSession(ulong value)
    {
        destroySession(new UIntPtr(value));
    }

    public static void Shutdown()
    {
        if (finalize != null) finalize();
    }
}
