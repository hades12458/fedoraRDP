#!/bin/bash
#
# install.sh - Fedora Thin Client RDP → PC Windows 10/11
# Sans Active Directory, connexion directe avec compte local Windows
#
# Usage: sudo ./install.sh
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

[[ $EUID -ne 0 ]] && { echo "Lancer en root : sudo ./install.sh"; exit 1; }

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[1;31m[✗]\033[0m $*"; exit 1; }

echo ""
echo "======================================================"
echo "  Fedora Thin Client RDP — Installation (sans AD)"
echo "======================================================"
echo ""

# === 1. Paquets ===
log "Installation des paquets nécessaires..."
dnf install -y \
    freerdp \
    gnome-session \
    gnome-settings-daemon \
    mutter \
    gdm \
    NetworkManager \
    dconf-cli \
    chrony \
    xorg-x11-server-utils \
    xset \
    iputils 2>/dev/null || \
dnf install -y --best --allowerasing \
    freerdp gnome-session gnome-settings-daemon mutter gdm \
    NetworkManager dconf-cli chrony xorg-x11-server-utils xset iputils

# Vérifier que xfreerdp3 est disponible (Fedora 39+ l'appelle xfreerdp3)
if ! command -v xfreerdp3 &>/dev/null; then
    if command -v xfreerdp &>/dev/null; then
        log "xfreerdp3 non trouvé, création d'un alias vers xfreerdp..."
        ln -sf "$(command -v xfreerdp)" /usr/local/bin/xfreerdp3
    else
        err "xfreerdp non trouvé après installation. Vérifiez votre version de Fedora."
    fi
fi

systemctl enable --now chronyd
systemctl set-default graphical.target

# === 2. Utilisateur kiosk ===
log "Création de l'utilisateur kiosk (auto-login, sans mot de passe)..."
if ! id kiosk &>/dev/null; then
    useradd -m -s /bin/bash -c "Kiosk RDP" kiosk
fi
passwd -l kiosk   # verrouille le mdp (auto-login uniquement)

# Refuser sudo pour kiosk
echo "kiosk ALL=(ALL) !ALL" > /etc/sudoers.d/99-kiosk-deny
chmod 0440 /etc/sudoers.d/99-kiosk-deny

# === 3. Scripts ===
log "Déploiement des scripts..."
install -m 0755 "$SCRIPT_DIR/scripts/kiosk-session.sh"  /usr/local/bin/kiosk-session.sh
install -m 0755 "$SCRIPT_DIR/scripts/rdp-launcher.sh"   /usr/local/bin/rdp-launcher.sh
install -m 0755 "$SCRIPT_DIR/scripts/kiosk-watchdog.sh" /usr/local/bin/kiosk-watchdog.sh

# === 4. Configuration RDP ===
log "Déploiement de la configuration RDP..."
mkdir -p /etc/kiosk-rdp
install -m 0600 "$SCRIPT_DIR/config/config" /etc/kiosk-rdp/config
chown root:root /etc/kiosk-rdp/config   # le mot de passe est dedans, root seulement

mkdir -p /var/log/kiosk-rdp
chown kiosk:kiosk /var/log/kiosk-rdp

# === 5. GDM — auto-login ===
log "Configuration GDM (auto-login kiosk, X11 forcé)..."
install -m 0644 "$SCRIPT_DIR/gdm/custom.conf" /etc/gdm/custom.conf

# === 6. Session graphique ===
log "Installation de la session kiosk-rdp..."
install -m 0644 "$SCRIPT_DIR/xsessions/kiosk-rdp.desktop" /usr/share/xsessions/kiosk-rdp.desktop

mkdir -p /var/lib/AccountsService/users
install -m 0600 "$SCRIPT_DIR/accountsservice/kiosk" /var/lib/AccountsService/users/kiosk

# === 7. dconf — verrouillage GNOME ===
log "Application des restrictions GNOME (dconf)..."
mkdir -p /etc/dconf/profile /etc/dconf/db/kiosk.d/locks
install -m 0644 "$SCRIPT_DIR/dconf/profile/user"              /etc/dconf/profile/user
install -m 0644 "$SCRIPT_DIR/dconf/db/kiosk.d/00-lockdown"   /etc/dconf/db/kiosk.d/00-lockdown
install -m 0644 "$SCRIPT_DIR/dconf/db/kiosk.d/locks/lockdown" /etc/dconf/db/kiosk.d/locks/lockdown
dconf update

# === 8. Watchdog systemd ===
log "Activation du watchdog GDM..."
install -m 0644 "$SCRIPT_DIR/systemd/kiosk-watchdog.service" /etc/systemd/system/kiosk-watchdog.service
systemctl daemon-reload
systemctl enable kiosk-watchdog.service

# === 9. logind (désactive TTY inutiles) ===
log "Configuration logind..."
mkdir -p /etc/systemd/logind.conf.d
install -m 0644 "$SCRIPT_DIR/logind.conf.d/kiosk.conf" /etc/systemd/logind.conf.d/kiosk.conf

# === 10. logrotate ===
install -m 0644 "$SCRIPT_DIR/logrotate/kiosk-rdp" /etc/logrotate.d/kiosk-rdp

# === 11. Firewall — fermer tout sauf sortant ===
log "Durcissement firewall (zone block, uniquement sortant)..."
if systemctl is-active --quiet firewalld; then
    firewall-cmd --set-default-zone=block 2>/dev/null || true
    firewall-cmd --permanent --zone=block --add-service=dhcpv6-client 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi

# === SELinux : autoriser xfreerdp à se connecter ===
if command -v setsebool &>/dev/null; then
    setsebool -P nis_enabled 1 2>/dev/null || true
fi

echo ""
echo "======================================================"
echo "  INSTALLATION TERMINÉE"
echo "======================================================"
echo ""
echo "  ÉTAPE OBLIGATOIRE avant de redémarrer :"
echo ""
echo "  sudo nano /etc/kiosk-rdp/config"
echo ""
echo "  → Renseigner RDP_SERVER  (IP du PC Windows)"
echo "  → Renseigner RDP_USER    (nom du compte Windows)"
echo "  → Renseigner RDP_PASSWORD (mot de passe Windows)"
echo ""
echo "  Côté PC Windows (à faire une seule fois) :"
echo "  → Paramètres → Système → Bureau à distance → Activer"
echo "  → Autoriser les connexions depuis n'importe quel ordinateur"
echo "  → Vérifier que le compte utilisé a un mot de passe défini"
echo ""
echo "  Puis redémarrer ce Fedora :"
echo "  sudo systemctl reboot"
echo ""
echo "======================================================"
