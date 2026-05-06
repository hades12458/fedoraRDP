# Checklist mise en production

## Préparation infrastructure

- [ ] Serveur RDS opérationnel (CAL configurées, certificat valide)
- [ ] AD / DNS résolvant correctement le serveur RDS
- [ ] VLAN clients léger isolé du reste du réseau
- [ ] NTP configuré (Kerberos exige horloges synchro à ±5min)
- [ ] RD Gateway configuré si accès externe
- [ ] Stratégie GPO RDS : limiter sessions par user, redirections, etc.

## Préparation poste master

- [ ] Fedora installée (Workstation ou Server + GNOME minimal)
- [ ] Réseau configuré (DHCP ou statique)
- [ ] Hostname unique et significatif
- [ ] Jonction AD testée (`realm join`)
- [ ] `install.sh` exécuté sans erreur
- [ ] `/etc/kiosk-rdp/config` édité avec bonnes valeurs

## Tests fonctionnels

- [ ] Boot → auto-login `kiosk` OK
- [ ] xfreerdp se lance plein écran
- [ ] Saisie credentials AD → session Windows OK
- [ ] Multi-écrans détectés (si applicable)
- [ ] Audio fonctionnel
- [ ] Clipboard fonctionnel
- [ ] Logout Windows → relance auto session RDP
- [ ] Coupure réseau 30s → reconnexion auto
- [ ] Coupure réseau longue → boucle de tentatives propre
- [ ] Kill xfreerdp manuel → relance auto
- [ ] Reboot hard (coupure secteur) → tout repart

## Sécurité

- [ ] Validation fingerprint RDS configurée (pas `tofu` en prod)
- [ ] TTY désactivés
- [ ] Sudo refusé pour kiosk
- [ ] Compte admin local séparé créé
- [ ] SSH activé pour admin avec clé uniquement
- [ ] Firewall en zone block
- [ ] Pas de mot de passe RDP stocké en clair

## Industrialisation

- [ ] Rôle Ansible testé sur 1 poste
- [ ] Inventaire complet généré
- [ ] Image de clonage créée (Clonezilla / FOG)
- [ ] Procédure de réinstallation documentée
- [ ] Logs centralisés (rsyslog)
- [ ] Monitoring (Zabbix / Prometheus / Centreon)
- [ ] Plan de bascule si RDS down (message clair, second serveur)

## Documentation utilisateur

- [ ] Doc utilisateur final (comment se connecter, mdp oublié, etc.)
- [ ] Doc équipe support (comment intervenir sur poste verrouillé)
- [ ] Procédure escalade incident
