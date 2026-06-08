# LightPDF Editor - Forged License Generator
# Generates an encrypted passport.userinfo with lifetime commercial premium status

$json = @'
{"HasGroup":false,"license_info":{"max_online_num":10,"durations":99999,"candy":9999,"candy_expired_at":9999999999,"limit":99999,"passport_license_type":"lifetime","product_license_type":"commercial","expire_at":"2099-12-31","is_activated":1,"remained_seconds":9999999999},"group_licese_info":{"max_online_num":10,"durations":99999,"candy":9999,"candy_expired_at":9999999999,"limit":99999,"passport_license_type":"lifetime","product_license_type":"commercial","expire_at":"2099-12-31","is_activated":1,"remained_seconds":9999999999},"user_info":{"uid":"999999","equip_id":"3010677305","device_hash":"3d5887813e8aac588f97021be1de713f","email":"premium@lightpdf.com","telephone":"","first_name":"Premium","last_name":"User","avatar_url":"","api_token":"v2,3010677305,448,23c75f381b5189529182319ad1d8e0c70","nickname":"PremiumUser"},"activate_key_info":{"activate_key":"FORGED-LIFETIME-99999","function_code":"all","state":"activated","is_expired":false,"will_expire":0,"passport_license_type":"lifetime","product_license_type":"commercial","expire_at":"2099-12-31","is_activated":1,"remained_seconds":9999999999},"activate_key_infos":{},"fuction_code_activate_key_infos":[]}
'@

$des = New-Object System.Security.Cryptography.DESCryptoServiceProvider
$des.Key = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
$des.IV = [Text.Encoding]::ASCII.GetBytes("JuBsbsmP")
$des.Mode = [System.Security.Cryptography.CipherMode]::CBC
$des.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

$plainBytes = [Text.Encoding]::UTF8.GetBytes($json)
$encryptor = $des.CreateEncryptor()
$cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)

$hex = -join ($cipherBytes | ForEach-Object { "{0:X2}" -f $_ })
$outPath = Join-Path $PSScriptRoot "..\files\passport.userinfo"
$hex | Out-File $outPath -NoNewline -Encoding ascii
Write-Host "Generated: $outPath ($($hex.Length) chars)"
