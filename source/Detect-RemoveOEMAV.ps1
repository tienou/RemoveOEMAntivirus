<#
.SYNOPSIS
    Détecte si les AV OEM ont été supprimés avec succès
.DESCRIPTION
    Win32 App Intune - Script de détection compatible ESP Autopilot
    
    Logique :
    - Exit 0 = Détecté (marqueur présent ET aucun AV dans le registre)
    - Exit 1 = Non détecté (marqueur absent OU AV encore dans le registre)
    
    IMPORTANT : On vérifie le REGISTRE, pas les fichiers sur disque.
    Les fichiers McAfee peuvent rester verrouillés par le driver kernel
    jusqu'au reboot. Le script d'install désactive les drivers et planifie
    le nettoyage fichiers au reboot. La clé registre McAfee.WPS est
    supprimée immédiatement, donc la détection passe pendant l'ESP.
#>

$markerFile = "C:\ProgramData\Genesienne\OEMAVRemoved.txt"

# 1. Vérifier le marqueur
if (!(Test-Path $markerFile)) {
    Write-Host "Marqueur absent"
    exit 1
}

# 2. Vérifier le registre (pas les fichiers - ils peuvent être verrouillés jusqu'au reboot)
$avFound = $false

$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$installed = Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue
$avPatterns = @("*McAfee*", "*Norton*", "*Avast*", "*AVG Antivirus*", "*Kaspersky*", "*Trend Micro*", "*Bitdefender*")

foreach ($pattern in $avPatterns) {
    $match = $installed | Where-Object { $_.DisplayName -like $pattern }
    if ($match) {
        Write-Host "AV trouvé dans registre : $($match.DisplayName)"
        $avFound = $true
    }
}

if ($avFound) {
    # AV encore dans le registre = le script d'install n'a pas réussi à nettoyer le registre
    # Supprimer le marqueur pour forcer la ré-exécution
    Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "AV OEM supprimés - registre propre"
exit 0