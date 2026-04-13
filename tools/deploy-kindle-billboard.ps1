param(
    [string]$BusId = "2-1",
    [string]$Distro = "Ubuntu",
    [string]$KindleIp = "192.168.15.244",
    [string]$HostUsbIp = "192.168.15.201",
    [string]$Workspace = "C:\Users\monro\Codex\Kindle reclaim",
    [string]$BillboardUrl = "",
    [int]$IntervalSeconds = 60,
    [int]$UseSuspend = 0,
    [int]$FetchTimeoutSeconds = 30,
    [int]$FetchRetries = 2,
    [int]$RenderOnChange = 1,
    [string]$SshPassword = "",
    [string]$SshKeyPath = "",
    [switch]$StartPoller
)

$ErrorActionPreference = "Stop"

function Get-LanIPv4 {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.InterfaceAlias -notmatch "WSL|Tailscale|Default Switch|Loopback|Bluetooth|vEthernet"
        } |
        Sort-Object InterfaceMetric, SkipAsSource

    $preferred = $candidates | Where-Object { $_.InterfaceAlias -match "Wi-?Fi|Wireless" } | Select-Object -First 1
    if ($preferred) {
        return $preferred.IPAddress
    }

    $fallback = $candidates | Select-Object -First 1
    if ($fallback) {
        return $fallback.IPAddress
    }

    throw "Unable to detect a LAN IPv4 address. Pass -BillboardUrl explicitly."
}

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

if (-not $BillboardUrl) {
    $LanIp = Get-LanIPv4
    $BillboardUrl = "http://${LanIp}:8765/current.png"
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

$sshKeyWsl = if ($SshKeyPath) { Convert-ToWslPath -Path $SshKeyPath } else { "" }

$usbipd = "C:\Program Files\usbipd-win\usbipd.exe"
& $usbipd attach --wsl $Distro --busid $BusId | Out-Null

$workspaceWsl = "/mnt/c/Users/monro/Codex/Kindle reclaim"
$startPollerFlag = if ($StartPoller.IsPresent) { "1" } else { "0" }
$script = @"
set -e
IFACE=\$(ip -o link | awk -F': ' '/enxee4900000000/ {print \$2; exit}')
if [ -z "\$IFACE" ]; then
  echo "ERROR: Kindle USB network interface not found" >&2
  exit 1
fi
ip link set "\$IFACE" up
ip addr replace $HostUsbIp/24 dev "\$IFACE"
cd "$workspaceWsl"
AUTH_MODE="__AUTH_MODE__"
SSH_KEY_PATH="__SSH_KEY_PATH__"
SSH_PASSWORD="__SSH_PASSWORD__"
SSH_OPTS_BASE="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

ssh_run() {
  target="$1"
  shift

  if [ "$AUTH_MODE" = "key" ]; then
    ssh $SSH_OPTS_BASE -o PreferredAuthentications=publickey,password -o IdentitiesOnly=yes -i "$SSH_KEY_PATH" "root@$target" "$@"
    return
  fi

  SSHPASS="$SSH_PASSWORD" sshpass -e ssh $SSH_OPTS_BASE -o PreferredAuthentications=password -o PubkeyAuthentication=no "root@$target" "$@"
}

scp_run() {
  source_path="$1"
  target_path="$2"

  if [ "$AUTH_MODE" = "key" ]; then
    scp $SSH_OPTS_BASE -o IdentitiesOnly=yes -i "$SSH_KEY_PATH" $source_path "root@$target_path"
    return
  fi

  SSHPASS="$SSH_PASSWORD" sshpass -e scp $SSH_OPTS_BASE -o PreferredAuthentications=password -o PubkeyAuthentication=no $source_path "root@$target_path"
}

ssh_run ${KindleIp} "mkdir -p /mnt/us/billboard /mnt/us/extensions/kindle-billboard/bin"
scp_run billboard/* "${KindleIp}:/mnt/us/billboard/"
scp_run kual/kindle-billboard/config.xml "${KindleIp}:/mnt/us/extensions/kindle-billboard/"
scp_run kual/kindle-billboard/menu.json "${KindleIp}:/mnt/us/extensions/kindle-billboard/"
scp_run kual/kindle-billboard/bin/* "${KindleIp}:/mnt/us/extensions/kindle-billboard/bin/"
ssh_run ${KindleIp} '
set -e
chmod +x /mnt/us/billboard/*.sh /mnt/us/extensions/kindle-billboard/bin/*.sh
mkdir -p /mnt/us/billboard/state /mnt/us/billboard/logs
cat >/mnt/us/billboard/config.env <<EOF
: "`${BILLBOARD_URL:=${BillboardUrl}}"
: "`${INTERVAL_SECONDS:=${IntervalSeconds}}"
: "`${USE_SUSPEND:=${UseSuspend}}"
: "`${FETCH_TIMEOUT_SECONDS:=${FetchTimeoutSeconds}}"
: "`${FETCH_RETRIES:=${FetchRetries}}"
: "`${RENDER_ON_CHANGE:=${RenderOnChange}}"
: "`${STATE_DIR:=/mnt/us/billboard/state}"
: "`${LOG_DIR:=/mnt/us/billboard/logs}"
: "`${STOP_FLAG:=`$STATE_DIR/stop.flag}"
: "`${PID_FILE:=`$STATE_DIR/poller.pid}"
: "`${LOCK_DIR:=`$STATE_DIR/poller.lock}"
: "`${LOG_FILE:=`$LOG_DIR/poller.log}"
: "`${LAST_RESULT_FILE:=`$STATE_DIR/last_result}"
: "`${LAST_SUCCESS_FILE:=`$STATE_DIR/last_success}"
EOF
if [ "${startPollerFlag}" = "1" ]; then
  /mnt/us/billboard/stop-poller.sh >/dev/null 2>&1 || true
  /mnt/us/billboard/start-poller.sh
fi
/mnt/us/billboard/status.sh
'
"@

$script = $script.Replace("__AUTH_MODE__", $sshAuthMode)
$script = $script.Replace("__SSH_KEY_PATH__", $sshKeyWsl)
$script = $script.Replace("__SSH_PASSWORD__", $SshPassword)

wsl.exe -d $Distro -u root -e bash -lc $script
