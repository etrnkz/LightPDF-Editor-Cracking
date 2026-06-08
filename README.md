# LightPDF Editor Cracking -- The Revenge Story

> "They put a watermark on my PDF. So I learned reverse engineering."

This is the full walkthrough of reverse engineering LightPDF Editor 2.16.8.8 (Windows, x86) -- from zero to a forged lifetime commercial license. Every tool, every code path, every mistake the developers made.

---

## The Origin Story

Last week I had to submit a system analysis and vulnerability assessment report. In PDF. All the online editors were garbage. Microsoft Word destroyed my layout when converting back and forth.

Found LightPDF Editor. Did all my work. Hit "Save."

**Boom.** A massive watermark plastered across my report.

> *"Upgrade to Premium to remove watermark"*

I was furious. Hours of work. A clean report. Ruined by a watermark.

So I decided to crack it.

A few weeks later -- here we are.

---

## TL;DR (The Cheat Code)

`powershell
# Run as Admin
.\patcher.ps1
# Done. Lifetime premium. No watermark.
`

---

## The Architecture -- Follow the Money

`
LightPDF Editor.exe (41 MB, Qt5 C++)
        |
        v
CommonLib.dll (C++/CLI bridge)
        |
        v
Apowersoft.CommUtilities.Native.dll (5.6 MB, .NET WPF)
        |
        +-- Passport.cs              <- The crown jewel
        +-- ActiveServer.cs          <- Phone-home API
        +-- AccountServer.cs         <- Auth API
        +-- Config.cs                <- Server URLs (lol)
        +-- Utils.cs                 <- "Encryption"
`

**The golden rule of reversing native apps:** If the licensing is in .NET, you've already won. .NET decompiles to nearly perfect C#. No amount of native code can protect what's handed off to managed assemblies.

---

## Tools

| Tool | What it does |
|------|-------------|
| ilspycmd | .NET to C# decompiler |
| Process Monitor | Watch file/registry/network in real-time |
| PowerShell | Encryption, automation, hosts manipulation |
| VS Code | Code reading and scripting |

---

## Phase 1: Find the Weak Point

First, list the install directory:

`
C:\Program Files (x86)\LightPDF\LightPDF Editor\
`

The file sizes tell the story:

| File | Size | Role |
|------|------|------|
| LightPDF Editor.exe | 41 MB | Qt5 C++ -- the real app |
| CommonLib.dll | 1.5 MB | C++/CLI bridge to .NET |
| Apowersoft.CommUtilities.Native.dll | 5.6 MB | .NET licensing -- target acquired |
| Apowersoft.CommUtilities.dll | 2.3 MB | VB.NET legacy (marked [Obsolete]) |

**The insight:** A 41MB native executable doesn't delegate its entire licensing to a 5.6MB .NET DLL unless they want it to be easy to reverse.

Procmon confirmed the startup flow:
1. Reads \%APPDATA\%\LightPDF\LightPDF Editor\passport.userinfo  <- local license file
2. HTTP calls to gw.aoscdn.com, aw.aoscdn.com, checkout.aoscdn.com  <- server validation
3. Writes back to passport.userinfo  <- syncs server response to local

---

## Phase 2: Decompile Everything

`powershell
ilspycmd -p "bin\Apowersoft.CommUtilities.Native.dll" -o ./src
`

Out comes a full C# project. The key files:

| File | What it controls |
|------|-----------------|
| Passport/Passport.cs | IsActive, server sync, license state |
| Passport/PassportBaseLicenseInfo.cs | License data model |
| Passport/ActiveServer.cs | VIP API client (phone-home) |
| Passport/AccountServer.cs | Authentication API client |
| Config.cs | All server URLs, encryption keys |
| Utils.cs | DES encrypt/decrypt, key derivation |

---

## Phase 3: The License File

Location: \%APPDATA\%\LightPDF\LightPDF Editor\passport.userinfo

The file is "encrypted" -- I say that loosely.

### The "Encryption"

