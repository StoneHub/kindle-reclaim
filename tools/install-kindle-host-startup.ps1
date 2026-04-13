param(
    [ValidateSet("install", "remove", "status")]
    [string]$Action = "install",
    [string]$Workspace = "C:\Users\monro\Codex\Kindle reclaim"
)

$ErrorActionPreference = "Stop"

$workspaceResolved = (Resolve-Path -LiteralPath $Workspace).Path
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "kindle-host-serve.cmd"
$command = '@echo off
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $workspaceResolved + '\tools\kindle-host-serve.ps1" -Action ensure
'

switch ($Action) {
    "status" {
        if (Test-Path -LiteralPath $shortcutPath) {
            Write-Output "state=installed path=$shortcutPath"
        }
        else {
            Write-Output "state=missing path=$shortcutPath"
        }
        return
    }

    "remove" {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        Write-Output "state=removed path=$shortcutPath"
        return
    }

    "install" {
        [System.IO.File]::WriteAllText($shortcutPath, $command, [System.Text.Encoding]::ASCII)
        Write-Output "state=installed path=$shortcutPath"
        return
    }
}
