#!/bin/bash
#
# install.sh - Déploiement complet thin client Fedora RDP
# À exécuter en root sur la machine cible
#
# Usage: sudo ./install.sh [--join-domain DOMAIN.LOCAL --admin admin]
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
JOIN_DOMAIN=""
DOMAIN_ADMIN=""

# Parsing args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --join-domain) JOIN_DOMAIN="$2"; shift 2 ;;
        --admin)       DOMAIN_ADMIN="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | head -20
            exit 0
            ;;
        *) echo "Argument inconnu: $1"; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être lancé en root."
    exit 1
fi

log() { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# === 1. Paquets ===
log "Installation des paquets..."
dnf install -y \
    freerdp \
    gnome-session \
    gnome-settings-daemon \
    mutter \
    gdm \
    NetworkManager \
    sssd sssd-ad sssd-tools \
    realmd adcli krb5-workstation \
    samba-common-tools oddjob oddjob-mkhomedir \
    dconf-cli \
    chrony \
    xorg-x11-server-utils \
    xset

systemctl enable --now chronyd
systemctl set-default graphical.target

# === 2. Jonction AD (optionnelle) ===
if [[ -n "$JOIN_DOMAIN" && -n "$DOMAIN_ADMIN" ]]; then
    log "Jonction au domaine $JOIN_DOMAIN..."
    realm join --user="$DOMAIN_ADMIN" "$JOIN_DOMAIN" || warn "Jonction AD échouée, continuation..."
    realm permit -g "Domain Users" || true
fi

# === 3. Utilisateur kiosk ===
log "Création utilisateur kiosk..."
if ! id kiosk &>/dev/null; then
    useradd -m -s /bin/bash -c "Kiosk RDP User" kiosk
    passwd -l kiosk
fi

# Restriction sudo
echo "kiosk ALL=(ALL) !ALL" > /etc/sudoers.d/99-kiosk-deny
chmod 0440 /etc/sudoers.d/99-kiosk-deny

# === 4. Déploiement scripts ===
log "Déploiement scripts /usr/local/bin..."
install -m 0755 "$SCRIPT_DIR/scripts/kiosk-session.sh"  /usr/local/bin/kiosk-session.sh
install -m 0755 "$SCRIPT_DIR/scripts/rdp-launcher.sh"   /usr/local/bin/rdp-launcher.sh
install -m 0755 "$SCRIPT_DIR/scripts/kiosk-watchdog.sh" /usr/local/bin/kiosk-watchdog.sh

# === 5. Configuration ===
log "Déploiement configuration..."
mkdir -p /etc/kiosk-rdp
install -m 0644 "$SCRIPT_DIR/config/config" /etc/kiosk-rdp/config

mkdir -p /var/log/kiosk-rdp
chown kiosk:kiosk /var/log/kiosk-rdp

# === 6. GDM ===
log "Configuration GDM..."
install -m 0644 "$SCRIPT_DIR/gdm/custom.conf" /etc/gdm/custom.conf

# === 7. Session graphique ===
log "Installation session kiosk-rdp..."
install -m 0644 "$SCRIPT_DIR/xsessions/kiosk-rdp.desktop" /usr/share/xsessions/kiosk-rdp.desktop

mkdir -p /var/lib/AccountsService/users
install -m 0600 "$SCRIPT_DIR/accountsservice/kiosk" /var/lib/AccountsService/users/kiosk

# === 8. dconf lockdown ===
log "Application dconf lockdown..."
mkdir -p /etc/dconf/profile /etc/dconf/db/kiosk.d/locks
install -m 0644 "$SCRIPT_DIR/dconf/profile/user" /etc/dconf/profile/user
install -m 0644 "$SCRIPT_DIR/dconf/db/kiosk.d/00-lockdown" /etc/dconf/db/kiosk.d/00-lockdown
install -m 0644 "$SCRIPT_DIR/dconf/db/kiosk.d/locks/lockdown" /etc/dconf/db/kiosk.d/locks/lockdown
dconf update

# === 9. systemd watchdog ===
log "Activation watchdog systemd..."
install -m 0644 "$SCRIPT_DIR/systemd/kiosk-watchdog.service" /etc/systemd/system/kiosk-watchdog.service
systemctl daemon-reload
systemctl enable kiosk-watchdog.service

# === 10. logind ===
log "Configuration logind (désactivation TTY supplémentaires)..."
mkdir -p /etc/systemd/logind.conf.d
install -m 0644 "$SCRIPT_DIR/logind.conf.d/kiosk.conf" /etc/systemd/logind.conf.d/kiosk.conf

# === 11. logrotate ===
install -m 0644 "$SCRIPT_DIR/logrotate/kiosk-rdp" /etc/logrotate.d/kiosk-rdp

# === 12. Firewall durcissement ===
log "Durcissement firewall..."
firewall-cmd --set-default-zone=block || warn "firewall-cmd non disponible"
firewall-cmd --permanent --zone=block --add-service=dhcpv6-client 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

log "Installation terminée."
echo
echo "=========================================="
echo "  ÉTAPES SUIVANTES :"
echo "=========================================="
echo "1. Éditez /etc/kiosk-rdp/config et renseignez RDP_SERVER, RDP_DOMAIN"
echo "2. Si pas déjà fait : realm join votre domaine AD"
echo "3. Redémarrez : systemctl reboot"
echo "4. Pour intervenir admin : SSH ou Ctrl+Alt+F2 (si vous l'avez réactivé)"
echo "=========================================="
