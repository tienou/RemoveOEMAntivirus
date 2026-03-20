<#
.SYNOPSIS
    Supprime le marqueur de suppression des AV OEM
.DESCRIPTION
    Win32 App Intune - Script de désinstallation
    Supprime le fichier marqueur pour permettre une ré-exécution
#>

$markerFile = "C:\ProgramData\Genesienne\OEMAVRemoved.txt"
if (Test-Path $markerFile) {
    Remove-Item $markerFile -Force
}
exit 0