`
Algorithm: DES-CBC
Key:       ASCII("JuBsbsmP")     [8 bytes]
IV:        ASCII("JuBsbsmP")     [8 bytes]
Mode:      CBC
Padding:   PKCS7
Output:    Hex-encoded uppercase string
`

The key derivation (Utils.GetDesKey) is comedy gold:

`csharp
private static string GetDesKey(string Password) {
    string[] letters = RegexGetAll(Password, "[a-zA-Z]"); // Only letters!
    if (letters.Length == 0) Password = "JuBsbsmP";       // Fallback hardcoded
    // Repeat letters until exactly 8 chars
}
`

**Static key. Hardcoded fallback. DES.** Not even AES. This is 1970s encryption protecting a 2026 software license.

### Decrypt It

`powershell
 = New-Object System.Security.Cryptography.DESCryptoServiceProvider
.Key = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
.IV  = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
.Mode = [System.Security.Cryptography.CipherMode]::CBC
.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

 = Get-Content "C:\Users\user\AppData\Roaming\LightPDF\LightPDF Editor\passport.userinfo" -Raw
 = for ( = 0;  -lt .Length;  += 2) {
    [Convert]::ToByte(.Substring(, 2), 16)
}
 = .CreateDecryptor()
[Text.Encoding]::UTF8.GetString(.TransformFinalBlock(, 0, .Length))
`

### The Original Content

`json
{
  "license_info": {
    "passport_license_type": "trial",
    "product_license_type": "free",
    "is_activated": 1,
    "remained_seconds": 0
  }
}
`

Trial expired. Limited features. Exactly what you'd expect.

---

## Phase 4: The Validation Flow

Here's how Passport.Init() works:

`
Init()
|
+-- 1. ParseAccountInfo()
|     +-- Read + DES-decrypt passport.userinfo
|     +-- Deserialize JSON to PassportInfo
|     +-- Set isActive = (license_info.is_activated == 1)
|     +-- [*] Local file is loaded FIRST [*]
|
+-- 2. RefreshPassportInfo()
|     +-- LoginByAnonymity()    <- HTTP call, probably fails
|     +-- GetVipInfoServer()    <- HTTP call, the real threat
|           +-- If server says "unauthorized" -> ResetVipInfo()
|           +-- Otherwise -> keep local data
|           +-- Set IsActive = (is_activated == 1 && HasRemainDays())
|
+-- 3. InitCallBack()
      +-- Fire OnPassportInfoLoaded
`

### The Critical Code

**GetVipInfoServer() (Passport.cs:1014):**
`csharp
var result = ActiveServer.GetVipInfo(...).Result;

// ONLY resets on 401/Unauthorized
if (result.ErrorCode == ErrorCode.HttpUnauthorized || result.Status == 401) {
    ResetVipInfo();  // <- This is the only thing that kills local state
}

// On any other error -> local data SURVIVES
Dispatcher.Invoke(() => {
    IsActive = PassportInfo.license_info.is_activated == 1 && HasRemainDays();
});
`

**HasRemainDays() (Passport.cs:1066):**
`csharp
internal bool HasRemainDays(bool isGroup = false) {
    var info = isGroup ? group_license : license;
    if (info.is_activated > 0) {
        if (info.is_lifetime) return true;  // <- No date check for lifetime!
        return DateTime.Parse(info.expire_at) >= DateTime.Now;
    }
    return false;
}
`

**The vulnerability chain:**

1. Local file is loaded BEFORE server check -> we control the initial state
2. Server failing -> CatchError, NOT HttpUnauthorized -> no reset
3. Lifetime license -> HasRemainDays() returns true instantly, no expiry check
4. Result: if we can prevent the server call from succeeding, our forged local data sticks

---

## Phase 5: The Bypass

### Step 1: Block Their Servers

The app has a domain fallback chain:

`
gw.aoscdn.com -> gw.wangxutech.com -> gw.apsapp.cn  (overseas)
aw.aoscdn.com -> aw.wangxutech.com -> aw.apsapp.cn  (China)
`

