param(
    [ValidateSet("auto", "usb", "wifi")]
    [string]$Transport = "auto",
    [string]$BusId = "2-1",
    [string]$Distro = "Ubuntu",
    [string]$UsbInterfaceName = "enxee4900000000",
    [string]$KindleUsbIp = "192.168.15.244",
    [string]$KindleWifiIp = "192.168.50.162",
    [string]$HostUsbIp = "192.168.15.201",
    [string]$NewPassword = "kindle",
    [string]$SshPassword = "",
    [string]$SshKeyPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath {
    param([string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $drive = $resolved.Substring(0, 1).ToLowerInvariant()
    $rest = $resolved.Substring(2).Replace("\", "/")
    return "/mnt/$drive$rest"
}

function Get-DefaultSshKeyPath {
    $defaultKey = Join-Path $env:USERPROFILE ".ssh\id_ed25519"
    if (Test-Path -LiteralPath $defaultKey) {
        return (Resolve-Path -LiteralPath $defaultKey).Path
    }

    return ""
}

function Convert-ToShellSingleQuoted {
    param([string]$Value)

    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $replacement = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
    return $singleQuote + $Value.Replace($singleQuote, $replacement) + $singleQuote
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

function Test-NativeWifiReachable {
    param(
        [string]$Target,
        [string]$KeyPath,
        [string]$Password
    )

    try {
        Invoke-WindowsSsh -Target $Target -RemoteCommand "echo connected" -KeyPath $KeyPath -Password $Password | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Verify-NativePasswordLogin {
    param(
        [string]$Target,
        [string]$Password
    )

    $output = Invoke-WindowsSsh -Target $Target -RemoteCommand "echo password_ok" -KeyPath "" -Password $Password
    return ($output | Out-String).Trim() -match "password_ok"
}

function Set-NativeWifiPassword {
    param(
        [string]$Target,
        [string]$CurrentKeyPath,
        [string]$CurrentPassword,
        [string]$PasswordToSet
    )

    $quotedPassword = Convert-ToShellSingleQuoted -Value $PasswordToSet
    $remoteCommand = "set -e; mount -o remount,rw /; printf 'root:%s\n' $quotedPassword | chpasswd; sync; mount -o remount,ro /"

    Invoke-WindowsSsh -Target $Target -RemoteCommand $remoteCommand -KeyPath $CurrentKeyPath -Password $CurrentPassword | Out-Null

    if (-not (Verify-NativePasswordLogin -Target $Target -Password $PasswordToSet)) {
        throw "Password update command ran but password verification failed for $Target."
    }
}

$envPassword = [Environment]::GetEnvironmentVariable("KINDLE_SSH_PASSWORD")
if (-not $SshKeyPath) {
    $SshKeyPath = Get-DefaultSshKeyPath
}

if (-not $SshPassword -and $envPassword) {
    $SshPassword = $envPassword
}

$sshAuthMode = if ($SshKeyPath) { "key" } else { "password" }
if ($sshAuthMode -eq "password" -and -not $SshPassword) {
    $SshPassword = "x"
}

if ($Transport -eq "wifi") {
    if ($DryRun.IsPresent) {
        Write-Output "selected_transport=wifi target=$KindleWifiIp auth=$sshAuthMode"
        return
    }

    Set-NativeWifiPassword -Target $KindleWifiIp -CurrentKeyPath $SshKeyPath -CurrentPassword $SshPassword -PasswordToSet $NewPassword
    Write-Output "password_updated target=$KindleWifiIp"
    return
}

$wifiNativeReachable = $false
if ($Transport -eq "auto") {
    $wifiNativeReachable = Test-NativeWifiReachable -Target $KindleWifiIp -KeyPath $SshKeyPath -Password $SshPassword
    if ($wifiNativeReachable) {
        if ($DryRun.IsPresent) {
            Write-Output "selected_transport=wifi target=$KindleWifiIp auth=$sshAuthMode"
            return
        }

        Set-NativeWifiPassword -Target $KindleWifiIp -CurrentKeyPath $SshKeyPath -CurrentPassword $SshPassword -PasswordToSet $NewPassword
        Write-Output "password_updated target=$KindleWifiIp"
        return
    }
}

$sshKeyWsl = if ($SshKeyPath) { Convert-ToWslPath -Path $SshKeyPath } else { "" }

$usbipd = "C:\Program Files\usbipd-win\usbipd.exe"
$shouldAttemptUsb = $Transport -in @("auto", "usb")
$usbBusAvailable = $false
$usbBusState = ""

if ($shouldAttemptUsb -and (Test-Path $usbipd)) {
    $usbipdList = & $usbipd list 2>$null
    $usbBusLine = $usbipdList | Where-Object { $_ -match "^$([regex]::Escape($BusId))\s" } | Select-Object -First 1
    $usbBusAvailable = [bool]$usbBusLine

    if ($usbBusLine -match "Not shared") {
        $usbBusState = "not_shared"
    }
    elseif ($usbBusLine -match "Attached") {
        $usbBusState = "attached"
    }
    elseif ($usbBusLine -match "Shared") {
        $usbBusState = "shared"
    }

    if ($usbBusAvailable -and $usbBusState -in @("shared", "attached") -and -not $DryRun) {
        & $usbipd attach --wsl $Distro --busid $BusId | Out-Null
        if ($LASTEXITCODE -ne 0) {
            if ($Transport -eq "usb") {
                throw "usbipd attach failed for busid $BusId."
            }
            $usbBusAvailable = $false
        }
    }
    elseif ($Transport -eq "usb" -and $usbBusState -eq "not_shared") {
        throw "USB busid $BusId is visible but not shared. Run 'usbipd bind --busid $BusId' as administrator first."
    }
    elseif ($Transport -eq "usb" -and -not $usbBusAvailable) {
        throw "USB busid $BusId is not currently available in usbipd."
    }
}
elseif ($Transport -eq "usb") {
    throw "usbipd is not installed at $usbipd."
}

$dryRunFlag = if ($DryRun.IsPresent) { "1" } else { "0" }
$shouldAttemptUsbFlag = if ($shouldAttemptUsb -and $usbBusAvailable -and $usbBusState -ne "not_shared") { "1" } else { "0" }
$shouldAttemptWifiFlag = if ($Transport -in @("auto", "wifi")) { "1" } else { "0" }

$script = @'
set -euo pipefail

TRANSPORT="__TRANSPORT__"
USB_INTERFACE_NAME="__USB_INTERFACE_NAME__"
KINDLE_USB_IP="__KINDLE_USB_IP__"
KINDLE_WIFI_IP="__KINDLE_WIFI_IP__"
HOST_USB_IP="__HOST_USB_IP__"
NEW_PASSWORD="__NEW_PASSWORD__"
DRY_RUN="__DRY_RUN__"
TRY_USB="__TRY_USB__"
TRY_WIFI="__TRY_WIFI__"
AUTH_MODE="__AUTH_MODE__"
SSH_KEY_PATH="__SSH_KEY_PATH__"
SSH_PASSWORD="__SSH_PASSWORD__"
SSH_OPTS_BASE='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5'

ssh_run() {
  target="$1"
  shift

  if [ "$AUTH_MODE" = "key" ]; then
    ssh $SSH_OPTS_BASE -o PreferredAuthentications=publickey,password -o IdentitiesOnly=yes -i "$SSH_KEY_PATH" "root@$target" "$@"
    return
  fi

  SSHPASS="$SSH_PASSWORD" sshpass -e ssh $SSH_OPTS_BASE -o PreferredAuthentications=password -o PubkeyAuthentication=no "root@$target" "$@"
}

can_ssh() {
  target="$1"
  ssh_run "$target" "echo connected" >/dev/null 2>&1
}

verify_password_login() {
  target="$1"
  SSHPASS="$NEW_PASSWORD" sshpass -e ssh $SSH_OPTS_BASE -o PreferredAuthentications=password -o PubkeyAuthentication=no "root@$target" "echo password_ok" >/dev/null 2>&1
}

find_usb_iface() {
  if [ -n "$USB_INTERFACE_NAME" ] && ip -o link show "$USB_INTERFACE_NAME" >/dev/null 2>&1; then
    echo "$USB_INTERFACE_NAME"
    return 0
  fi

  ip -o link | awk -F': ' '
    {
      iface = $2
      sub(/@.*/, "", iface)
      if (iface ~ /^(enx|usb)/) {
        print iface
        exit
      }
    }
  '
}

prepare_usb() {
  iface="$(find_usb_iface)"
  [ -n "$iface" ] || return 1
  ip link set "$iface" up >/dev/null 2>&1 || true
  ip addr replace "$HOST_USB_IP/24" dev "$iface"
}

selected_transport=""
selected_target=""

if [ "$TRANSPORT" = "usb" ]; then
  prepare_usb || {
    echo "ERROR: Kindle USB network interface not found" >&2
    exit 1
  }
  selected_transport="usb"
  selected_target="$KINDLE_USB_IP"
elif [ "$TRANSPORT" = "wifi" ]; then
  selected_transport="wifi"
  selected_target="$KINDLE_WIFI_IP"
else
  if [ "$TRY_USB" = "1" ] && prepare_usb && can_ssh "$KINDLE_USB_IP"; then
    selected_transport="usb"
    selected_target="$KINDLE_USB_IP"
  elif [ "$TRY_WIFI" = "1" ] && can_ssh "$KINDLE_WIFI_IP"; then
    selected_transport="wifi"
    selected_target="$KINDLE_WIFI_IP"
  else
    echo "ERROR: no reachable Kindle SSH transport (USB or Wi-Fi)" >&2
    exit 1
  fi
fi

echo "selected_transport=$selected_transport target=$selected_target auth=$AUTH_MODE"

if [ "$DRY_RUN" = "1" ]; then
  exit 0
fi

if ! can_ssh "$selected_target"; then
  echo "ERROR: Kindle SSH target is not reachable on $selected_transport ($selected_target)" >&2
  exit 1
fi

ssh_run "$selected_target" "if command -v mntroot >/dev/null 2>&1; then mntroot rw >/dev/null 2>&1 || true; fi; mount -o remount,rw /; if command -v chpasswd >/dev/null 2>&1; then printf '%s\n' \"root:$NEW_PASSWORD\" | chpasswd; elif command -v passwd >/dev/null 2>&1; then printf '%s\n%s\n' \"$NEW_PASSWORD\" \"$NEW_PASSWORD\" | passwd root; else echo 'ERROR: neither chpasswd nor passwd is available' >&2; exit 1; fi; sync; mount -o remount,ro /"

if ! verify_password_login "$selected_target"; then
  echo "ERROR: password update command ran but password verification failed" >&2
  exit 1
fi

echo "password_updated target=$selected_target"
'@

$script = $script.Replace("__TRANSPORT__", $Transport)
$script = $script.Replace("__USB_INTERFACE_NAME__", $UsbInterfaceName)
$script = $script.Replace("__KINDLE_USB_IP__", $KindleUsbIp)
$script = $script.Replace("__KINDLE_WIFI_IP__", $KindleWifiIp)
$script = $script.Replace("__HOST_USB_IP__", $HostUsbIp)
$script = $script.Replace("__NEW_PASSWORD__", $NewPassword)
$script = $script.Replace("__DRY_RUN__", $dryRunFlag)
$script = $script.Replace("__TRY_USB__", $shouldAttemptUsbFlag)
$script = $script.Replace("__TRY_WIFI__", $shouldAttemptWifiFlag)
$script = $script.Replace("__AUTH_MODE__", $sshAuthMode)
$script = $script.Replace("__SSH_KEY_PATH__", $sshKeyWsl)
$script = $script.Replace("__SSH_PASSWORD__", $SshPassword)

$tempScriptPath = Join-Path $env:TEMP ("set-kindle-root-password-" + [guid]::NewGuid().ToString("N") + ".sh")
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempScriptPath, ($script -replace "`r`n", "`n"), $utf8NoBom)

try {
    $tempScriptWsl = Convert-ToWslPath -Path $tempScriptPath
    wsl.exe -d $Distro -u root -e bash $tempScriptWsl
}
finally {
    Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction SilentlyContinue
}
