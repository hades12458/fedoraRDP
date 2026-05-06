#!/bin/bash
#
# uninstall.sh - Désinstallation thin client RDP
#

set -e
[[ $EUID -ne 0 ]] && { echo "Lancer en root."; exit 1; }

systemctl disable --now kiosk-watchdog.service 2>/dev/null || true
rm -f /etc/systemd/system/kiosk-watchdog.service

rm -f /usr/local/bin/kiosk-session.sh
rm -f /usr/local/bin/rdp-launcher.sh
rm -f /usr/local/bin/kiosk-watchdog.sh

rm -f /usr/share/xsessions/kiosk-rdp.desktop
rm -f /var/lib/AccountsService/users/kiosk
rm -rf /etc/kiosk-rdp
rm -rf /var/log/kiosk-rdp

rm -f /etc/dconf/db/kiosk.d/00-lockdown
rm -f /etc/dconf/db/kiosk.d/locks/lockdown
rm -f /etc/dconf/profile/user
dconf update

rm -f /etc/systemd/logind.conf.d/kiosk.conf
rm -f /etc/logrotate.d/kiosk-rdp
rm -f /etc/sudoers.d/99-kiosk-deny

# Reset GDM auto-login (à adapter)
sed -i 's/^AutomaticLoginEnable=True/AutomaticLoginEnable=False/' /etc/gdm/custom.conf 2>/dev/null || true

systemctl daemon-reload

echo "Désinstallation terminée. Redémarrez pour valider."
echo "L'utilisateur 'kiosk' n'a PAS été supprimé (faire 'userdel -r kiosk' si besoin)."
