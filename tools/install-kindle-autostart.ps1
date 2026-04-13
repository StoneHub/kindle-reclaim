param(
    [string]$KindleWifiIp = "192.168.50.162",
    [string]$Workspace = "C:\Users\monro\Codex\Kindle reclaim",
    [string]$SshPassword = "",
    [string]$SshKeyPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-DefaultSshKeyPath {
    $defaultKey = Join-Path $env:USERPROFILE ".ssh\id_ed25519"
    if (Test-Path -LiteralPath $defaultKey) {
        return (Resolve-Path -LiteralPath $defaultKey).Path
    }

    return ""
}

function New-AskPassScript {
    param([string]$Password)

    $path = Join-Path $env:TEMP ("codex-kindle-askpass-" + [guid]::NewGuid().ToString("N") + ".cmd")
    [System.IO.File]::WriteAllText($path, "@echo off`r`necho $Password`r`n", [System.Text.Encoding]::ASCII)
    return $path
}

function Invoke-WithAskPass {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)]
        [string]$Password
    )

    $askPassPath = New-AskPassScript -Password $Password
    try {
        $previousAskPass = $env:SSH_ASKPASS
        $previousAskPassRequire = $env:SSH_ASKPASS_REQUIRE
        $previousDisplay = $env:DISPLAY

        $env:SSH_ASKPASS = $askPassPath
        $env:SSH_ASKPASS_REQUIRE = "force"
        $env:DISPLAY = "codex"

        & $ScriptBlock
    }
    finally {
        if ($null -eq $previousAskPass) {
            Remove-Item Env:SSH_ASKPASS -ErrorAction SilentlyContinue
        }
        else {
            $env:SSH_ASKPASS = $previousAskPass
        }

        if ($null -eq $previousAskPassRequire) {
            Remove-Item Env:SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
        }
        else {
            $env:SSH_ASKPASS_REQUIRE = $previousAskPassRequire
        }

        if ($null -eq $previousDisplay) {
            Remove-Item Env:DISPLAY -ErrorAction SilentlyContinue
        }
        else {
            $env:DISPLAY = $previousDisplay
        }

        Remove-Item -LiteralPath $askPassPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WindowsSsh {
    param(
        [string]$Target,
        [string]$RemoteCommand,
        [string]$KeyPath,
        [string]$Password
    )

    $arguments = @(
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=5"
    )

    if ($KeyPath) {
        $arguments += @(
            "-o", "PreferredAuthentications=publickey,password",
            "-o", "IdentitiesOnly=yes",
            "-i", $KeyPath
        )
    }
    else {
        $arguments += @(
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1"
        )
    }

    $arguments += "root@$Target"
    if ($RemoteCommand) {
        $arguments += $RemoteCommand
    }

    if ($KeyPath) {
        $output = & ssh @arguments
        $exitCode = $LASTEXITCODE
    }
    else {
        $output = Invoke-WithAskPass -Password $Password -ScriptBlock {
            & ssh @arguments
        }
        $exitCode = $LASTEXITCODE
    }

    if ($exitCode -ne 0) {
        throw "ssh failed for $Target with exit code $exitCode."
    }

    return $output
}

function Invoke-WindowsScp {
    param(
        [string]$SourcePath,
        [string]$Target,
        [string]$RemotePath,
        [string]$KeyPath,
        [string]$Password
    )

    $arguments = @(
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=5"
    )

    if ($KeyPath) {
        $arguments += @(
            "-o", "PreferredAuthentications=publickey,password",
            "-o", "IdentitiesOnly=yes",
            "-i", $KeyPath
        )
    }
    else {
        $arguments += @(
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1"
        )
    }

    $arguments += @(
        $SourcePath,
        "root@${Target}:$RemotePath"
    )

    if ($KeyPath) {
        & scp @arguments
        $exitCode = $LASTEXITCODE
    }
    else {
        Invoke-WithAskPass -Password $Password -ScriptBlock {
            & scp @arguments
        }
        $exitCode = $LASTEXITCODE
    }

    if ($exitCode -ne 0) {
        throw "scp failed for $SourcePath -> ${Target}:$RemotePath with exit code $exitCode."
    }
}

$envPassword = [Environment]::GetEnvironmentVariable("KINDLE_SSH_PASSWORD")
if (-not $SshKeyPath) {
    $SshKeyPath = Get-DefaultSshKeyPath
}

if (-not $SshPassword -and $envPassword) {
    $SshPassword = $envPassword
}

if (-not $SshKeyPath -and -not $SshPassword) {
    $SshPassword = "kindle"
}

$workspaceResolved = (Resolve-Path -LiteralPath $Workspace).Path
$autostartScript = (Resolve-Path -LiteralPath (Join-Path $workspaceResolved "billboard\autostart.sh")).Path
$upstartConf = (Resolve-Path -LiteralPath (Join-Path $workspaceResolved "billboard\kindle-billboard-upstart.conf")).Path

if ($DryRun.IsPresent) {
    Write-Output "target=$KindleWifiIp"
    Write-Output "autostart=$autostartScript"
    Write-Output "upstart_conf=$upstartConf"
    return
}

Invoke-WindowsSsh -Target $KindleWifiIp -KeyPath $SshKeyPath -Password $SshPassword `
    -RemoteCommand "mkdir -p /mnt/us/billboard /mnt/us/billboard/logs"

Invoke-WindowsScp -SourcePath $autostartScript -Target $KindleWifiIp -RemotePath "/mnt/us/billboard/autostart.sh" `
    -KeyPath $SshKeyPath -Password $SshPassword
Invoke-WindowsScp -SourcePath $upstartConf -Target $KindleWifiIp -RemotePath "/mnt/us/billboard/kindle-billboard.conf" `
    -KeyPath $SshKeyPath -Password $SshPassword

$remoteInstall = @(
    "set -e"
    "chmod +x /mnt/us/billboard/autostart.sh"
    "mount -o remount,rw /"
    "[ -f /etc/upstart/kindle-billboard.conf ] && cp /etc/upstart/kindle-billboard.conf /etc/upstart/kindle-billboard.conf.bak || true"
    "cp /mnt/us/billboard/kindle-billboard.conf /etc/upstart/kindle-billboard.conf"
    "chmod 0644 /etc/upstart/kindle-billboard.conf"
    "sync"
    "mount -o remount,ro /"
    "/bin/sh /mnt/us/billboard/autostart.sh"
    "echo autostart_installed"
) -join "; "

Invoke-WindowsSsh -Target $KindleWifiIp -KeyPath $SshKeyPath -Password $SshPassword -RemoteCommand $remoteInstall
