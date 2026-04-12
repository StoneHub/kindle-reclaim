param(
    [string]$BusId = "2-1",
    [string]$Distro = "Ubuntu",
    [string]$KindleIp = "192.168.15.244",
    [string]$HostUsbIp = "192.168.15.201",
    [string]$Workspace = "C:\Users\monro\Codex\Kindle reclaim"
)

$ErrorActionPreference = "Stop"

$usbipd = "C:\Program Files\usbipd-win\usbipd.exe"
& $usbipd attach --wsl $Distro --busid $BusId | Out-Null

$workspaceWsl = "/mnt/c/Users/monro/Codex/Kindle reclaim"
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
sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no root@${KindleIp} "chmod +x /mnt/us/billboard/*.sh /mnt/us/extensions/kindle-billboard/bin/*.sh; [ -f /mnt/us/billboard/config.env ] || cp /mnt/us/billboard/config.env.example /mnt/us/billboard/config.env"
"@

wsl.exe -d $Distro -u root -e bash -lc $script
