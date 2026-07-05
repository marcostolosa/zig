const std = @import("../../std.zig");
const windows = std.os.windows;
const externs = @import("./externs.zig");

const ACCESS_MASK = windows.ACCESS_MASK;
const ANSI_STRING = windows.ANSI_STRING;
const BOOL = windows.BOOL;
const BOOLEAN = windows.BOOLEAN;
const CONDITION_VARIABLE = windows.CONDITION_VARIABLE;
const CONTEXT = windows.CONTEXT;
const CRITICAL_SECTION = windows.CRITICAL_SECTION;
const CTL_CODE = windows.CTL_CODE;
const CURDIR = windows.CURDIR;
const DIRECTORY = windows.DIRECTORY;
const DWORD = windows.DWORD;
const DWORD64 = windows.DWORD64;
const ERESOURCE = windows.ERESOURCE;
const EVENT_TYPE = windows.EVENT_TYPE;
const EXCEPTION_ROUTINE = windows.EXCEPTION_ROUTINE;
const FILE = windows.FILE;
const FS_INFORMATION_CLASS = windows.FS_INFORMATION_CLASS;
const HANDLE = windows.HANDLE;
const HEAP = windows.HEAP;
const IO_APC_ROUTINE = windows.IO_APC_ROUTINE;
const IO_STATUS_BLOCK = windows.IO_STATUS_BLOCK;
const KEY = windows.KEY;
const KNONVOLATILE_CONTEXT_POINTERS = windows.KNONVOLATILE_CONTEXT_POINTERS;
const LARGE_INTEGER = windows.LARGE_INTEGER;
const LDR = windows.LDR;
const LOGICAL = windows.LOGICAL;
const LONG = windows.LONG;
const LPCVOID = windows.LPCVOID;
const LPVOID = windows.LPVOID;
const MEM = windows.MEM;
const NTSTATUS = windows.NTSTATUS;
const OBJECT = windows.OBJECT;
const PAGE = windows.PAGE;
const PCWSTR = windows.PCWSTR;
const PROCESS = windows.PROCESS;
const PVOID = windows.PVOID;
const PWSTR = windows.PWSTR;
const REG = windows.REG;
const RTL_OSVERSIONINFOW = windows.RTL_OSVERSIONINFOW;
const RTL_QUERY_REGISTRY_TABLE = windows.RTL_QUERY_REGISTRY_TABLE;
const RUNTIME_FUNCTION = windows.RUNTIME_FUNCTION;
const SEC = windows.SEC;
const SECTION_INHERIT = windows.SECTION_INHERIT;
const SIZE_T = windows.SIZE_T;
const SRWLOCK = windows.SRWLOCK;
const SYSTEM = windows.SYSTEM;
const THREAD = windows.THREAD;
const ULONG = windows.ULONG;
const ULONG_PTR = windows.ULONG_PTR;
const UNICODE_STRING = windows.UNICODE_STRING;
const UNWIND_HISTORY_TABLE = windows.UNWIND_HISTORY_TABLE;
const USHORT = windows.USHORT;
const VECTORED_EXCEPTION_HANDLER = windows.VECTORED_EXCEPTION_HANDLER;
const WORD = windows.WORD;
const USER_THREAD_START_ROUTINE = windows.USER_THREAD_START_ROUTINE;
const PS = windows.PS;
const TEB = windows.TEB;

// ref: km/ntifs.h

pub fn RtlCreateHeap(
    Flags: HEAP.FLAGS.CREATE,
    HeapBase: ?PVOID,
    ReserveSize: SIZE_T,
    CommitSize: SIZE_T,
    Lock: ?*ERESOURCE,
    Parameters: ?*const HEAP.RTL_PARAMETERS,
) callconv(.winapi) ?*HEAP {
    return externs.ntdll.RtlCreateHeap(
        Flags,
        HeapBase,
        ReserveSize,
        CommitSize,
        Lock,
        Parameters,
    );
}

pub fn RtlDestroyHeap(
    HeapHandle: *HEAP,
) callconv(.winapi) ?*HEAP {
    return externs.ntdll.RtlDestroyHeap(
        HeapHandle,
    );
}

pub fn RtlAllocateHeap(
    HeapHandle: *HEAP,
    Flags: HEAP.FLAGS.ALLOCATION,
    Size: SIZE_T,
) callconv(.winapi) ?PVOID {
    return externs.ntdll.RtlAllocateHeap(
        HeapHandle,
        Flags,
        Size,
    );
}

pub fn RtlFreeHeap(
    HeapHandle: *HEAP,
    Flags: HEAP.FLAGS.ALLOCATION,
    BaseAddress: ?PVOID,
) callconv(.winapi) LOGICAL {
    return externs.ntdll.RtlFreeHeap(
        HeapHandle,
        Flags,
        BaseAddress,
    );
}

