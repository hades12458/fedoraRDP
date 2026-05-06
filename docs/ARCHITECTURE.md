# Architecture détaillée

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE                            │
│                                                              │
│  ┌──────────────┐         ┌──────────────────────────────┐  │
│  │ AD / DNS     │◄───────►│ Windows Server RDS           │  │
│  │ (DC)         │         │ - Connection Broker          │  │
│  └──────────────┘         │ - Session Host(s)            │  │
│         ▲                 │ - RD Gateway (optionnel)     │  │
│         │                 └──────────────────────────────┘  │
│         │                          ▲                         │
│         │                          │ RDP (3389) ou           │
│         │                          │ HTTPS (443) via Gateway │
│  ┌──────┴──────────────────────────┴──────┐                 │
│  │           VLAN clients légers          │                 │
│  └────────────────────────────────────────┘                 │
│         ▲              ▲              ▲                      │
│         │              │              │                      │
│  ┌──────┴────┐  ┌─────┴─────┐  ┌────┴──────┐                │
│  │ Fedora #1 │  │ Fedora #2 │  │ Fedora #N │                │
│  └───────────┘  └───────────┘  └───────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Chaîne de boot

1. **POST/UEFI** → bootloader (GRUB)
2. **systemd** → `graphical.target`
3. **GDM** auto-login utilisateur `kiosk` (X11)
4. **Session graphique** : `kiosk-rdp.desktop` → `kiosk-session.sh`
5. **Mutter** (gestionnaire de fenêtres minimal) en arrière-plan
6. **rdp-launcher.sh** lance `xfreerdp3` en boucle
7. Fenêtre RDP **plein écran** → utilisateur saisit ses identifiants AD
8. NLA + Kerberos négocie l'auth → session Windows distante

## Profils réseau

| Contexte             | NETWORK_PROFILE   | Codec      | BP estimée |
|----------------------|-------------------|------------|------------|
| LAN gigabit          | `lan`             | RemoteFX   | 5–20 Mbps  |
| LAN 100M / Wi-Fi OK  | `auto`            | Auto       | 2–10 Mbps  |
| WAN / RD Gateway     | `wan`             | AVC444     | 1–4 Mbps   |
| Liaison dégradée     | `modem`           | Bitmap     | < 500 kbps |

## Reprise sur incident

| Scénario              | Mécanisme                        |
|-----------------------|----------------------------------|
| Coupure réseau brève  | Boucle launcher + auto-reconnect |
| Coupure longue        | `wait_for_network()`             |
| RDS injoignable       | DNS check + retry indéfini       |
| xfreerdp crash        | `while true` dans launcher       |
| GNOME crash           | GDM relance la session           |
| GDM crash             | `kiosk-watchdog.service`         |
| Kernel freeze         | watchdog matériel (à activer)    |
| Coupure électrique    | Boot auto → toute la chaîne      |

## Watchdog matériel (recommandé)

```bash
sudo dnf install -y watchdog
sudo sed -i 's|^#watchdog-device.*|watchdog-device = /dev/watchdog|' /etc/watchdog.conf
sudo systemctl enable --now watchdog
```

## Mises à jour OS

```bash
sudo dnf install -y dnf-automatic
sudo systemctl enable --now dnf-automatic.timer
```

Configurer dans `/etc/dnf/automatic.conf` : `apply_updates = yes`

## Reboot programmé hebdomadaire

```ini
# /etc/systemd/system/weekly-reboot.timer
[Unit]
Description=Reboot hebdomadaire

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/weekly-reboot.service
[Unit]
Description=Reboot

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
```
