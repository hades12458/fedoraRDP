#!/bin/bash
# Watchdog - surveille GDM, redémarre si inactif
# Déployer dans /usr/local/bin/kiosk-watchdog.sh

while true; do
    if ! systemctl is-active --quiet gdm; then
        logger -t kiosk-watchdog "GDM inactif, redémarrage"
        systemctl restart gdm
        sleep 30
    fi
    sleep 30
done