pub fn RtlCaptureStackBackTrace(
    FramesToSkip: ULONG,
    FramesToCapture: ULONG,
    BackTrace: **anyopaque,
    BackTraceHash: ?*ULONG,
) callconv(.winapi) USHORT {
    return externs.ntdll.RtlCaptureStackBackTrace(
        FramesToSkip,
        FramesToCapture,
        BackTrace,
        BackTraceHash,
    );
}

pub fn RtlCaptureContext(
    ContextRecord: *CONTEXT,
) callconv(.winapi) void {
    return externs.ntdll.RtlCaptureContext(
        ContextRecord,
    );
}

pub fn NtSetInformationThread(
    ThreadHandle: HANDLE,
    ThreadInformationClass: THREAD.INFOCLASS,
    ThreadInformation: *const anyopaque,
    ThreadInformationLength: ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtSetInformationThread(
        ThreadHandle,
        ThreadInformationClass,
        ThreadInformation,
        ThreadInformationLength,
    );
}

pub fn NtCreateFile(
    FileHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    IoStatusBlock: *IO_STATUS_BLOCK,
    AllocationSize: ?*const LARGE_INTEGER,
    FileAttributes: FILE.ATTRIBUTE,
    ShareAccess: FILE.SHARE,
    CreateDisposition: FILE.CREATE_DISPOSITION,
    CreateOptions: FILE.MODE,
    EaBuffer: ?*const anyopaque,
    EaLength: ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCreateFile(
        FileHandle,
        DesiredAccess,
        ObjectAttributes,
        IoStatusBlock,
        AllocationSize,
        FileAttributes,
        ShareAccess,
        CreateDisposition,
        CreateOptions,
        EaBuffer,
        EaLength,
    );
}

pub fn NtDeviceIoControlFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    IoControlCode: CTL_CODE,
    InputBuffer: ?*const anyopaque,
    InputBufferLength: ULONG,
    OutputBuffer: ?PVOID,
    OutputBufferLength: ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtDeviceIoControlFile(
        FileHandle,
        Event,
        ApcRoutine,
        ApcContext,
        IoStatusBlock,
        IoControlCode,
        InputBuffer,
        InputBufferLength,
        OutputBuffer,
        OutputBufferLength,
    );
}

pub fn NtFsControlFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FsControlCode: CTL_CODE,
    InputBuffer: ?*const anyopaque,
    InputBufferLength: ULONG,
    OutputBuffer: ?PVOID,
    OutputBufferLength: ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtFsControlFile(
        FileHandle,
        Event,
        ApcRoutine,
        ApcContext,
        IoStatusBlock,
        FsControlCode,
        InputBuffer,
        InputBufferLength,
        OutputBuffer,
        OutputBufferLength,
    );
}

pub fn NtLockFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ByteOffset: *const LARGE_INTEGER,
    Length: *const LARGE_INTEGER,
    Key: ?*const ULONG,
    FailImmediately: BOOLEAN,
    ExclusiveLock: BOOLEAN,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtLockFile(
        FileHandle,
        Event,
        ApcRoutine,
        ApcContext,
        IoStatusBlock,
        ByteOffset,
        Length,
        Key,
        FailImmediately,
        ExclusiveLock,
    );
}

pub fn NtOpenFile(
    FileHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ShareAccess: FILE.SHARE,
    OpenOptions: FILE.MODE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtOpenFile(
        FileHandle,
        DesiredAccess,
        ObjectAttributes,
        IoStatusBlock,
        ShareAccess,
        OpenOptions,
    );
}

pub fn NtQueryDirectoryFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FileInformation: *anyopaque,
    Length: ULONG,
    FileInformationClass: FILE.INFORMATION_CLASS,
    ReturnSingleEntry: BOOLEAN,
    FileName: ?*const UNICODE_STRING,
    RestartScan: BOOLEAN,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryDirectoryFile(FileHandle, Event, ApcRoutine, ApcContext, IoStatusBlock, FileInformation, Length, FileInformationClass, ReturnSingleEntry, FileName, RestartScan);
}

pub fn NtQueryInformationFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FileInformation: *anyopaque,
    Length: ULONG,
    FileInformationClass: FILE.INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryInformationFile(
        FileHandle,
        IoStatusBlock,
        FileInformation,
        Length,
        FileInformationClass,
    );
}

pub fn NtQueryVolumeInformationFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FsInformation: *anyopaque,
    Length: ULONG,
    FsInformationClass: FS_INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryVolumeInformationFile(
        FileHandle,
        IoStatusBlock,
        FsInformation,
        Length,
        FsInformationClass,
    );
}

pub fn NtReadFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    Buffer: *anyopaque,
    Length: ULONG,
    ByteOffset: ?*const LARGE_INTEGER,
    Key: ?*const ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtReadFile(
        FileHandle,
        Event,
        ApcRoutine,
        ApcContext,
        IoStatusBlock,
        Buffer,
        Length,
        ByteOffset,
        Key,
    );
}

