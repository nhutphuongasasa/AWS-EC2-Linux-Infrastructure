#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/lab-web-monitor.conf"
LOG_FILE="/var/log/lab-web/server-healthcheck.log"

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

log(){
	echo "$(date '+ %F %T') [$1] $2" | tee -a "$LOG_FILE"
}

WARNINGS=0
CRITICALS=0

trap 'log ERROR "Loi o dong $LINENO"' ERR

log INFO "========== Server health check started =========="

free -h | tee -a "$LOG_FILE"

#Disk
for path in "$PROJECT_DIR"; do
	if [[ ! -e "$path"  ]]; then
		log ERROR "path khong ton tai!"
		CRITICALS=$((CRITICALS + 1))
		continue
	fi
	
	usage_percent=$(df -P "$path" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
	mount_folder=$(df -P "$path" | awk 'NR==2 {print $6}')
	
	if (( usage_percent >= DISK_CRIT ));then
		log ERROR "Disk critical: $mount_folder da duoc su dung ${usage_percent}%"
		CRITICALS=$((CRITICALS + 1))
	elif (( usage_percent >= DISK_WARN ));then
		log WARN "Disk warning: $mount_folder da duoc su dung ${usage_percent}% "
        	WARNINGS=$((WARNINGS + 1))
	else
		log INFO "Disk OK: $mount_folder da duoc su dung ${usage_percent}%"
	fi
done

#Docker

if ! command -v docker >/dev/null 2>&1;then
	log ERROR "docker chua duoc cai dat!"
	CRITICALS=$((CRITICALS + 1))
elif [[ ! -f "$COMPOSE_FILE"  ]];then
        log ERROR "docker compose khong ton tai!"
        CRITICALS=$((CRITICALS + 1))
elif ! docker compose -f "$COMPOSE_FILE" config --services 2&>1 /dev/null; then
	log ERROR "khong the doc duoc file docker compose!"
	CRITICALS=$((CRITICALS + 1))
else
	services=$(docker compose -f "$COMPOSE_FILE" config --services)
	running=$(docker compose -f "$COMPOSE_FILE" ps --status running --services 2> /dev/null)
	
	for service in $services; do 
		if echo "$running" | grep -Fxq -- "$service"; then
			log INFO "dich vu dang chay: $service"
		else
			log ERROR "dich vu co loi: $service"
		fi
	done 
fi

#http

http_code=$( curl -sSL -m 5 -o /dev/null -w '%{http_code}' "$HTTP_URL" 2>/dev/null )

if (( $? ==0 )); then
	case "$http_code" in
		2??)
			log INFO "HTTP ok"
			;;
		*)
			log ERROR "HTTP kiem tra that bai!"
			CRITICALS=$((CRITICALS + 1))
			;;
	esac
else
	log ERROR "HTTP request failed: $HTTP_URL"
	CRITICALS=$((CRITICALS + 1))
fi

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
