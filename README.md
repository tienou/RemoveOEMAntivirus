# RemoveOEMAntivirus

Script PowerShell pour supprimer silencieusement McAfee et autres antivirus OEM pré-installés par les constructeurs (Lenovo, HP, Dell...).

Conçu pour un déploiement **Intune Win32 App**, compatible **ESP Autopilot** (Required app).

## AV supportés

| Éditeur | Méthode |
|---|---|
| **McAfee** (Personal Security, WPS, LiveSafe) | MCPR mccleanup.exe + suppression forcée drivers/services/registre |
| Norton | Désinstallation silencieuse via registre |
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
├── Detect-RemoveOEMAV.ps1     # Détection Intune (marqueur + registre)
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

1. **McAfee MCPR** — Détection multi-source (registre, processus, fichiers), extraction du ZIP, exécution de `mccleanup.exe`
2. **McAfee WPS** — Bypass driver kernel : `mc-sec-unprotector.exe`, kill processus, arrêt services, désactivation drivers, nettoyage registre, suppression dossiers, shell extensions. Si fichiers verrouillés → tâche planifiée post-reboot
3. **AppX McAfee** — Suppression packages provisionnés et installés
4. **Autres AV (registre)** — Désinstallation silencieuse (QuietUninstallString / MSI / UninstallString)
5. **Autres AV (AppX)** — Suppression packages provisionnés et installés + bloatware
6. **Nettoyage résiduel** — Services, dossiers, clés autorun (Run keys)
7. **Windows Defender** — Réactivation si désactivé par l'AV OEM
8. **Marqueur** — Écrit `C:\ProgramData\Genesienne\OEMAVRemoved.txt` + exit 0

### Détection

- Exit 0 (détecté) = marqueur présent ET aucun AV dans le registre
- Exit 1 (non détecté) = marqueur absent OU AV encore dans le registre

La détection vérifie le **registre** (pas les fichiers sur disque) car les fichiers McAfee peuvent rester verrouillés par le driver kernel jusqu'au reboot.

## Logs

- `C:\ProgramData\Genesienne\Logs\Remove-OEMAntivirus.log`
- `C:\ProgramData\Genesienne\Logs\mccleanup.txt` (log MCPR)

## McAfeeRemoval.zip

Le fichier `McAfeeRemoval.zip` provient du repo original [bradleyf-2025/KillMcAfee.ps1](https://github.com/bradleyf-2025/KillMcAfee.ps1) (`McAfeeUninstall.zip`). Il contient une version spécifique plus ancienne de MCPR qui fonctionne pour supprimer McAfee WPS sur les laptops OEM.

> **Ne pas télécharger MCPR depuis le site McAfee** — les versions récentes ne suppriment plus McAfee WPS correctement.

Voir le post original : [How I killed McAfee for our Lenovo laptops (r/Intune)](https://www.reddit.com/r/Intune/comments/1iyvtp4/how_i_killed_mcafee_for_our_lenovo_laptops/)

## Regénérer le .intunewin

```powershell
IntuneWinAppUtil.exe -c .\source -s Install-RemoveOEMAV.ps1 -o .\prod -q
```

## Crédits

Fork de [bradleyf-2025/KillMcAfee.ps1](https://github.com/bradleyf-2025/KillMcAfee.ps1) — adapté et étendu par **Genesienne Groupe**.