pub fn NtSetInformationFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    /// This can't be const as providing read-only memory could result in ACCESS_VIOLATION
    /// in certain scenarios. This has been seen when using FILE_DISPOSITION_INFORMATION_EX
    /// and targeting x86-windows.
    FileInformation: *anyopaque,
    Length: ULONG,
    FileInformationClass: FILE.INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtSetInformationFile(
        FileHandle,
        IoStatusBlock,
        FileInformation,
        Length,
        FileInformationClass,
    );
}

pub fn NtWriteFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    Buffer: *const anyopaque,
    Length: ULONG,
    ByteOffset: ?*const LARGE_INTEGER,
    Key: ?*const ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtWriteFile(
        FileHandle,
        Event,
        ApcRoutine,
        ApcContext,
        IoStatusBlock,
        Buffer,
        Length,
        ByteOffset,
        Key,
    );
}

pub fn NtUnlockFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ByteOffset: *const LARGE_INTEGER,
    Length: *const LARGE_INTEGER,
    Key: ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtUnlockFile(
        FileHandle,
        IoStatusBlock,
        ByteOffset,
        Length,
        Key,
    );
}

pub fn NtQueryObject(
    Handle: HANDLE,
    ObjectInformationClass: OBJECT.INFORMATION_CLASS,
    ObjectInformation: ?PVOID,
    ObjectInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryObject(
        Handle,
        ObjectInformationClass,
        ObjectInformation,
        ObjectInformationLength,
        ReturnLength,
    );
}

pub fn NtClose(
    Handle: HANDLE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtClose(
        Handle,
    );
}

pub fn NtCreateSection(
    SectionHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: ?*const OBJECT.ATTRIBUTES,
    MaximumSize: ?*const LARGE_INTEGER,
    SectionPageProtection: PAGE,
    AllocationAttributes: SEC,
    FileHandle: ?HANDLE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCreateSection(
        SectionHandle,
        DesiredAccess,
        ObjectAttributes,
        MaximumSize,
        SectionPageProtection,
        AllocationAttributes,
        FileHandle,
    );
}

pub fn NtExtendSection(
    SectionHandle: HANDLE,
    NewSectionSize: *LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtExtendSection(
        SectionHandle,
        NewSectionSize,
    );
}

pub fn NtAllocateVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: *PVOID,
    ZeroBits: ULONG_PTR,
    RegionSize: *SIZE_T,
    AllocationType: MEM.ALLOCATE,
    Protect: PAGE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtAllocateVirtualMemory(
        ProcessHandle,
        BaseAddress,
        ZeroBits,
        RegionSize,
        AllocationType,
        Protect,
    );
}

pub fn NtFreeVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: *PVOID,
    RegionSize: *SIZE_T,
    FreeType: MEM.FREE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtFreeVirtualMemory(
        ProcessHandle,
        BaseAddress,
        RegionSize,
        FreeType,
    );
}

// ref: km/wdm.h

pub fn RtlQueryRegistryValues(
    RelativeTo: ULONG,
    Path: PCWSTR,
    QueryTable: [*]RTL_QUERY_REGISTRY_TABLE,
    Context: ?*const anyopaque,
    Environment: ?*const anyopaque,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlQueryRegistryValues(
        RelativeTo,
        Path,
        QueryTable,
        Context,
        Environment,
    );
}

pub fn RtlEqualUnicodeString(
    String1: *const UNICODE_STRING,
    String2: *const UNICODE_STRING,
    CaseInSensitive: BOOLEAN,
) callconv(.winapi) BOOLEAN {
    return externs.ntdll.RtlEqualUnicodeString(
        String1,
        String2,
        CaseInSensitive,
    );
}

pub fn RtlUpcaseUnicodeChar(
    SourceCharacter: u16,
) callconv(.winapi) u16 {
    return externs.ntdll.RtlUpcaseUnicodeChar(
        SourceCharacter,
    );
}

pub fn RtlFreeUnicodeString(
    UnicodeString: *UNICODE_STRING,
) callconv(.winapi) void {
    return externs.ntdll.RtlFreeUnicodeString(
        UnicodeString,
    );
}

pub fn RtlGetVersion(
    lpVersionInformation: *RTL_OSVERSIONINFOW,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlGetVersion(
        lpVersionInformation,
    );
}

// ref: um/winnt.h

pub fn RtlLookupFunctionEntry(
    ControlPc: usize,
    ImageBase: *usize,
    HistoryTable: *UNWIND_HISTORY_TABLE,
) callconv(.winapi) ?*RUNTIME_FUNCTION {
    return externs.ntdll.RtlLookupFunctionEntry(
        ControlPc,
        ImageBase,
        HistoryTable,
    );
}

