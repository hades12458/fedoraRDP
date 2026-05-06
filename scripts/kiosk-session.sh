#!/bin/bash
# Session graphique minimale pour kiosque RDP
# Déployer dans /usr/local/bin/kiosk-session.sh

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=KioskRDP

# Désactiver veille / DPMS
xset s off
xset -dpms
xset s noblank

# Désactiver Ctrl+Alt+Backspace (kill X)
setxkbmap -option terminate:ctrl_alt_bksp

# Curseur visible
xsetroot -cursor_name left_ptr

# Lancer mutter (gestionnaire de fenêtres léger, sans shell GNOME)
mutter --x11 &
MUTTER_PID=$!

# Petite latence pour init mutter
sleep 1

# Lancer le script RDP en boucle (bloquant)
exec /usr/local/bin/rdp-launcher.sh
