# Fedora Thin Client RDP

Solution complète pour transformer une machine Fedora en client léger RDP automatique.

Au démarrage : Fedora boot → auto-login utilisateur kiosk → session GNOME minimale → xfreerdp plein écran → reconnexion auto.

## Compatibilité

- Fedora 39, 40, 41, 42 (Workstation ou Server + GNOME minimal)
- Windows Server RDS 2016+ (recommandé 2019/2022/2025)
- FreeRDP 3.x (binaire `xfreerdp3`)

## Structure du projet

```
fedora-thinclient-rdp/
├── install.sh                  # Installation tout-en-un (un poste)
├── uninstall.sh                # Désinstallation
├── scripts/
│   ├── kiosk-session.sh        # Session graphique minimale (mutter + RDP)
│   ├── rdp-launcher.sh         # Boucle xfreerdp avec reconnexion
│   └── kiosk-watchdog.sh       # Watchdog GDM
├── config/config               # Variables RDP (serveur, domaine, etc.)
├── gdm/custom.conf             # Auto-login GDM, X11 forcé
├── xsessions/kiosk-rdp.desktop # Définition session graphique
├── accountsservice/kiosk       # Session par défaut pour user kiosk
├── dconf/                      # Lockdown GNOME (kiosque)
├── systemd/                    # Service watchdog
├── logind.conf.d/              # Désactivation TTY supplémentaires
├── logrotate/                  # Rotation logs
├── ansible/                    # Rôle Ansible pour déploiement parc
└── docs/                       # Documentation détaillée
```

## Installation rapide (un poste)

```bash
sudo ./install.sh
# ou avec jonction AD automatique :
sudo ./install.sh --join-domain DOMAIN.LOCAL --admin Administrator

# Éditer la config
sudo nano /etc/kiosk-rdp/config

# Reboot
sudo systemctl reboot
```

## Déploiement parc (Ansible)

```bash
cd ansible/
# Adapter inventory.ini et les variables dans playbook.yml
ansible-playbook -i inventory.ini playbook.yml
```

## Configuration

Toute la configuration réseau/RDP est centralisée dans `/etc/kiosk-rdp/config` :

| Variable                  | Description                                   | Défaut          |
|---------------------------|-----------------------------------------------|-----------------|
| `RDP_SERVER`              | Hôte RDS / poste cible                        | rds.domain.local|
| `RDP_DOMAIN`              | Domaine AD                                    | DOMAIN          |
| `RDP_PORT`                | Port RDP                                      | 3389            |
| `USE_KERBEROS`            | SSO Kerberos                                  | true            |
| `RECONNECT_DELAY`         | Délai entre tentatives (s)                    | 3               |
| `MAX_RECONNECT_ATTEMPTS`  | 0 = infini                                    | 0               |
| `NETWORK_PROFILE`         | auto / lan / broadband-low / wan / modem      | auto            |
| `MULTIMON`                | Multi-écrans                                  | true            |
| `AUDIO_MODE`              | remote / local / off                          | remote          |
| `CLIPBOARD`               | Sync presse-papier                            | true            |
| `USE_GATEWAY`             | RD Gateway                                    | false           |
| `GATEWAY_HOST`            | Hôte Gateway                                  | (vide)          |

## Sécurité

- Utilisateur `kiosk` local **verrouillé** (auto-login uniquement, pas de mdp)
- Aucun credential RDP stocké : NLA + Kerberos ou prompt utilisateur
- TTY désactivés (`logind.conf.d/kiosk.conf`)
- GNOME locké (dconf : pas de logout, pas de print, pas de lockscreen)
- Sudo refusé pour kiosk
- Firewall en zone block par défaut

### Recommandation : Kerberos SSO

Joindre le poste à AD via `realm join` pour permettre Kerberos :
```bash
sudo realm join DOMAIN.LOCAL --user=Administrator
```
L'utilisateur saisira ses identifiants AD une fois dans la fenêtre RDP, NLA gère le reste.

### Validation certificat RDS (production)

Remplacer dans `rdp-launcher.sh` :
```
/cert:tofu
```
par :
```
/cert:fingerprints:sha256:AA:BB:CC:DD:...
```

## Accès admin

Comme tout est verrouillé côté kiosk, prévoir SSH sur les postes (clé admin uniquement).

## Logs

- `/var/log/kiosk-rdp/kiosk.log` : logs xfreerdp + launcher
- `journalctl -u kiosk-watchdog` : watchdog GDM
- `journalctl -u gdm` : GDM

## Limites connues

- Wayland + multimon FreeRDP encore instable → X11 forcé
- Périphériques USB redirigés peu fiables (à tester cas par cas)
- Caméra WebRTC en RDP : limité
- Veille à désactiver totalement (problèmes reconnexion au réveil)

Voir `docs/` pour la documentation détaillée.
