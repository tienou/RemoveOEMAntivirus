# RemoveOEMAntivirus

Script PowerShell pour supprimer silencieusement McAfee, Norton et autres antivirus OEM pré-installés par les constructeurs (Lenovo, HP, Dell...).

Conçu pour un déploiement **Intune Win32 App**, compatible **ESP Autopilot** (Required app).

## AV supportés

| Éditeur | Méthode |
|---|---|
| **McAfee** (WPS, Personal Security, LiveSafe) | Désactivation self-protection kernel → MCPR mccleanup.exe (double passage) → suppression forcée drivers/services/registre |
| **Norton** (360, Security, LifeLock) | Suppression forcée : kill processus, services, drivers kernel, registre, fichiers, AppX |
| Avast | Désinstallation silencieuse via registre |
| AVG Antivirus | Désinstallation silencieuse via registre |
| Kaspersky | Désinstallation silencieuse via registre |
| Trend Micro | Désinstallation silencieuse via registre |
| Bitdefender | Désinstallation silencieuse via registre |

Supprime également les AppX provisionnés : WildTangent, ExpressVPN, Dropbox Trial.

## Structure du package

```
source/
├── McAfeeRemoval.zip          # MCPR ancienne version (voir section ci-dessous)
├── Install-RemoveOEMAV.ps1    # Script principal (8 phases)
├── Detect-RemoveOEMAV.ps1     # Détection Intune (marqueur + registre + fallback)
└── Uninstall-RemoveOEMAV.ps1  # Supprime le marqueur pour ré-exécution

prod/
└── Install-RemoveOEMAV.intunewin  # Package prêt à déployer
```

## Configuration Intune Win32

| Paramètre | Valeur |
|---|---|
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -File Install-RemoveOEMAV.ps1` |
| **Uninstall command** | `powershell.exe -ExecutionPolicy Bypass -File Uninstall-RemoveOEMAV.ps1` |
| **Detection** | Custom script → `Detect-RemoveOEMAV.ps1` (64-bit, System context) |
| **Install behavior** | System |
| **Assignment** | Required |

## Fonctionnement

### Install (8 phases)

1. **McAfee** — Détection multi-source, extraction ZIP, désactivation self-protection (`mc-sec-unprotector.exe` recherche dynamique), kill processus (liste + wildcard), arrêt services, désactivation + suppression drivers kernel (9 drivers dont ELAM), MCPR `mccleanup.exe` avec double passage si échec, nettoyage complet registre Uninstall (DisplayName + Publisher), suppression dossiers, tâches planifiées, shell extensions. Si fichiers verrouillés → tâche planifiée post-reboot
2. **Norton** — Kill processus, arrêt services, désactivation drivers kernel Symantec, nettoyage registre, suppression dossiers, AppX, tâches planifiées, shell extensions. Si fichiers verrouillés → tâche planifiée post-reboot
3. **AppX McAfee** — Suppression packages provisionnés et installés
4. **Autres AV (registre)** — Désinstallation silencieuse (QuietUninstallString / MSI / UninstallString)
5. **Autres AV (AppX)** — Suppression packages provisionnés + bloatware OEM
6. **Nettoyage résiduel** — Services, dossiers, clés autorun (Run keys)
7. **Windows Defender** — Réactivation protection temps réel + mise à jour signatures
8. **Marqueur** — Écrit `C:\ProgramData\Genesienne\OEMAVRemoved.txt` + exit 0

### Détection (avec fallback)

| Cas | Résultat |
|---|---|
| Marqueur présent ET aucun AV dans le registre | Exit 0 (détecté) |
| Marqueur absent ET aucun AV (registre, processus, services) | Exit 0 (fallback — crée le marqueur rétroactivement) |
| AV encore dans le registre ou en mémoire | Exit 1 (non détecté) |
| Marqueur présent MAIS AV encore dans le registre | Exit 1 (incohérence — supprime le marqueur) |

> La détection vérifie le **registre** en priorité (pas les fichiers sur disque) car les fichiers McAfee/Norton peuvent rester verrouillés par les drivers kernel jusqu'au reboot.

### Problème Autopilot résolu (v3.2)

Le blocage ESP était causé par des entrées registre McAfee résiduelles après MCPR. La v3.2 corrige cela en :
- Désactivant la self-protection **avant** MCPR (pas après)
- Exécutant MCPR en **double passage** si le 1er échoue
- Nettoyant **toutes** les entrées registre Uninstall McAfee (par DisplayName + Publisher)
- Supprimant les entrées drivers du registre Services (empêche le rechargement ELAM au boot)

## Logs

- `C:\ProgramData\Genesienne\Logs\Remove-OEMAntivirus.log`
- `C:\ProgramData\Genesienne\Logs\mccleanup.txt` (log MCPR)

## McAfeeRemoval.zip

Le fichier `McAfeeRemoval.zip` provient du repo original [bradleyf-2025/KillMcAfee.ps1](https://github.com/bradleyf-2025/KillMcAfee.ps1) (`McAfeeUninstall.zip`). Il contient une version spécifique plus ancienne de MCPR dont le `mccleanup.exe` supporte encore l'exécution silencieuse en CLI.

> **Ne pas télécharger MCPR depuis le site McAfee** — les versions récentes (10.5+) bloquent l'exécution CLI silencieuse et ne suppriment plus McAfee WPS correctement.

Voir le post original : [How I killed McAfee for our Lenovo laptops (r/Intune)](https://www.reddit.com/r/Intune/comments/1iyvtp4/how_i_killed_mcafee_for_our_lenovo_laptops/)

## Regénérer le .intunewin

```powershell
IntuneWinAppUtil.exe -c .\source -s Install-RemoveOEMAV.ps1 -o .\prod -q
```

## Changelog

### v3.2 (Avril 2026)
- **Fix Autopilot ESP** : nettoyage complet registre McAfee Uninstall (DisplayName + Publisher)
- Désactivation self-protection (`mc-sec-unprotector.exe`) **avant** MCPR, pas après
- Recherche dynamique de `mc-sec-unprotector.exe` (plus de chemin hardcodé)
- Double exécution MCPR si 1er passage échoue (exit code != 0)
- `mc-fw-host` ajouté aux paramètres MCPR
- 9 drivers kernel McAfee (ajout `mfeelamk`, `mfeavfk`, `mfehidk`, `mfefirek`, `cfwids`)
- Suppression entrées drivers dans le registre Services (`reg.exe delete`)
- Kill processus McAfee par wildcard + liste étendue
- Services McAfee par wildcard `mc-*`
- Defender : force réactivation + mise à jour signatures
- Norton : suppression forcée complète (processus, services, drivers, registre, fichiers, AppX)
- Détection : mécanisme fallback (registre + processus + services)
- `Uninstall-RemoveOEMAV.ps1` recréé (était corrompu)
- Fusion phases McAfee en une seule phase cohérente

## Crédits

Fork de [bradleyf-2025/KillMcAfee.ps1](https://github.com/bradleyf-2025/KillMcAfee.ps1) 
