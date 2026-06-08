# LightPDF Editor Cracking

"They put a watermark on my PDF. So I reversed their licensing."

---

## The Origin Story

Needed to submit a PDF report. Online editors were trash. Word destroyed my layout.

Found LightPDF Editor. Did all my work. Hit Save.

A watermark slammed across my report: *"Upgrade to Premium to remove watermark"*

Hours of work, ruined. So I cracked it.

---

## TL;DR

```powershell
.\patcher.ps1         # Run as Admin. Done.
```

---

## Architecture

```
LightPDF Editor.exe (41 MB, Qt5 C++)
        |
        v
CommonLib.dll (C++/CLI bridge)
        |
        v
Apowersoft.CommUtilities.Native.dll (5.6 MB, .NET)
        |
        +-- Passport.cs          <- Licensing controller
        +-- ActiveServer.cs      <- Phone-home API
        +-- Config.cs            <- Server URLs + encryption key
        +-- Utils.cs             <- DES encrypt/decrypt
```

Golden rule of reversing: **.NET licensing in a native app = already won.**

---

## Phase 1: The License File

`%APPDATA%\LightPDF\LightPDF Editor\passport.userinfo`

Encrypted with DES-CBC. Key: `ASCII("JuBsbsmP")`. Static. Hardcoded. Not even AES.

Decrypt:

```powershell
$des = New-Object System.Security.Cryptography.DESCryptoServiceProvider
$des.Key = $des.IV = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
$des.Mode = [System.Security.Cryptography.CipherMode]::CBC
$des.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

$hex = Get-Content "$env:APPDATA\LightPDF\LightPDF Editor\passport.userinfo" -Raw
$bytes = for ($i = 0; $i -lt $hex.Length; $i += 2) {
    [Convert]::ToByte($hex.Substring($i, 2), 16)
}
$dec = $des.CreateDecryptor()
[Text.Encoding]::UTF8.GetString($dec.TransformFinalBlock($bytes, 0, $bytes.Length))
```

Original: `trial`, `free`, `is_activated: 1`, `remained_seconds: 0`

---

## Phase 2: The Validation Flow

```
Init()
+-- ParseAccountInfo()     <- Loads LOCAL file FIRST
+-- RefreshPassportInfo()
|   +-- LoginByAnonymity()   <- HTTP (fails -> CatchError)
|   +-- GetVipInfoServer()   <- HTTP (fails -> CatchError)
|       +-- 401/Unauthorized? -> ResetVipInfo()
|       +-- Anything else?    -> Keep local data -> IsActive = true
+-- InitCallBack()
```

**The bug (Passport.cs:1019):**

```csharp
if (result.ErrorCode == ErrorCode.HttpUnauthorized || result.Status == 401) {
    ResetVipInfo();  // Only this path destroys local state
}
// Everything else falls through to:
IsActive = PassportInfo.license_info.is_activated == 1 && HasRemainDays();
```

**HasRemainDays() (Passport.cs:1066):**

```csharp
if (info.is_lifetime) return true;  // No date check. Instant pass.
```

The chain:
1. Local file loads first -> we control initial state
2. Block network -> server returns CatchError, not HttpUnauthorized -> no reset
3. Set `is_lifetime: true` -> HasRemainDays() returns true instantly
4. IsActive = true. Done.

---

## Phase 3: The Bypass

### Block 34 domains

Triple failover chain: `aoscdn.com -> wangxutech.com -> apsapp.cn`

All to `127.0.0.1`. Connection refused. CatchError bubbles up. Reset never fires.

### Forge the license

```json
{
  "license_info": {
    "passport_license_type": "lifetime",
    "product_license_type": "commercial",
    "is_activated": 1,
    "remained_seconds": 9999999999,
    "expire_at": "2099-12-31"
  }
}
```

DES encrypt. Write to passport.userinfo. Done.

---

## Files

### Package contents
```
+-- README.md
+-- patcher.ps1               <- Run as Admin
+-- restore.ps1               <- Undo everything
+-- files/
|   +-- passport.userinfo     <- Cracked license
|   +-- passport.userinfo.original  <- Original trial license
+-- scripts/
    +-- generate_license.ps1
```

### [Download original license](files/passport.userinfo.original)
### [Download cracked license](files/passport.userinfo)
### [Download patcher](patcher.ps1)
### [Download restore script](restore.ps1)

---

## Key Takeaways

- .NET licensing = decompilable by default. All your license logic is readable.
- Static DES key in the binary. The encryption is theater.
- Error handling is the exploit. CatchError vs HttpUnauthorized is a 1-line bug.
- Domain fallback chains must be fully blocked. Miss one and the server check succeeds.
- Lifetime = no date validation. HasRemainDays() short-circuits completely.

---

## Disclaimer

Educational purposes only. Research conducted on software I own.
