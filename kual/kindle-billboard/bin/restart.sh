#!/bin/sh
LOG_FILE="/mnt/us/billboard/logs/kual-actions.log"
mkdir -p /mnt/us/billboard/logs
printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "kual restart" >>"$LOG_FILE"
exec /bin/sh /mnt/us/billboard/restart-poller.sh >>"$LOG_FILE" 2>&1