Plus checkout, payment, account, CDN, etc. **34 domains total** in the hosts file.

All redirect to 127.0.0.1. Connection refused. The HTTP helper throws. CatchError bubbles up. ResetVipInfo() never fires.

### Step 2: Forge the License

Set everything to maximum:

`json
{
  "license_info": {
    "passport_license_type": "lifetime",
    "product_license_type": "commercial",
    "is_activated": 1,
    "remained_seconds": 9999999999,
    "expire_at": "2099-12-31"
  },
  "user_info": {
    "uid": "999999",
    "email": "premium@lightpdf.com"
  },
  "activate_key_info": {
    "activate_key": "FORGED-LIFETIME-99999",
    "passport_license_type": "lifetime",
    "is_activated": 1
  }
}
`

Encrypt with DES, write to passport.userinfo, done.

### Why This Works

The error handling has a fatal flaw:

`csharp
// Line 1019 -- Passport.cs
if (result.ErrorCode == ErrorCode.HttpUnauthorized || result.Status == 401) {
    ResetVipInfo();
}
// Everything else: Fall through to line 1052:
IsActive = PassportInfo.license_info.is_activated == 1 && HasRemainDays();
//                                                         ^ lifetime -> always true
`

When the server is blocked: CatchError != HttpUnauthorized. Reset skipped. Local data wins. IsActive = true.

---

## The Result

- No watermark
- All premium features unlocked (OCR, convert, compress, edit)
- "Lifetime Commercial" license
- No nag screens
- No upgrade prompts

Just a clean PDF editor that does what it's supposed to.

---

## Files

`
LightPDF-Crack-Reversing/
+-- README.md                  <- You are here
+-- patcher.ps1                <- Apply the crack (run as admin)
+-- restore.ps1                <- Undo everything
+-- files/
|   +-- passport.userinfo      <- Forged license (DES encrypted)
+-- scripts/
    +-- generate_license.ps1   <- Create your own forged license
`

---

## Usage

### Apply

`powershell
# Right-click -> Run with PowerShell (Admin)
.\patcher.ps1
`

What it does:
1. Elevates to admin (auto UAC)
2. Kills running LightPDF instances
3. Blocks 34 server domains in hosts
4. Backs up original license -> passport.userinfo.original.bak
5. Installs forged premium license
6. Done

### Restore

`powershell
.\restore.ps1
`

Removes hosts entries + restores original license.

---

## Lessons Learned

### For Reverse Engineers

1. .NET licensing is a gift. If the licensing is in a managed assembly, you're 90% done. Native apps use .NET for licensing because it's easy to write -- and easy to reverse.

2. Local encrypted state is always forgeable. The key must live in the binary. DES with a static key is 5 minutes of work.

3. Error handling is the real vulnerability. The gap between CatchError and HttpUnauthorized is the entire exploit. One branch resets state. The other preserves it. Block the network and you pick which branch runs.

4. Domain fallback chains must be fully mapped. The app has 3 tiers of domains per endpoint. Miss one and the server call succeeds. We blocked 34.

5. Lifetime = no date check. HasRemainDays() returns immediately for lifetime licenses. No expiry validation. The entire date logic is skipped.

### For Developers (Don't Do This)

1. Don't use .NET for license validation in a native app. It's the first thing reversers check.
2. Don't use DES in 2026. Not even for obfuscation. Use authenticated encryption with a key derived from hardware.
3. Hard-fail on network errors. If the server can't be reached, default to free. Not "trust the local file."
4. Sign your license files. RSA or ECDSA signature would make forging impossible without the private key.
5. Don't distinguish error types in validation logic. Every network error should be treated as "unauthorized."

---

## The Moral

If your app puts an ugly watermark on someone's work after they spent hours on it, don't be surprised when they learn reverse engineering just to remove it.

**Good encryption doesn't hide in .NET. Bad decisions get decompiled.**

---

## Disclaimer

This project is for educational purposes. Reverse engineering software may violate its EULA. All research was conducted on software the author owns. Don't be an asshole.