pub fn RtlVirtualUnwind(
    HandlerType: DWORD,
    ImageBase: usize,
    ControlPc: usize,
    FunctionEntry: *RUNTIME_FUNCTION,
    ContextRecord: *CONTEXT,
    HandlerData: *?PVOID,
    EstablisherFrame: *usize,
    ContextPointers: ?*KNONVOLATILE_CONTEXT_POINTERS,
) callconv(.winapi) *EXCEPTION_ROUTINE {
    return externs.ntdll.RtlVirtualUnwind(
        HandlerType,
        ImageBase,
        ControlPc,
        FunctionEntry,
        ContextRecord,
        HandlerData,
        EstablisherFrame,
        ContextPointers,
    );
}

// ref: um/winternl.h

pub fn NtWaitForSingleObject(
    Handle: HANDLE,
    Alertable: BOOLEAN,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtWaitForSingleObject(
        Handle,
        Alertable,
        Timeout,
    );
}

pub fn NtQueryInformationProcess(
    ProcessHandle: HANDLE,
    ProcessInformationClass: PROCESS.INFOCLASS,
    ProcessInformation: *anyopaque,
    ProcessInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryInformationProcess(
        ProcessHandle,
        ProcessInformationClass,
        ProcessInformation,
        ProcessInformationLength,
        ReturnLength,
    );
}

pub fn NtQueryInformationThread(
    ThreadHandle: HANDLE,
    ThreadInformationClass: THREAD.INFOCLASS,
    ThreadInformation: *anyopaque,
    ThreadInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryInformationThread(
        ThreadHandle,
        ThreadInformationClass,
        ThreadInformation,
        ThreadInformationLength,
        ReturnLength,
    );
}

pub fn NtQuerySystemInformation(
    SystemInformationClass: SYSTEM.INFORMATION_CLASS,
    SystemInformation: PVOID,
    SystemInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQuerySystemInformation(
        SystemInformationClass,
        SystemInformation,
        SystemInformationLength,
        ReturnLength,
    );
}

// ref none

pub fn RtlGetActiveActivationContext(
    ActivationContext: *?HANDLE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlGetActiveActivationContext(
        ActivationContext,
    );
}

pub fn RtlActivateActivationContextEx(
    Flags: ULONG,
    Teb: *TEB,
    ActivationContext: HANDLE,
    Cookie: *ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlActivateActivationContextEx(
        Flags,
        Teb,
        ActivationContext,
        Cookie,
    );
}

pub fn RtlReleaseActivationContext(
    ActivationContext: HANDLE,
) callconv(.winapi) void {
    return externs.ntdll.RtlReleaseActivationContext(
        ActivationContext,
    );
}

pub fn LdrAddRefDll(
    Flags: ULONG,
    DllHandle: PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrAddRefDll(
        Flags,
        DllHandle,
    );
}

pub fn LdrLoadDll(
    DllPath: ?PCWSTR,
    DllCharacteristics: ?*const ULONG,
    DllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrLoadDll(
        DllPath,
        DllCharacteristics,
        DllName,
        DllHandle,
    );
}
pub fn LdrUnloadDll(
    DllHandle: PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrUnloadDll(
        DllHandle,
    );
}

pub fn LdrFindEntryForAddress(
    DllHandle: PVOID,
    Entry: **LDR.DATA_TABLE_ENTRY,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrFindEntryForAddress(
        DllHandle,
        Entry,
    );
}
pub fn LdrGetDllFullName(
    DllHandle: ?PVOID,
    FullDllName: *UNICODE_STRING,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetDllFullName(
        DllHandle,
        FullDllName,
    );
}
pub fn LdrGetDllPath(
    DllName: PCWSTR,
    Flags: LDR.LOAD,
    DllPath: *PWSTR,
    SearchPaths: *PWSTR,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetDllPath(
        DllName,
        Flags,
        DllPath,
        SearchPaths,
    );
}

pub fn LdrGetDllHandle(
    DllPath: ?PCWSTR,
    DllCharacteristics: ?*const ULONG,
    DllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetDllHandle(
        DllPath,
        DllCharacteristics,
        DllName,
        DllHandle,
    );
}
pub fn LdrGetDllHandleByMapping(
    BaseAddress: PVOID,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetDllHandleByMapping(
        BaseAddress,
        DllHandle,
    );
}
pub fn LdrGetDllHandleByName(
    BaseDllName: *const UNICODE_STRING,
    FullDllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetDllHandleByName(
        BaseDllName,
        FullDllName,
        DllHandle,
    );
}
pub fn LdrGetDllHandleEx(
    Flags: LDR.GET_DLL_HANDLE_EX,
    DllPath: ?PCWSTR,
    DllCharacteristics: ?*const ULONG,
    DllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetDllHandleEx(
        Flags,
        DllPath,
        DllCharacteristics,
        DllName,
        DllHandle,
    );
}

