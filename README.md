# Fedora Thin Client RDP — PC Windows 10/11

Transforme un PC Fedora en client léger qui se connecte automatiquement en RDP à un PC Windows 10/11 au démarrage. Aucun Active Directory, aucun serveur RDS.

**Comportement :** boot Fedora → auto-login utilisateur `kiosk` → xfreerdp plein écran vers le PC Windows → reconnexion automatique si déconnexion.

## Prérequis côté PC Windows

Activer le Bureau à distance (à faire une seule fois) :

1. **Paramètres → Système → Bureau à distance → Activer**
2. S'assurer que le compte Windows utilisé a **un mot de passe** (Windows refuse les connexions RDP sans mot de passe)
3. Optionnel : noter l'IP du PC Windows (`ipconfig` dans cmd)

> Windows 10/11 **Home** ne supporte pas nativement le Bureau à distance en tant que serveur. Il faut Windows 10/11 **Pro, Education ou Enterprise**.

## Installation (Fedora)

```bash
git clone https://github.com/hades12458/fedoraRDP.git
cd fedoraRDP
sudo ./install.sh
```

Puis éditer la config :

```bash
sudo nano /etc/kiosk-rdp/config
```

Renseigner au minimum :

```bash
RDP_SERVER="192.168.1.XXX"    # IP du PC Windows
RDP_USER="Prenom"              # Compte local Windows
RDP_PASSWORD="monmotdepasse"   # Mot de passe Windows
```

Puis reboot :

```bash
sudo systemctl reboot
```

## Structure

```
fedoraRDP/
├── install.sh                  # Installation tout-en-un
├── uninstall.sh                # Désinstallation
├── config/config               # Variables RDP (à remplir !)
├── scripts/
│   ├── kiosk-session.sh        # Session X11 minimale (mutter)
│   ├── rdp-launcher.sh         # Boucle xfreerdp + reconnexion auto
│   └── kiosk-watchdog.sh       # Watchdog GDM
├── gdm/custom.conf             # Auto-login GDM, X11 forcé
├── xsessions/kiosk-rdp.desktop # Définition de la session
├── accountsservice/kiosk       # Session par défaut utilisateur kiosk
├── dconf/                      # Verrouillage GNOME (kiosque)
├── systemd/                    # Service watchdog
├── logind.conf.d/              # Désactivation TTY inutiles
└── logrotate/                  # Rotation des logs
```

## Ce qui se passe au démarrage

```
Boot Fedora
  └─> GDM auto-login → utilisateur "kiosk" (pas de prompt)
        └─> kiosk-rdp.desktop → kiosk-session.sh
              └─> mutter (gestionnaire fenêtres léger)
              └─> rdp-launcher.sh
                    └─> Attend que le PC Windows soit joignable
                    └─> xfreerdp3 plein écran → PC Windows
                          └─> Prompt login Windows (NLA)
                          └─> Session Windows
                    └─> Si déconnexion → relance auto dans 5s
```

## Configuration complète

| Variable               | Description                          | Défaut    |
|------------------------|--------------------------------------|-----------|
| `RDP_SERVER`           | IP ou hostname du PC Windows         | à remplir |
| `RDP_USER`             | Nom du compte Windows local          | à remplir |
| `RDP_PASSWORD`         | Mot de passe Windows                 | à remplir |
| `RDP_DOMAIN`           | Domaine (vide = compte local)        | vide      |
| `RDP_PORT`             | Port RDP                             | 3389      |
| `RECONNECT_DELAY`      | Délai entre tentatives (secondes)    | 5         |
| `MAX_RECONNECT_ATTEMPTS` | 0 = infini                         | 0         |
| `MULTIMON`             | Multi-écrans                         | false     |
| `AUDIO_MODE`           | remote / off                         | remote    |
| `CLIPBOARD`            | Presse-papier partagé                | true      |

## Dépannage

**Le PC Windows refuse la connexion :**
- Vérifier que le Bureau à distance est activé (Paramètres → Système)
- Vérifier que le compte Windows a un mot de passe
- Windows Home ne supporte pas le RDP entrant

**xfreerdp ne se lance pas :**
- `journalctl -u kiosk-watchdog` pour voir les erreurs
- `cat /var/log/kiosk-rdp/kiosk.log`

**Revenir à un Fedora normal :**
```bash
sudo ./uninstall.sh
sudo systemctl reboot
```

## Accès admin au Fedora

SSH recommandé (TTY désactivés côté kiosk) :
```bash
# Créer un compte admin sur le Fedora avant l'install
sudo useradd -m admin && sudo passwd admin
# Puis depuis un autre PC :
ssh admin@IP_DU_FEDORA
```
