# Sécurité — Recommandations production

## Gestion des credentials RDP

| Méthode                         | Sécurité     | Complexité | Recommandé pour      |
|---------------------------------|--------------|------------|----------------------|
| Mot de passe en clair script    | Très faible  | Triviale   | **Jamais en prod**   |
| `secret-tool` / GNOME Keyring   | Moyenne      | Moyenne    | Postes mono-user     |
| Prompt utilisateur xfreerdp     | Bonne        | Aucune     | Lycée / multi-user   |
| **Kerberos SSO via AD**         | Excellente   | Modérée    | **Prod entreprise**  |
| Smartcard (PKINIT)              | Maximale     | Élevée     | Environnements sensibles |

## Configuration recommandée

1. **Joindre le poste à AD** (`realm join`)
2. **NLA activé** côté serveur RDS (par défaut depuis 2012)
3. **Validation cert RDP** par fingerprint en production
4. **TLS 1.2+ uniquement** sur le serveur RDS
5. **RD Gateway** si accès depuis Internet (pas de RDP exposé direct)

## Validation certificat

Dans `rdp-launcher.sh`, remplacer :
```bash
args+=("/cert:tofu")
```
par :
```bash
args+=("/cert:fingerprints:sha256:AA:BB:CC:DD:EE:FF:...")
```

Pour récupérer le fingerprint :
```bash
echo | openssl s_client -connect rds.domain.local:3389 -starttls rdp 2>/dev/null \
  | openssl x509 -fingerprint -sha256 -noout
```

## Firewall

Le client ne doit avoir **aucun port exposé**. Configuration zone `block` :
```bash
sudo firewall-cmd --set-default-zone=block
sudo firewall-cmd --permanent --zone=block --add-service=dhcpv6-client
sudo firewall-cmd --reload
```

Ports sortants nécessaires :
- **DNS** (53/udp,tcp)
- **Kerberos** (88/tcp,udp)
- **LDAP** (389/tcp) si bind AD
- **NTP** (123/udp)
- **RDP** (3389/tcp) ou **HTTPS** (443/tcp) si RD Gateway

## Verrouillage GNOME

Tous les paramètres dconf appliqués (cf. `dconf/db/kiosk.d/00-lockdown`) :
- Pas de logout
- Pas de user switching
- Pas de lockscreen
- Pas d'impression (sauf si redirigée via RDP)
- Pas de sauvegarde locale

## Désactivation TTY

`logind.conf.d/kiosk.conf` désactive Ctrl+Alt+F1..F6.
**Attention** : prévoir un accès admin (SSH ou raccourci dédié).

## Accès admin

### Option 1 : SSH avec clé

```bash
sudo dnf install -y openssh-server
sudo systemctl enable --now sshd
# Désactiver auth par mot de passe dans /etc/ssh/sshd_config :
#   PasswordAuthentication no
#   PermitRootLogin no
# Déployer la clé admin sur le compte admin local
```

### Option 2 : Raccourci de secours

Réactiver TTY admin uniquement (modifier `logind.conf.d/kiosk.conf`) :
```ini
NAutoVTs=2
ReserveVT=2
```
Puis créer un compte `admin` local en plus de `kiosk`.

## Smartcard (optionnel, sécurité maximale)

```bash
sudo dnf install -y opensc pcsc-lite pcsc-tools
sudo systemctl enable --now pcscd
```

Dans `rdp-launcher.sh`, ajouter :
```bash
args+=("/smartcard")
```

Configurer PKINIT côté AD pour authentification par carte.

## Audit / logs

- Logs RDP : `/var/log/kiosk-rdp/`
- Logs système : `journalctl`
- Centralisation recommandée : rsyslog → serveur central / SIEM