pub fn LdrGetProcedureAddress(
    DllHandle: PVOID,
    ProcedureName: *const ANSI_STRING,
    ProcedureNumber: ULONG,
    ProcedureAddress: *PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetProcedureAddress(
        DllHandle,
        ProcedureName,
        ProcedureNumber,
        ProcedureAddress,
    );
}
pub fn LdrGetProcedureAddressEx(
    DllHandle: PVOID,
    ProcedureName: *const ANSI_STRING,
    ProcedureNumber: ULONG,
    ProcedureAddress: *PVOID,
    Flags: LDR.GET_PROCEDURE_ADDRESS,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetProcedureAddressEx(
        DllHandle,
        ProcedureName,
        ProcedureNumber,
        ProcedureAddress,
        Flags,
    );
}
pub fn LdrGetProcedureAddressForCaller(
    DllHandle: PVOID,
    ProcedureName: *const ANSI_STRING,
    ProcedureNumber: ULONG,
    ProcedureAddress: *PVOID,
    Flags: LDR.GET_PROCEDURE_ADDRESS,
    CallerAddress: PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrGetProcedureAddressForCaller(
        DllHandle,
        ProcedureName,
        ProcedureNumber,
        ProcedureAddress,
        Flags,
        CallerAddress,
    );
}

pub fn LdrRegisterDllNotification(
    Flags: LDR.DLL_NOTIFICATION.REGISTER,
    NotificationFunction: *const LDR.DLL_NOTIFICATION.FUNCTION,
    Context: ?PVOID,
    Cookie: *LDR.DLL_NOTIFICATION.COOKIE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrRegisterDllNotification(
        Flags,
        NotificationFunction,
        Context,
        Cookie,
    );
}
pub fn LdrUnregisterDllNotification(
    Cookie: LDR.DLL_NOTIFICATION.COOKIE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.LdrUnregisterDllNotification(
        Cookie,
    );
}

pub fn NtQueryAttributesFile(
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    FileAttributes: *FILE.BASIC_INFORMATION,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryAttributesFile(
        ObjectAttributes,
        FileAttributes,
    );
}

pub fn NtCreateEvent(
    EventHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: ?*const OBJECT.ATTRIBUTES,
    EventType: EVENT_TYPE,
    InitialState: BOOLEAN,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCreateEvent(
        EventHandle,
        DesiredAccess,
        ObjectAttributes,
        EventType,
        InitialState,
    );
}
pub fn NtSetEvent(
    EventHandle: HANDLE,
    PreviousState: ?*LONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtSetEvent(
        EventHandle,
        PreviousState,
    );
}

pub fn NtCreateKeyedEvent(
    KeyedEventHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: ?*const OBJECT.ATTRIBUTES,
    Flags: ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCreateKeyedEvent(
        KeyedEventHandle,
        DesiredAccess,
        ObjectAttributes,
        Flags,
    );
}
pub fn NtReleaseKeyedEvent(
    EventHandle: ?HANDLE,
    Key: ?*const anyopaque,
    Alertable: BOOLEAN,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtReleaseKeyedEvent(
        EventHandle,
        Key,
        Alertable,
        Timeout,
    );
}
pub fn NtWaitForKeyedEvent(
    EventHandle: ?HANDLE,
    Key: ?*const anyopaque,
    Alertable: BOOLEAN,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtWaitForKeyedEvent(
        EventHandle,
        Key,
        Alertable,
        Timeout,
    );
}

pub fn NtCancelSynchronousIoFile(
    ThreadHandle: HANDLE,
    IoRequestToCancel: ?*IO_STATUS_BLOCK,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCancelSynchronousIoFile(
        ThreadHandle,
        IoRequestToCancel,
        IoStatusBlock,
    );
}
pub fn NtCancelIoFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCancelIoFile(
        FileHandle,
        IoStatusBlock,
    );
}
pub fn NtCancelIoFileEx(
    FileHandle: HANDLE,
    IoRequestToCancel: *const IO_STATUS_BLOCK,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCancelIoFileEx(
        FileHandle,
        IoRequestToCancel,
        IoStatusBlock,
    );
}

/// This function has been observed to return SUCCESS on timeout on Windows 10
/// and TIMEOUT on Wine 10.0.
///
/// This function has been observed on Windows 11 such that positive interval
/// is real time, which can cause waits to be interrupted by changing system
/// time, however negative intervals are not affected by changes to system
/// time.
pub fn NtDelayExecution(
    Alertable: BOOLEAN,
    DelayInterval: *const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtDelayExecution(
        Alertable,
        DelayInterval,
    );
}

pub fn NtNotifyChangeDirectoryFileEx(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    Buffer: *anyopaque,
    Length: ULONG,
    CompletionFilter: FILE.NOTIFY.CHANGE,
    WatchTree: BOOLEAN,
    DirectoryNotifyInformationClass: DIRECTORY.NOTIFY_INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtNotifyChangeDirectoryFileEx(
        FileHandle,
        Event,
        ApcRoutine,
        ApcContext,
        IoStatusBlock,
        Buffer,
        Length,
        CompletionFilter,
        WatchTree,
        DirectoryNotifyInformationClass,
    );
}

