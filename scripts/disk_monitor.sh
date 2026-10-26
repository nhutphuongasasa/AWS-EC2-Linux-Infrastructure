#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/lab-web-monitor.conf"
LOG_FILE="/home/phuong/lab-web/logs/disk-monitor.log"
STATE_FILE="/home/phuong/lab-web/logs/disk-monitor.state"

if [[ ! -r "$CONFIG"  ]]; then
        echo "ERROR: path config bi loi" 
        exit 1
fi

source "$CONFIG"
: "${PROJECT_DIR:?Missing PROJECT_DIR}"
: "${COMPOSE_FILE:?Missing COMPOSE_FILE}"
: "${HTTP_URL:?Missing HTTP_URL}"
: "${DISK_WARN:?Missing DISK_WARN}"
: "${DISK_CRIT:?Missing DISK_CRIT}"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$STATE_FILE")"

WARN=${DISK_WARN_OVERRIDE:-${DISK_WARN:-80}}
CRIT=${DISK_CRIT_OVERRIDE:-${DISK_CRIT:-90}}

if (( WARN < 1 || CRIT > 100 || WARN >= CRIT )); then
	echo "Nguong WARN va CRIT vo li!"
	exit 1
fi

log(){
        echo "$(date '+ %F %T') [$1] $2" | tee -a "$LOG_FILE"
}

WARNINGS=0
CRITICALS=0
NEW_STATE=""

disks=$(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs | awk 'NR>1 {gsub(/%/,"", $5); print $5, $6}' )

IFS=$'\n'
for line in $disks; do
	usage=$(echo "$line" | awk '{print $1}')
	mount=$(echo "$line" | awk '{print $2}')
	level=OK
	if (( usage >= CRIT )); then
		level=CRITICAL
		CRITICALS=$((CRITICALS + 1))
	elif (( usage >= WARN )); then
		level=WARN
		WARNINGS=$((WARNINGS + 1))
	else
		 log INFO "$mount usage=${usage}% OK"
	fi
done
unset IFS

log INFO "Tong ket: warnings=$WARNINGS criticals=$CRITICALS"

if (( CRITICALS > 0 )); then
    log ERROR "Healthcheck: co loi nghiem trong"
    exit 2
elif (( WARNINGS > 0 )); then
    log WARN "Healthcheck: canh bao"
    exit 1
else
    log INFO "Healthcheck: OK!"
    exit 0
fi
