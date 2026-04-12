param(
    [string]$BusId = "2-1",
    [string]$Distro = "Ubuntu",
    [string]$KindleIp = "192.168.15.244",
    [string]$HostUsbIp = "192.168.15.201",
    [string]$Workspace = "C:\Users\monro\Codex\Kindle reclaim",
    [string]$BillboardUrl = "",
    [int]$IntervalSeconds = 300,
    [int]$UseSuspend = 1,
    [int]$FetchTimeoutSeconds = 30,
    [int]$FetchRetries = 2,
    [int]$RenderOnChange = 1,
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

if (-not $BillboardUrl) {
    $LanIp = Get-LanIPv4
    $BillboardUrl = "http://${LanIp}:8765/current.png"
}

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
export SSHPASS=x
cd "$workspaceWsl"
sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no root@${KindleIp} "mkdir -p /mnt/us/billboard /mnt/us/extensions/kindle-billboard/bin"
sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no billboard/* root@${KindleIp}:/mnt/us/billboard/
sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no kual/kindle-billboard/config.xml root@${KindleIp}:/mnt/us/extensions/kindle-billboard/
sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no kual/kindle-billboard/menu.json root@${KindleIp}:/mnt/us/extensions/kindle-billboard/
sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no kual/kindle-billboard/bin/* root@${KindleIp}:/mnt/us/extensions/kindle-billboard/bin/
sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no root@${KindleIp} '
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

wsl.exe -d $Distro -u root -e bash -lc $script
