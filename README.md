> "They put a watermark on my PDF. So I reversed their licensing."

---

## > The Origin Story

Last week I had to submit a system analysis and vulnerability assessment report in PDF format. All the online editors I tried were either broken, slow, or wanted me to upload my files to some sketchy server. I figured I'd use Microsoft Word instead, but converting the PDF to a Word doc completely destroyed the entire layout -- tables misaligned, fonts wrong, diagrams scattered everywhere. After fighting with it for hours I found LightPDF Editor, a desktop app that actually opened my PDF perfectly. I finished all my edits, hit Save, and right as I was about to export, a massive watermark slammed across every single page of my report: "Upgrade to Premium to remove watermark." Hours of meticulous work, ruined by an ugly overlay I never agreed to. So I decided to crack it.

---

## > TL;DR

```powershell
.\patcher.ps1         # Run as Admin. Done.
```

---

## > Architecture

```
  LightPDF Editor.exe (41 MB, Qt5 C++)
          |
          v
  CommonLib.dll (C++/CLI bridge)
          |
          v
  Apowersoft.CommUtilities.Native.dll (5.6 MB, .NET WPF)
          |
          +-- Passport.cs          Licensing controller
          +-- ActiveServer.cs      Phone-home API
          +-- AccountServer.cs     Auth API
          +-- Config.cs            Server URLs + encryption key
          +-- Utils.cs             DES encrypt/decrypt
```

**Golden rule:** .NET licensing in a native app = already won.

---

## > Phase 1: Crack the License File

There's a file at `%APPDATA%\LightPDF\LightPDF Editor\passport.userinfo` that holds the full license state. Encrypted? Sure. But with DES-CBC and a static key hardcoded in the binary: `ASCII("JuBsbsmP")`. That's not encryption, it's obfuscation theater.

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

Decrypted content: `trial`, `free`, `is_activated: 1`, `remained_seconds: 0`

---

## > Phase 2: Map the Validation Flow

```
  Passport.Init()
  |
  +-- ParseAccountInfo()        Loads LOCAL file FIRST
  |
  +-- RefreshPassportInfo()
  |   +-- LoginByAnonymity()    HTTP -> fails with CatchError
  |   +-- GetVipInfoServer()    HTTP -> fails with CatchError
  |       |
  |       +-- 401/Unauthorized? -> ResetVipInfo() (kills local state)
  |       +-- Anything else?    -> Keep local data -> IsActive = true
  |
  +-- InitCallBack()            Done.
```

**The one-line bug (Passport.cs:1019):**

```csharp
if (result.ErrorCode == ErrorCode.HttpUnauthorized || result.Status == 401) {
    ResetVipInfo();  // Only this branch destroys our forged state
}
// Everything else -> local data survives -> IsActive stays true
IsActive = PassportInfo.license_info.is_activated == 1 && HasRemainDays();
```

**The second gift (Passport.cs:1066):**

```csharp
if (info.is_lifetime) return true;  // No date check. Instant pass.
```

The exploit chain:
1. Local file is parsed BEFORE server check -- we control the initial state
2. Block network -- server returns CatchError, not HttpUnauthorized -- no reset
3. Set `is_lifetime` -- HasRemainDays() returns true without checking the date
4. IsActive = true. Done.

---

## > Phase 3: Execute

### Block 34 domains

The HTTP client has a triple failover chain: `aoscdn.com -> wangxutech.com -> apsapp.cn`

Every single one goes to `127.0.0.1`. Connection refused. CatchError bubbles up. ResetVipInfo() is never reached.

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

DES encrypt. Write to passport.userinfo. Launch the app.

No watermark. Lifetime commercial. Done.

---

## > Downloads

| What | Link |
|------|------|
| Original software | [lightpdf.com/free-pdf-editor.html](https://www.lightpdf.com/free-pdf-editor.html) |
| Patcher (run as admin) | [patcher.ps1](patcher.ps1) |
| Patched DLL (no hosts needed) | [files/Apowersoft.CommUtilities.Native.dll](files/Apowersoft.CommUtilities.Native.dll) |
| Restore script | [restore.ps1](restore.ps1) |
| Cracked license file | [files/passport.userinfo](files/passport.userinfo) |
| Original license file | [files/passport.userinfo.original](files/passport.userinfo.original) |
| License generator | [scripts/generate_license.ps1](scripts/generate_license.ps1) |

---

## > Files

```
  +-- README.md
  +-- patcher.ps1               Run as Admin. Patches hosts + installs license.
  +-- restore.ps1               Removes hosts entries + restores original.
  +-- files/
  |   +-- passport.userinfo         Forged lifetime commercial license
  |   +-- passport.userinfo.original Original trial license (backup)
  +-- scripts/
      +-- generate_license.ps1  Generate your own forged license from JSON
```

---

## > Key Takeaways

  - **.NET licensing** -- decompilable by default. All your logic is readable.
  - **Static DES key** -- the encryption is theater. One string in the binary.
  - **Error handling is the exploit** -- CatchError vs HttpUnauthorized created a 1-line backdoor.
  - **Domain failover chains** -- the app tries 3 domains per endpoint. Block all 34 or the check passes.
  - **Lifetime bypasses date validation** -- HasRemainDays() short-circuits completely when is_lifetime is set.

---

## > Disclaimer

Educational purposes only. Research conducted on software I own.
