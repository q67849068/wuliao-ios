# ============================================
# Windows 下给 IPA 签名（无需 Mac）
# 依赖: zsign.exe  https://github.com/zhlynn/zsign
# ============================================
param(
    [Parameter(Mandatory=$true)][string]$UnsignedIPA,
    [string]$Cert = "wuliao.p12",
    [string]$Password = "",
    [string]$Profile = "wuliao.mobileprovision",
    [string]$Out = "wuliao-signed.ipa"
)

if (-not (Test-Path $UnsignedIPA)) { Write-Error "找不到 IPA: $UnsignedIPA"; exit 1 }
if (-not (Test-Path $Cert))        { Write-Error "找不到证书: $Cert"; exit 1 }
if (-not (Test-Path $Profile))     { Write-Error "找不到描述文件: $Profile"; exit 1 }

Write-Host "开始签名..." -ForegroundColor Cyan
& .\zsign.exe -k $Cert -p $Password -m $Profile -o $Out -z 9 $UnsignedIPA

if ($LASTEXITCODE -eq 0 -and (Test-Path $Out)) {
    $size = [math]::Round((Get-Item $Out).Length / 1MB, 2)
    Write-Host "签名成功: $Out ($size MB)" -ForegroundColor Green
    Write-Host ""
    Write-Host "接下来可以：" -ForegroundColor Yellow
    Write-Host "  1. 用 impactor / Sideloader 装到 iPhone"
    Write-Host "  2. 用 Transporter（微软商店）上传到 App Store Connect"
} else {
    Write-Error "签名失败，退出码 $LASTEXITCODE"
}
