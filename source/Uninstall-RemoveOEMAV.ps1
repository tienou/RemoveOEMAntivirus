<#
.SYNOPSIS
    Annule le marqueur de suppression des AV OEM
.DESCRIPTION
    Win32 App Intune - Script de désinstallation
    Supprime le marqueur, les tâches planifiées et les scripts de nettoyage
    créés par Install-RemoveOEMAV.ps1

    Après exécution, le script de détection retournera exit 1 (non détecté),
    ce qui permettra à Intune de relancer l'installation si nécessaire.
.NOTES
    Genesienne Groupe - Version 3.2 - Avril 2026
#>

$ErrorActionPreference = "SilentlyContinue"

$markerDir  = "C:\ProgramData\Genesienne"
$markerFile = "$markerDir\OEMAVRemoved.txt"
$LogFile    = "$markerDir\Logs\Remove-OEMAntivirus.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-Log "========== Début désinstallation (rollback marqueur) v3.2 =========="

# 1. Supprimer le marqueur
if (Test-Path $markerFile) {
    Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
    Write-Log "Marqueur supprimé : $markerFile"
} else {
    Write-Log "Marqueur déjà absent"
}

# 2. Supprimer les tâches planifiées de nettoyage post-reboot
foreach ($taskName in @("Genesienne-CleanMcAfee", "Genesienne-CleanNorton")) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Tâche planifiée supprimée : $taskName"
    }
}

# 3. Supprimer les scripts de nettoyage post-reboot
foreach ($script in @("$markerDir\CleanMcAfee.ps1", "$markerDir\CleanNorton.ps1")) {
    if (Test-Path $script) {
        Remove-Item $script -Force -ErrorAction SilentlyContinue
        Write-Log "Script nettoyage supprimé : $script"
    }
}

Write-Log "========== Désinstallation terminée v3.2 =========="
exit 0