pub fn NtOpenThread(
    ThreadHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    ClientId: *const windows.CLIENT_ID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtOpenThread(
        ThreadHandle,
        DesiredAccess,
        ObjectAttributes,
        ClientId,
    );
}

pub fn NtCreateNamedPipeFile(
    FileHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ShareAccess: FILE.SHARE,
    CreateDisposition: FILE.CREATE_DISPOSITION,
    CreateOptions: FILE.MODE,
    NamedPipeType: FILE.PIPE.TYPE,
    ReadMode: FILE.PIPE.READ_MODE,
    CompletionMode: FILE.PIPE.COMPLETION_MODE,
    MaximumInstances: ULONG,
    InboundQuota: ULONG,
    OutboundQuota: ULONG,
    DefaultTimeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCreateNamedPipeFile(
        FileHandle,
        DesiredAccess,
        ObjectAttributes,
        IoStatusBlock,
        ShareAccess,
        CreateDisposition,
        CreateOptions,
        NamedPipeType,
        ReadMode,
        CompletionMode,
        MaximumInstances,
        InboundQuota,
        OutboundQuota,
        DefaultTimeout,
    );
}

pub fn NtFlushBuffersFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtFlushBuffersFile(
        FileHandle,
        IoStatusBlock,
    );
}

pub fn NtMapViewOfSection(
    SectionHandle: HANDLE,
    ProcessHandle: HANDLE,
    BaseAddress: ?*PVOID,
    ZeroBits: ?*const ULONG,
    CommitSize: SIZE_T,
    SectionOffset: ?*LARGE_INTEGER,
    ViewSize: *SIZE_T,
    InheritDispostion: SECTION_INHERIT,
    AllocationType: MEM.MAP,
    PageProtection: PAGE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtMapViewOfSection(
        SectionHandle,
        ProcessHandle,
        BaseAddress,
        ZeroBits,
        CommitSize,
        SectionOffset,
        ViewSize,
        InheritDispostion,
        AllocationType,
        PageProtection,
    );
}
pub fn NtUnmapViewOfSection(
    ProcessHandle: HANDLE,
    BaseAddress: PVOID,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtUnmapViewOfSection(
        ProcessHandle,
        BaseAddress,
    );
}
pub fn NtUnmapViewOfSectionEx(
    ProcessHandle: HANDLE,
    BaseAddress: PVOID,
    UnmapFlags: MEM.UNMAP,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtUnmapViewOfSectionEx(
        ProcessHandle,
        BaseAddress,
        UnmapFlags,
    );
}

pub fn NtOpenKey(
    KeyHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtOpenKey(
        KeyHandle,
        DesiredAccess,
        ObjectAttributes,
    );
}

pub fn NtQueueApcThread(
    ThreadHandle: HANDLE,
    ApcRoutine: *const IO_APC_ROUTINE,
    ApcArgument1: ?*anyopaque,
    ApcArgument2: ?*anyopaque,
    ApcArgument3: ?*anyopaque,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueueApcThread(
        ThreadHandle,
        ApcRoutine,
        ApcArgument1,
        ApcArgument2,
        ApcArgument3,
    );
}

pub fn NtReadVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: ?PVOID,
    Buffer: LPVOID,
    NumberOfBytesToRead: SIZE_T,
    NumberOfBytesRead: ?*SIZE_T,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtReadVirtualMemory(
        ProcessHandle,
        BaseAddress,
        Buffer,
        NumberOfBytesToRead,
        NumberOfBytesRead,
    );
}
pub fn NtWriteVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: ?PVOID,
    Buffer: LPCVOID,
    NumberOfBytesToWrite: SIZE_T,
    NumberOfBytesWritten: ?*SIZE_T,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtWriteVirtualMemory(
        ProcessHandle,
        BaseAddress,
        Buffer,
        NumberOfBytesToWrite,
        NumberOfBytesWritten,
    );
}
pub fn NtProtectVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: *?PVOID,
    NumberOfBytesToProtect: *SIZE_T,
    NewAccessProtection: PAGE,
    OldAccessProtection: *PAGE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtProtectVirtualMemory(
        ProcessHandle,
        BaseAddress,
        NumberOfBytesToProtect,
        NewAccessProtection,
        OldAccessProtection,
    );
}

