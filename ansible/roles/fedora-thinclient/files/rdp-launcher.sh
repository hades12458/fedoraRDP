#!/bin/bash
#
# RDP Launcher - Thin Client Fedora
# Déployer dans /usr/local/bin/rdp-launcher.sh
#
# Lance xfreerdp en boucle avec gestion d'erreurs et reconnexion auto.
#

set -u

CONFIG_FILE="/etc/kiosk-rdp/config"
LOG_FILE="/var/log/kiosk-rdp/$(whoami).log"
LOCK_FILE="/tmp/rdp-launcher-$(whoami).lock"

# Création log
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="/tmp/kiosk-rdp.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Source config
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERREUR: Fichier de config $CONFIG_FILE manquant"
    sleep 10
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Verrou anti-double-instance
if [[ -e "$LOCK_FILE" ]]; then
    if kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
        log "Instance déjà active (PID $(cat "$LOCK_FILE"))"
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Attendre réseau opérationnel
wait_for_network() {
    local max=60
    local i=0
    log "Attente connectivité réseau et résolution DNS..."
    while [[ $i -lt $max ]]; do
        if getent hosts "$RDP_SERVER" >/dev/null 2>&1 && \
           ping -c1 -W2 "$RDP_SERVER" >/dev/null 2>&1; then
            log "Réseau OK, serveur $RDP_SERVER joignable"
            return 0
        fi
        sleep 2
        ((i++))
    done
    log "ATTENTION: Timeout réseau, tentative quand même"
    return 1
}

# Authentification Kerberos
init_kerberos() {
    if [[ "${USE_KERBEROS:-false}" != "true" ]]; then
        return 0
    fi
    if klist -s 2>/dev/null; then
        log "Ticket Kerberos valide"
        return 0
    fi
    log "Pas de ticket Kerberos, fallback sur authentification interactive RDP"
    return 1
}

# Construction des arguments xfreerdp
build_rdp_args() {
    local args=()

    # Serveur
    args+=("/v:${RDP_SERVER}:${RDP_PORT}")

    # Domaine
    [[ -n "${RDP_DOMAIN:-}" ]] && args+=("/d:${RDP_DOMAIN}")

    # Plein écran + dynamic resize
    args+=("/f")
    args+=("/dynamic-resolution")

    # Multi-écrans
    [[ "${MULTIMON:-false}" == "true" ]] && args+=("/multimon")

    # Performance / qualité
    case "${NETWORK_PROFILE:-auto}" in
        auto)
            args+=("/network:auto")
            ;;
        lan|broadband-high)
            args+=("/network:lan")
            args+=("/gfx:RFX")
            args+=("/gfx-progressive")
            ;;
        broadband-low|wan)
            args+=("/network:broadband")
            args+=("/gfx:AVC444")
            ;;
        modem)
            args+=("/network:modem")
            ;;
    esac

    # Codec / GDI
    args+=("/rfx")
    args+=("/gdi:hw")

    # Audio
    case "${AUDIO_MODE:-remote}" in
        remote)
            args+=("/sound:sys:pulse")
            args+=("/microphone:sys:pulse")
            ;;
        local)
            args+=("/audio-mode:1")
            ;;
        off)
            args+=("/audio-mode:2")
            ;;
    esac

    # Clipboard
    [[ "${CLIPBOARD:-true}" == "true" ]] && args+=("+clipboard")

    # Drives : désactivés par défaut (sécurité)
    args+=("-drives")

    # Sécurité : validation certificat
    # En prod stricte : /cert:fingerprints:sha256:XX:XX...
    args+=("/cert:tofu")

    # NLA
    args+=("/sec:nla")

    # Compression
    args+=("+compression")
    args+=("/compression-level:2")

    # RD Gateway
    if [[ "${USE_GATEWAY:-false}" == "true" && -n "${GATEWAY_HOST:-}" ]]; then
        args+=("/g:${GATEWAY_HOST}")
        args+=("/gd:${RDP_DOMAIN}")
        args+=("/gat:auto")
    fi

    # Optimisations visuelles
    args+=("-themes")
    args+=("-wallpaper")
    args+=("+menu-anims")
    args+=("+window-drag")
    args+=("+fonts")

    # Niveau log
    args+=("/log-level:WARN")

    # Kerberos auto si TGT présent
    if [[ "${USE_KERBEROS:-false}" == "true" ]] && klist -s 2>/dev/null; then
        args+=("/sec:tls")
    fi

    printf '%s\n' "${args[@]}"
}

# Boucle principale
ATTEMPTS=0
wait_for_network
init_kerberos || true

while true; do
    ((ATTEMPTS++)) || true
    log "Tentative #${ATTEMPTS} de connexion à ${RDP_SERVER}"

    # Vérifier DNS avant lancement
    if ! getent hosts "$RDP_SERVER" >/dev/null 2>&1; then
        log "DNS KO, attente 10s"
        sleep 10
        continue
    fi

    # Lecture des args
    mapfile -t RDP_ARGS < <(build_rdp_args)

    log "Lancement: xfreerdp3 ${RDP_ARGS[*]}"
    xfreerdp3 "${RDP_ARGS[@]}"
    EXIT_CODE=$?
    log "xfreerdp terminé avec code $EXIT_CODE"

    case $EXIT_CODE in
        0|131)
            log "Logoff utilisateur, redémarrage session après 2s"
            sleep 2
            ;;
        128|129|130)
            log "Interruption signal, sortie"
            break
            ;;
        *)
            log "Erreur RDP (code $EXIT_CODE), reconnexion dans ${RECONNECT_DELAY}s"
            sleep "${RECONNECT_DELAY:-3}"
            ;;
    esac

    if [[ "${MAX_RECONNECT_ATTEMPTS:-0}" -gt 0 && "$ATTEMPTS" -ge "${MAX_RECONNECT_ATTEMPTS}" ]]; then
        log "Maximum de tentatives atteint, abandon"
        break
    fi
done

log "Fin du launcher RDP"
exit 0
