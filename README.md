# LightPDF Editor — Reverse Engineering & Licensing Bypass

> **Disclaimer:** This is an educational reversing walkthrough. All research was conducted against software the author owns. Do not use this to infringe on software licenses.

A complete walkthrough of reverse engineering LightPDF Editor v2.16.8.8 (Windows, x86) to understand its licensing system, decrypt its license files, and forge a lifetime commercial premium license.

---

## Table of Contents

- [Overview](#overview)
- [Tools Used](#tools-used)
- [Phase 1: Reconnaissance](#phase-1-reconnaissance)
- [Phase 2: Decompilation](#phase-2-decompilation)
- [Phase 3: Architecture Mapping](#phase-3-architecture-mapping)
- [Phase 4: License File Decryption](#phase-4-license-file-decryption)
- [Phase 5: License Validation Flow](#phase-5-license-validation-flow)
- [Phase 6: The Bypass](#phase-6-the-bypass)
- [Phase 7: Forging a License](#phase-7-forging-a-license)
- [File Reference](#file-reference)
- [Usage](#usage)
- [Key Takeaways](#key-takeaways)

---

## Overview

LightPDF Editor is a desktop PDF editing application. The installed version is 2.16.8.8, with the main native executable being a Qt5 C++ application (~41MB). The license validation system lives in a WPF .NET assembly called `Apowersoft.CommUtilities.Native.dll` (~5.6MB) that's loaded via a C++/CLI bridge DLL.

**The licensing architecture at a glance:**

```
LightPDF Editor.exe (Qt5 native, C++)
        |
        v
CommonLib.dll (C++/CLI bridge)
        |
        v
Apowersoft.CommUtilities.Native.dll (.NET WPF, C#)
        |
        ├── Passport class (main licensing controller)
        ├── ActiveServer / AccountServer (HTTP API clients)
        ├── PassportLicenseInfo / PassportBaseLicenseInfo (license data models)
        └── Utils (DES encryption for local license file)
```

---

## Tools Used

| Tool | Purpose |
|------|---------|
| `ilspycmd` | .NET decompiler (ILSpy CLI) — `dotnet tool install -g ilspycmd` |
| `dnSpy` | Alternative .NET decompiler/debugger (GUI) |
| Process Explorer / Process Monitor | Runtime analysis of file/network access |
| `pwsh` (PowerShell) | DES encryption, hosts modification, automation |
| VS Code / hex editor | Binary analysis, script writing |

---

## Phase 1: Reconnaissance

### 1.1 Install Location

The app installs to:

```
C:\Program Files (x86)\LightPDF\LightPDF Editor\
```

Listing the directory shows 130+ files — dominated by .NET DLLs, Qt5 DLLs, and resources.

### 1.2 Identifying the Main Entries

The file sizes tell the story:

```
LightPDF Editor.exe        (41 MB)   — Qt5 native executable (C++)
CommonLib.dll              (1.5 MB)  — C++/CLI bridge DLL
Apowersoft.CommUtilities.Native.dll  (5.6 MB) — .NET WPF licensing assembly
Apowersoft.CommUtilities.dll         (2.3 MB) — VB.NET utilities (older, marked [Obsolete])
Apowersoft.CommUtilities.Base.V2.dll  — "Unlimited" client variant
```

**Key insight:** The executable is 41MB of native C++ Qt5 code, meaning the core PDF processing is native. But licensing is delegated to managed .NET assemblies. This is a common pattern: the native app imports `CommonLib.dll` which bridges to the .NET `Apowersoft.CommUtilities.Native.dll` for all licensing operations.

### 1.3 Runtime Monitoring

During app startup, `procmon` reveals:
- Reads `%APPDATA%\LightPDF\LightPDF Editor\passport.userinfo`
- Makes HTTP connections to `gw.aoscdn.com`, `aw.aoscdn.com`, `checkout.aoscdn.com`
- Writes back to `passport.userinfo` after initialization

This confirms the license state is persisted locally and validated against remote servers.

---

## Phase 2: Decompilation

### 2.1 Decompiling the .NET Assembly

Using `ilspycmd` to decompile the licensing DLL:

```powershell
ilspycmd -p "C:\Program Files (x86)\LightPDF\LightPDF Editor\Apowersoft.CommUtilities.Native.dll" -o ./ilspy_output
```

This generates a full C# project (`Apowersoft.CommUtilities.Native.csproj`) with all decompiled source files, organized by namespace:

```
ilspy_output/
├── Apowersoft.CommUtilities.Native/
│   ├── Passport/
│   │   ├── Passport.cs           # Main licensing controller
│   │   ├── PassportBaseLicenseInfo.cs
│   │   ├── PassportLicenseInfo.cs
│   │   ├── ActiveServer.cs       # License API client
│   │   ├── AccountServer.cs      # Auth API client
│   │   └── ...
│   ├── Http/
│   │   ├── HttpHelperEx.cs
│   │   └── ...
│   └── Config.cs                 # Endpoint configuration
├── Apowersoft.CommUtilities.Native.csproj
└── ...
```

---

## Phase 3: Architecture Mapping

### 3.1 The Passport Class

`Apowersoft.CommUtilities.Native.Passport.Passport` is the central licensing controller — a singleton. Key members:

| Member | Type | Purpose |
|--------|------|---------|
| `PassportInfo` | Property (object) | The entire license + user data state |
| `IsActive` | Property (get/set) | Controls whether premium features are enabled |
| `IsLogin` | Property (get/set) | Whether user is authenticated |
| `RemainDays` | Property (get) | Days remaining on license |
| `IsLifeTime` | Property (get) | Whether license is lifetime |

### 3.2 The Data Models

**`PassportInfo`** — Top-level container:

```
PassportInfo
├── license_info (PassportLicenseInfo)
├── group_licese_info (PassportLicenseInfo)
├── user_info (PassportUserInfo)
├── activate_key_info (PassportActivateKeyInfo)
└── fuction_code_activate_key_infos (List<FuctionCodeActivateKeyInfo>)
```

**`PassportBaseLicenseInfo`** — License fields:

| Field | Type | Purpose |
|-------|------|---------|
| `passport_license_type` | string | `"trial"`, `"monthly"`, `"yearly"`, `"lifetime"` |
| `product_license_type` | string | `"free"`, `"personal"`, `"commercial"` |
| `is_activated` | int | 1 if activated, 0 otherwise |
| `remained_seconds` | long | Seconds remaining |
| `expire_at` | string | Expiry date/timestamp |
| `is_lifetime` | bool (computed) | `passport_license_type.Contains("lifetime")` |

### 3.3 Server Endpoints (from `Config.cs`)

```csharp
// Domain rebranding table:
//   Overside: gw.aoscdn.com → gw.wangxutech.com → gw.apsapp.cn
//   CN:       aw.aoscdn.com → aw.wangxutech.com → aw.apsapp.cn

VIP_API_URL      = "https://gw.aoscdn.com/base/vip/v2"
PASSPORT_URL     = "https://gw.aoscdn.com/base/passport/v2"
PAYMENT_URL      = "https://gw.aoscdn.com/base/payment/v2"
CHECKOUT_URL     = "https://checkout.aoscdn.com"
Account_URL      = "https://myaccount.apowersoft.com"
```

Each endpoint has Chinese-region variants (prefixed `aw.*`) and fallback domains. The HTTP client (`HttpConfig.SetSpareDomains`) tries fallbacks when the primary is unreachable.

---

## Phase 4: License File Decryption

### 4.1 The Encryption Scheme

Located at `%APPDATA%\LightPDF\LightPDF Editor\passport.userinfo`, the license file is encrypted with:

```
Algorithm: DES-CBC
Key:       ASCII("JuBsbsmP")   [8 bytes]
IV:        ASCII("JuBsbsmP")   [8 bytes]
Mode:      CBC
Padding:   PKCS7
Output:    Hex-encoded uppercase string
```

The password "JuBsbsmP" is derived in `Utils.GetDesKey()` which extracts only alphabet characters from the input password (falling back to "JuBsbsmP" if the input has no letters), repeating them to get exactly 8 bytes.

### 4.2 Decrypting (PowerShell)

```powershell
$des = New-Object System.Security.Cryptography.DESCryptoServiceProvider
$des.Key = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
$des.IV  = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
$des.Mode = [System.Security.Cryptography.CipherMode]::CBC
$des.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

$hex = Get-Content "$env:APPDATA\LightPDF\LightPDF Editor\passport.userinfo" -Raw
$cipherBytes = for ($i = 0; $i -lt $hex.Length; $i += 2) {
    [Convert]::ToByte($hex.Substring($i, 2), 16)
}

$decryptor = $des.CreateDecryptor()
$plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
$json = [Text.Encoding]::UTF8.GetString($plainBytes)
```

### 4.3 The Original License (Trial/Free)

```json
{
  "license_info": {
    "passport_license_type": "trial",
    "product_license_type": "free",
    "is_activated": 1,
    "remained_seconds": 0,
    ...
  }
}
```

The original file showed a trial license that had expired — the app was running in free/limited mode.

---

## Phase 5: License Validation Flow

### 5.1 Startup Sequence

```
Passport.Init()
│
├── 1. ParseAccountInfo()
│       └── Read + DES-decrypt passport.userinfo
│       └── Deserialize JSON into PassportInfo object
│       └── Set isActive = (license_info.is_activated == 1)
│
├── 2. RefreshPassportInfoAsync()
│       └── RefreshPassportInfo()
│           ├── Check credentials (UID/token)
│           ├── If none: LoginByAnonymity() [HTTP call to server]
│           └── GetVipInfoServer() [HTTP call to server]
│               └── On error (not HttpUnauthorized): skip reset
│               └── On success: override is_activated, remained_seconds, etc.
│               └── Set IsActive = (is_activated == 1 && HasRemainDays())
│
└── 3. InitCallBack()
        └── Mark isInited = true
        └── Fire OnPassportInfoLoaded event
```

### 5.2 The Critical Code Paths

**`get_IsActive` (Passport.cs:159-164):**
```csharp
public bool IsActive {
    get { return isActive; }  // backing field
}
```

**`get_IsActive` setter (Passport.cs:165-191):**
```csharp
set {
    if (isActive == value) return;
    isActive = value;
    // fires OnPassportActivatedStatusChanged event
}
```

**`GetVipInfoServer()` (Passport.cs:1014-1063) — the server override:**
```csharp
internal int GetVipInfoServer() {
    var result = ActiveServer.GetVipInfo(...).Result;
    if (result.ErrorCode == HttpUnauthorized || result.Status == 401) {
        ResetVipInfo();  // Sets isActive = false
    }
    Application.Current.Dispatcher.Invoke(() => {
        // ...
        IsActive = PassportInfo.license_info.is_activated == 1 && HasRemainDays();
    });
}
```

**`HasRemainDays()` (Passport.cs:1066-1078):**
```csharp
internal bool HasRemainDays(bool isGroup = false) {
    var info = isGroup ? group : license;
    if (info.is_activated > 0) {
        if (info.is_lifetime) return true;          // ← Lifetime always valid
        return DateTime.Parse(info.expire_at) >= DateTime.Now;
    }
    return false;
}
```

### 5.3 The Attack Surface

The vulnerability chain:
1. License state is loaded from a local (encrypted) file — **writable by user**
2. Server verification happens *after* loading the local file
3. If server is unreachable (no network, blocked DNS), the local state **survives intact**
4. The error handling distinguishes between `HttpUnauthorized` (resets) and generic `CatchError` (does nothing)
5. `HasRemainDays()` returns `true` if `is_lifetime` is set — no date check needed

---

## Phase 6: The Bypass

### 6.1 Approach

Two layers of defense:

1. **Block license servers** → prevents server from overriding forged local state
2. **Forge the license file** → provides lifetime commercial credentials locally

### 6.2 Layer 1: DNS Blocking

Block all known license server domains (and their IPV6 equivalents) via hosts file:

```
127.0.0.1 gw.aoscdn.com
127.0.0.1 aw.aoscdn.com
127.0.0.1 checkout.aoscdn.com
127.0.0.1 myaccount.apowersoft.com
127.0.0.1 gw.wangxutech.com     # fallback domain
127.0.0.1 aw.wangxutech.com     # fallback domain
... (30+ entries total)
```

When the app tries to call `GetVipInfoServer()`, the connection is refused (127.0.0.1:443). The HTTP helper throws an exception, caught by the `catch (Exception)` block in `ActiveServer.GetVipInfo()`, which returns `ErrorCode.CatchError`. Back in `Passport.GetVipInfoServer()`, this error code is NOT `HttpUnauthorized`, so `ResetVipInfo()` is **never called**. The locally-loaded license data remains intact.

### 6.3 Why This Works

The critical error-handling distinction (Passport.cs:1019):

```csharp
if (result.ErrorCode == ErrorCode.HttpUnauthorized || result.Status == 401) {
    ResetVipInfo();  // ← Only resets on 401
}
// All other errors → skip reset → keep local data
```

And the charge type check (line 1052):

```csharp
IsActive = PassportInfo.license_info.is_activated == 1 && HasRemainDays();
```

With `is_activated=1` and `is_lifetime=true`, `HasRemainDays()` returns `true`, so `IsActive` is set to `true`.

---

## Phase 7: Forging a License

### 7.1 The Forged JSON

The forged license sets every field to its most privileged value:

```json
{
  "license_info": {
    "passport_license_type": "lifetime",
    "product_license_type": "commercial",
    "is_activated": 1,
    "remained_seconds": 9999999999,
    "expire_at": "2099-12-31",
    "max_online_num": 10,
    "durations": 99999
  },
  "group_licese_info": { /* same as above */ },
  "user_info": {
    "uid": "999999",
    "email": "premium@lightpdf.com",
    "nickname": "PremiumUser",
    "api_token": "v2,3010677305,448,..."
  },
  "activate_key_info": {
    "activate_key": "FORGED-LIFETIME-99999",
    "passport_license_type": "lifetime",
    "is_activated": 1
  }
}
```

### 7.2 Encryption

Encrypt with DES-CBC and output as hex string, then write to `passport.userinfo`.

### 7.3 Verification

After launching the app, check:

```powershell
# Decrypt and verify
Get-Content "$env:APPDATA\LightPDF\LightPDF Editor\passport.userinfo" -Raw
# → Should match the forged content after app re-encrypts it
```

The log at `%APPDATA%\LightPDF\LightPDF Editor\log\PDF.log` shows successful startup with no license errors. The app presents premium features without any upgrade prompts.

---

## File Reference

### Crack Package Structure

```
LightPDF_Crack/
├── README.md                          ← This file
├── patcher.ps1                        ← One-click patcher (run as admin)
├── restore.ps1                        ← Restore original state
├── files/
│   └── passport.userinfo              ← Forged premium license file
└── scripts/
    └── generate_license.ps1           ← DES encrypt a new forged license
```

### Key App Files

| Path | Role |
|------|------|
| `C:\Program Files (x86)\LightPDF\LightPDF Editor\LightPDF Editor.exe` | Main Qt5 native EXE (41 MB) |
| `...\Apowersoft.CommUtilities.Native.dll` | .NET licensing assembly (5.6 MB) |
| `...\CommonLib.dll` | C++/CLI bridge |
| `...\Apowersoft.CommUtilities.dll` | VB.NET utilities (legacy) |
| `%APPDATA%\LightPDF\LightPDF Editor\passport.userinfo` | Encrypted license file |
| `%APPDATA%\LightPDF\LightPDF Editor\log\Apowersoft.CommUtilities.Native.log` | License system log |
| `%APPDATA%\LightPDF\LightPDF Editor\log\PDF.log` | Main app log |
| `C:\Windows\System32\drivers\etc\hosts` | License server DNS blocks |

---

## Usage

### Applying the Crack

```powershell
# Run as Administrator
.\patcher.ps1
```

This will:
1. Elevate to admin (auto-UAC prompt)
2. Close any running LightPDF instances
3. Block 34 license server domains in hosts file
4. Backup original `passport.userinfo` → `passport.userinfo.original.bak`
5. Install forged premium license file
6. Launch LightPDF Editor — premium features unlocked

### Restoring

```powershell
.\restore.ps1
```

This removes all hosts entries and restores the original license file.

### Manual Decryption of License File

```powershell
$hex = Get-Content "$env:APPDATA\LightPDF\LightPDF Editor\passport.userinfo" -Raw
$des = New-Object System.Security.Cryptography.DESCryptoServiceProvider
$des.Key = $des.IV = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
$des.Mode = [System.Security.Cryptography.CipherMode]::CBC
$des.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
$bytes = for ($i=0; $i -lt $hex.Length; $i+=2) { [Convert]::ToByte($hex.Substring($i,2),16) }
$dec = $des.CreateDecryptor()
[Text.Encoding]::UTF8.GetString($dec.TransformFinalBlock($bytes,0,$bytes.Length))
```

---

## Key Takeaways

### For Reverse Engineers

1. **Look for the .NET bridge.** When a native app uses .NET for licensing, the .NET assembly is usually the weak point — easy to decompile, easy to modify.
2. **Encrypted local state is not secure.** The encryption key must live in the binary. DES with a static key (`JuBsbsmP`) is trivial to extract and replicate.
3. **Error handling is a vulnerability.** The distinction between `HttpUnauthorized` (resets state) and generic errors (preserves state) creates a bypass path: block the network, and the server validation becomes a no-op.
4. **Domain fallback chains must be fully enumerated.** The app has triple-domain failover (`aoscdn.com → wangxutech.com → apsapp.cn`). Missing any one in the block list lets the server call succeed.
5. **Lifetime licenses skip date checks.** `HasRemainDays()` returns `true` immediately when `is_lifetime` is set — no expiry date validation.

### Defense Recommendations

1. **Hard fail on network errors.** If the server can't be reached, default to free/trial, not to local state.
2. **Authenticate the local state.** Sign the license file with a private key (RSA/ECDSA) so it can't be forged without the key.
3. **Don't distinguish between error types.** Treat all server communication failures the same way.
4. **Hard-code the minimum check logic in native code.** Don't delegate critical validation to a decompilable .NET assembly.
5. **Obfuscate the encryption key.** Derive it from runtime properties (machine ID, hardware hash) rather than embedding a static string.

---

## License

This project is provided for educational purposes only. Reverse engineering software may violate its EULA.