pub fn NtWaitForAlertByThreadId(
    Address: ?*const anyopaque,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtWaitForAlertByThreadId(
        Address,
        Timeout,
    );
}
pub fn NtAlertThreadByThreadId(ThreadId: DWORD) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtAlertThreadByThreadId(
        ThreadId,
    );
}
pub fn NtAlertThread(ThreadHandle: HANDLE) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtAlertThread(ThreadHandle);
}
pub fn NtAlertMultipleThreadByThreadId(
    ThreadIds: [*]const ULONG_PTR,
    ThreadCount: ULONG,
    Unknown1: ?*const anyopaque,
    Unknown2: ?*const anyopaque,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtAlertMultipleThreadByThreadId(
        ThreadIds,
        ThreadCount,
        Unknown1,
        Unknown2,
    );
}

pub fn NtYieldExecution() callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtYieldExecution();
}

pub fn RtlAddVectoredExceptionHandler(
    First: ULONG,
    Handler: ?VECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) ?LPVOID {
    return externs.ntdll.RtlAddVectoredExceptionHandler(
        First,
        Handler,
    );
}
pub fn RtlRemoveVectoredExceptionHandler(
    Handle: HANDLE,
) callconv(.winapi) ULONG {
    return externs.ntdll.RtlRemoveVectoredExceptionHandler(
        Handle,
    );
}

pub fn RtlDosPathNameToNtPathName_U(
    DosPathName: [*:0]const u16,
    NtPathName: *UNICODE_STRING,
    NtFileNamePart: ?*?[*:0]const u16,
    DirectoryInfo: ?*CURDIR,
) callconv(.winapi) BOOL {
    return externs.ntdll.RtlDosPathNameToNtPathName_U(
        DosPathName,
        NtPathName,
        NtFileNamePart,
        DirectoryInfo,
    );
}

pub fn RtlExitUserProcess(
    ExitStatus: u32,
) callconv(.winapi) noreturn {
    return externs.ntdll.RtlExitUserProcess(
        ExitStatus,
    );
}

/// Returns the number of bytes written to `Buffer`.
/// If the returned count is larger than `BufferByteLength`, the buffer was too small.
/// If the returned count is zero, an error occurred.
pub fn RtlGetFullPathName_U(
    FileName: [*:0]const u16,
    BufferByteLength: ULONG,
    Buffer: [*]u16,
    ShortName: ?*[*:0]const u16,
) callconv(.winapi) ULONG {
    return externs.ntdll.RtlGetFullPathName_U(
        FileName,
        BufferByteLength,
        Buffer,
        ShortName,
    );
}

pub fn RtlGetCurrentDirectory_U(
    BufferByteLength: ULONG,
    Buffer: [*]u16,
) callconv(.winapi) ULONG {
    return externs.ntdll.RtlGetCurrentDirectory_U(
        BufferByteLength,
        Buffer,
    );
}

pub fn RtlGetSystemTimePrecise() callconv(.winapi) LARGE_INTEGER {
    return externs.ntdll.RtlGetSystemTimePrecise();
}

pub fn RtlInitializeCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlInitializeCriticalSection(
        lpCriticalSection,
    );
}
pub fn RtlEnterCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlEnterCriticalSection(
        lpCriticalSection,
    );
}
pub fn RtlLeaveCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlLeaveCriticalSection(
        lpCriticalSection,
    );
}
pub fn RtlDeleteCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlDeleteCriticalSection(
        lpCriticalSection,
    );
}

pub fn RtlQueryPerformanceCounter(
    PerformanceCounter: *LARGE_INTEGER,
) callconv(.winapi) BOOL {
    return externs.ntdll.RtlQueryPerformanceCounter(
        PerformanceCounter,
    );
}
pub fn RtlQueryPerformanceFrequency(
    PerformanceFrequency: *LARGE_INTEGER,
) callconv(.winapi) BOOL {
    return externs.ntdll.RtlQueryPerformanceFrequency(
        PerformanceFrequency,
    );
}

pub fn RtlReAllocateHeap(
    HeapHandle: *HEAP,
    Flags: HEAP.FLAGS.ALLOCATION,
    BaseAddress: ?PVOID,
    Size: SIZE_T,
) callconv(.winapi) ?PVOID {
    return externs.ntdll.RtlReAllocateHeap(
        HeapHandle,
        Flags,
        BaseAddress,
        Size,
    );
}

pub fn RtlReportSilentProcessExit(
    ProcessHandle: HANDLE,
    ExitStatus: NTSTATUS,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlReportSilentProcessExit(
        ProcessHandle,
        ExitStatus,
    );
}
pub fn NtTerminateProcess(
    ProcessHandle: ?HANDLE,
    ExitStatus: NTSTATUS,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtTerminateProcess(
        ProcessHandle,
        ExitStatus,
    );
}

pub fn RtlSetCurrentDirectory_U(
    PathName: *const UNICODE_STRING,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlSetCurrentDirectory_U(
        PathName,
    );
}

