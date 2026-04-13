param(
    [string]$TargetRoot = "",
    [string]$PublicKeyPath = "",
    [string]$Workspace = "C:\Users\monro\Codex\Kindle reclaim"
)

$ErrorActionPreference = "Stop"

function Get-DefaultPublicKeyPath {
    $defaultKey = Join-Path $env:USERPROFILE ".ssh\id_ed25519.pub"
    if (Test-Path -LiteralPath $defaultKey) {
        return (Resolve-Path -LiteralPath $defaultKey).Path
    }

    throw "No -PublicKeyPath was provided and the default key was not found at $defaultKey."
}

function Resolve-TargetRoot {
    param([string]$RequestedRoot)

    if ($RequestedRoot) {
        $resolved = (Resolve-Path -LiteralPath $RequestedRoot).Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
            throw "Target root does not exist: $resolved"
        }
        return $resolved.TrimEnd("\")
    }

    $candidates = Get-PSDrive -PSProvider FileSystem |
        ForEach-Object { $_.Root } |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_ "documents")) -or
            (Test-Path -LiteralPath (Join-Path $_ "extensions")) -or
            (Test-Path -LiteralPath (Join-Path $_ "usbnet"))
        } |
        Select-Object -Unique

    if (-not $candidates) {
        throw "No mounted Kindle-like filesystem was found. Plug the Kindle in as USB mass storage or pass -TargetRoot explicitly."
    }

    if ($candidates.Count -gt 1) {
        $joined = $candidates -join ", "
        throw "Multiple mounted Kindle-like roots were found: $joined. Pass -TargetRoot explicitly."
    }

    return $candidates[0].TrimEnd("\")
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Content -replace "`r`n", "`n"), $encoding)
}

if (-not $PublicKeyPath) {
    $PublicKeyPath = Get-DefaultPublicKeyPath
}

$targetRoot = Resolve-TargetRoot -RequestedRoot $TargetRoot
$publicKeyResolved = (Resolve-Path -LiteralPath $PublicKeyPath).Path
$publicKey = (Get-Content -LiteralPath $publicKeyResolved -Raw).Trim()

if (-not $publicKey) {
    throw "Public key file is empty: $publicKeyResolved"
}

$usbnetEtc = Join-Path $targetRoot "usbnet\etc"
$billboardSshDir = Join-Path $targetRoot "billboard\ssh"
$authorizedKeysPath = Join-Path $usbnetEtc "authorized_keys"
$stagedAuthorizedKeysPath = Join-Path $billboardSshDir "authorized_keys"

New-Item -ItemType Directory -Force -Path $usbnetEtc | Out-Null
New-Item -ItemType Directory -Force -Path $billboardSshDir | Out-Null

$existingKeys = @()
if (Test-Path -LiteralPath $authorizedKeysPath) {
    $existingKeys = (Get-Content -LiteralPath $authorizedKeysPath -Raw) -replace "`r`n", "`n" -split "`n"
}

$mergedKeys = @($existingKeys + $publicKey) |
    Where-Object { $_ -and $_.Trim() } |
    ForEach-Object { $_.Trim() } |
    Select-Object -Unique

$mergedContent = (($mergedKeys -join "`n").TrimEnd()) + "`n"
Write-Utf8NoBom -Path $authorizedKeysPath -Content $mergedContent
Write-Utf8NoBom -Path $stagedAuthorizedKeysPath -Content $mergedContent

Write-Output "Installed host SSH public key into:"
Write-Output "  $authorizedKeysPath"
Write-Output "  $stagedAuthorizedKeysPath"
