const std = @import("../../../std.zig");
const windows = std.os.windows;
const crypt32 = windows.crypt32;

const api_guards = @import("../../api_guards.zig");

const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const BYTE = windows.BYTE;
const LONG = windows.LONG;
const LPCSTR = windows.LPCSTR;
const LPCWSTR = windows.LPCWSTR;
const FILETIME = windows.FILETIME;
const HANDLE = windows.HANDLE;

const CERT_STORE = crypt32.CERT_STORE;
const HCERTSTORE = crypt32.HCERTSTORE;
const CERT_CONTEXT = crypt32.CERT_CONTEXT;
const HCRYPTPROV_LEGACY = crypt32.HCRYPTPROV_LEGACY;
const ENCODING = crypt32.ENCODING;
const CERT_CLOSE_STORE_FLAG = crypt32.CERT_CLOSE_STORE_FLAG;
const HCERTCHAINENGINE = crypt32.HCERTCHAINENGINE;
const CERT_CHAIN = crypt32.CERT_CHAIN;

comptime {
    api_guards.ensureOsTag(.windows);
}

pub extern "crypt32" fn CertOpenStore(
    lpszStoreProvider: CERT_STORE.PROV,
    dwEncodingType: ENCODING.TYPE,
    hCryptProv: HCRYPTPROV_LEGACY,
    dwFlags: CERT_STORE.FLAG,
    pvPara: ?*const anyopaque,
) callconv(.winapi) ?HCERTSTORE;

pub extern "crypt32" fn CertCloseStore(
    hCertStore: HCERTSTORE,
    dwFlags: CERT_CLOSE_STORE_FLAG,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertEnumCertificatesInStore(
    hCertStore: HCERTSTORE,
    pPrevCertContext: ?*CERT_CONTEXT,
) callconv(.winapi) ?*CERT_CONTEXT;

pub extern "crypt32" fn CertFreeCertificateContext(
    pCertContext: ?*const CERT_CONTEXT,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertAddEncodedCertificateToStore(
    hCertStore: ?HCERTSTORE,
    dwCertEncodingType: ENCODING.TYPE,
    pbCertEncoded: [*]const BYTE,
    cbCertEncoded: DWORD,
    dwAddDisposition: CERT_STORE.ADD,
    ppCertContext: ?*?*const CERT_CONTEXT,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertOpenSystemStoreW(
    hProv: HCRYPTPROV_LEGACY,
    szSubsystemProtocol: LPCWSTR,
) callconv(.winapi) ?HCERTSTORE;

pub extern "crypt32" fn CertGetCertificateChain(
    hChainEngine: HCERTCHAINENGINE,
    pCertContext: *const CERT_CONTEXT,
    pTime: ?*const FILETIME,
    hAdditionalStore: ?HCERTSTORE,
    pChainPara: *const CERT_CHAIN.PARA,
    dwFlags: CERT_CHAIN,
    pvReserved: ?*const anyopaque,
    ppChainContext: **const CERT_CHAIN.CONTEXT,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertFreeCertificateChain(
    pChainContext: *const CERT_CHAIN.CONTEXT,
) callconv(.winapi) void;

pub extern "crypt32" fn CertVerifyCertificateChainPolicy(
    pszPolicyOID: CERT_CHAIN.POLICY,
    pChainContext: *const CERT_CHAIN.CONTEXT,
    pPolicyPara: *const CERT_CHAIN.POLICY.PARA,
    pPolicyStatus: *CERT_CHAIN.POLICY.STATUS,
) callconv(.winapi) BOOL;