pub fn RtlTryAcquireSRWLockExclusive(
    SRWLock: *SRWLOCK,
) callconv(.winapi) BOOLEAN {
    return externs.ntdll.RtlTryAcquireSRWLockExclusive(
        SRWLock,
    );
}
pub fn RtlAcquireSRWLockExclusive(
    SRWLock: *SRWLOCK,
) callconv(.winapi) void {
    return externs.ntdll.RtlAcquireSRWLockExclusive(
        SRWLock,
    );
}
pub fn RtlReleaseSRWLockExclusive(
    SRWLock: *SRWLOCK,
) callconv(.winapi) void {
    return externs.ntdll.RtlReleaseSRWLockExclusive(
        SRWLock,
    );
}

pub fn RtlWakeAddressAll(
    Address: ?*const anyopaque,
) callconv(.winapi) void {
    return externs.ntdll.RtlWakeAddressAll(
        Address,
    );
}
pub fn RtlWakeAddressSingle(
    Address: ?*const anyopaque,
) callconv(.winapi) void {
    return externs.ntdll.RtlWakeAddressSingle(
        Address,
    );
}
pub fn RtlWaitOnAddress(
    Address: ?*const anyopaque,
    CompareAddress: ?*const anyopaque,
    AddressSize: SIZE_T,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlWaitOnAddress(
        Address,
        CompareAddress,
        AddressSize,
        Timeout,
    );
}

pub fn RtlWakeConditionVariable(
    ConditionVariable: *CONDITION_VARIABLE,
) callconv(.winapi) void {
    return externs.ntdll.RtlWakeConditionVariable(
        ConditionVariable,
    );
}
pub fn RtlWakeAllConditionVariable(
    ConditionVariable: *CONDITION_VARIABLE,
) callconv(.winapi) void {
    return externs.ntdll.RtlWakeAllConditionVariable(
        ConditionVariable,
    );
}

pub fn NtOpenKeyEx(
    KeyHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    OpenOptions: REG.OpenOptions,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtOpenKeyEx(
        KeyHandle,
        DesiredAccess,
        ObjectAttributes,
        OpenOptions,
    );
}
pub fn RtlOpenCurrentUser(
    DesiredAccess: ACCESS_MASK,
    CurrentUserKey: *HANDLE,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.RtlOpenCurrentUser(
        DesiredAccess,
        CurrentUserKey,
    );
}
pub fn NtQueryValueKey(
    KeyHandle: HANDLE,
    ValueName: *const UNICODE_STRING,
    KeyValueInformationClass: KEY.VALUE.INFORMATION_CLASS,
    KeyValueInformation: *anyopaque,
    /// Length of KeyValueInformation buffer in bytes
    Length: ULONG,
    /// On STATUS_SUCCESS, contains the length of the populated portion of the
    /// provided buffer. On STATUS_BUFFER_OVERFLOW or STATUS_BUFFER_TOO_SMALL,
    /// contains the minimum `Length` value that would be required to hold the information.
    ResultLength: *ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtQueryValueKey(
        KeyHandle,
        ValueName,
        KeyValueInformationClass,
        KeyValueInformation,
        Length,
        ResultLength,
    );
}
pub fn NtLoadKeyEx(
    TargetKey: *const OBJECT.ATTRIBUTES,
    SourceFile: *const OBJECT.ATTRIBUTES,
    Flags: REG.LoadOptions,
    TrustClassKey: ?HANDLE,
    Event: ?HANDLE,
    DesiredAccess: ACCESS_MASK,
    RootHandle: ?*HANDLE,
    Reserved: ?*anyopaque,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtLoadKeyEx(
        TargetKey,
        SourceFile,
        Flags,
        TrustClassKey,
        Event,
        DesiredAccess,
        RootHandle,
        Reserved,
    );
}

pub fn NtCreateThreadEx(
    ThreadHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    ProcessHandle: HANDLE,
    StartRoutine: *const USER_THREAD_START_ROUTINE,
    Argument: ?PVOID,
    CreateFlags: THREAD.CREATE_FLAGS,
    ZeroBits: SIZE_T,
    /// This value is rounded up to the nearest page.
    /// If this value is larger than `StackReserve`, the reserved stack
    /// size will be the rounded value of this parameter.
    /// https://learn.microsoft.com/en-us/windows/win32/procthread/thread-stack-size
    StackCommit: THREAD.StackSize,
    StackReserve: THREAD.StackSize,
    AttributeList: ?*PS.ATTRIBUTE.LIST,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtCreateThreadEx(
        ThreadHandle,
        DesiredAccess,
        ObjectAttributes,
        ProcessHandle,
        StartRoutine,
        Argument,
        CreateFlags,
        ZeroBits,
        StackCommit,
        StackReserve,
        AttributeList,
    );
}

pub fn NtResumeThread(
    ThreadHandle: HANDLE,
    PreviousSuspendCount: ?*ULONG,
) callconv(.winapi) NTSTATUS {
    return externs.ntdll.NtResumeThread(
        ThreadHandle,
        PreviousSuspendCount,
    );
}
