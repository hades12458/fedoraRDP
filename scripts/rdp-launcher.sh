#!/bin/bash
#
# RDP Launcher - Thin Client Fedora → PC Windows 10/11
# Sans AD, credentials stockés dans /etc/kiosk-rdp/config
# Reconnexion automatique en boucle infinie
#

set -u

CONFIG_FILE="/etc/kiosk-rdp/config"
LOG_FILE="/var/log/kiosk-rdp/$(whoami).log"
LOCK_FILE="/tmp/rdp-launcher-$(whoami).lock"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="/tmp/kiosk-rdp.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Source config
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERREUR: Fichier de config manquant : $CONFIG_FILE"
    sleep 15
    exit 1
fi
source "$CONFIG_FILE"

# Vérifications
for var in RDP_SERVER RDP_USER RDP_PASSWORD; do
    if [[ -z "${!var:-}" ]]; then
        log "ERREUR: $var non défini dans $CONFIG_FILE"
        sleep 15
        exit 1
    fi
done

# Anti-double-instance
if [[ -e "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
    log "Instance déjà active (PID $(cat "$LOCK_FILE"))"
    exit 0
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Attendre que le PC Windows soit joignable
wait_for_host() {
    log "Attente du PC Windows ($RDP_SERVER)..."
    local i=0
    while [[ $i -lt 150 ]]; do
        if ping -c1 -W2 "$RDP_SERVER" >/dev/null 2>&1; then
            log "PC Windows joignable."
            return 0
        fi
        sleep 2
        ((i++)) || true
    done
    log "Timeout réseau — tentative quand même"
}

# Arguments xfreerdp pour PC Windows 10/11 classique (pas de serveur RDS)
build_rdp_args() {
    local args=()

    # Cible
    args+=("/v:${RDP_SERVER}:${RDP_PORT:-3389}")

    # Credentials (compte local Windows, pas de domaine AD)
    args+=("/u:${RDP_USER}")
    args+=("/p:${RDP_PASSWORD}")
    [[ -n "${RDP_DOMAIN:-}" ]] && args+=("/d:${RDP_DOMAIN}")

    # Plein écran
    args+=("/f")
    args+=("/dynamic-resolution")

    # Multi-écrans (désactivé par défaut pour PC simple)
    [[ "${MULTIMON:-false}" == "true" ]] && args+=("/multimon")

    # Sécurité : PC Windows 10/11 utilisent NLA par défaut
    # /sec:nla = NLA (standard), /cert:ignore = accepter le cert auto-signé du PC
    args+=("/sec:nla")
    args+=("/cert:ignore")

    # Réseau LAN local (PC sur le même réseau)
    args+=("/network:lan")

    # Codec (RemoteFX si dispo, sinon bitmap classique)
    args+=("/gdi:hw")

    # Audio depuis le PC Windows vers le Fedora
    case "${AUDIO_MODE:-remote}" in
        remote) args+=("/sound:sys:pulse") ;;
        off)    args+=("/audio-mode:2") ;;
    esac

    # Presse-papier
    [[ "${CLIPBOARD:-true}" == "true" ]] && args+=("/clipboard")

    # Pas de redirection de lecteurs locaux (sécurité)
    args+=("-drives")
    args+=("-home-drive")

    # Qualité visuelle correcte pour LAN
    args+=("+fonts")
    args+=("+window-drag")
    args+=("/rfx")

    # Log minimal
    args+=("/log-level:WARN")

    printf '%s\n' "${args[@]}"
}

# Boucle principale
ATTEMPTS=0
wait_for_host

while true; do
    ((ATTEMPTS++)) || true
    log "Tentative #${ATTEMPTS} → ${RDP_SERVER}:${RDP_PORT:-3389} (user: ${RDP_USER})"

    # Revérifier joignabilité avant chaque tentative
    if ! ping -c1 -W3 "$RDP_SERVER" >/dev/null 2>&1; then
        log "PC Windows injoignable, attente ${RECONNECT_DELAY:-5}s..."
        sleep "${RECONNECT_DELAY:-5}"
        continue
    fi

    mapfile -t RDP_ARGS < <(build_rdp_args)
    xfreerdp3 "${RDP_ARGS[@]}"
    EXIT_CODE=$?
    log "xfreerdp terminé — code $EXIT_CODE"

    case $EXIT_CODE in
        0|131)
            # Déconnexion normale (logout Windows) → relance rapide
            log "Session terminée proprement, relance dans 2s"
            sleep 2
            ;;
        128|129|130)
            # Signal kill/interrupt → on sort
            log "Signal d'arrêt reçu, extinction"
            break
            ;;
        *)
            # Erreur réseau, PC éteint, etc. → attente avant retry
            log "Erreur connexion (code $EXIT_CODE), retry dans ${RECONNECT_DELAY:-5}s"
            sleep "${RECONNECT_DELAY:-5}"
            ;;
    esac

    # Limite de tentatives (0 = infini)
    if [[ "${MAX_RECONNECT_ATTEMPTS:-0}" -gt 0 && "$ATTEMPTS" -ge "${MAX_RECONNECT_ATTEMPTS}" ]]; then
        log "Nombre maximum de tentatives atteint, abandon"
        break
    fi
done

log "Launcher RDP arrêté"
exit 0
