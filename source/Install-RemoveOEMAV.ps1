<#
.SYNOPSIS
    Supprime McAfee (via MCPR) et autres AV OEM en mode silencieux
.DESCRIPTION
    Win32 App Intune - Compatible ESP Autopilot (Required app)
    Extrait McAfeeRemoval.zip dans C:\Temp, lance mccleanup.exe
    Si McAfee WPS résiste (driver kernel), désactive les drivers et planifie nettoyage au reboot
    Retourne exit 0 rapidement pour ne pas bloquer l'ESP
.NOTES
    Genesienne Groupe - Version 2.3 - Mars 2026
    
    Structure package .intunewin :
    source\
    ├── McAfeeRemoval.zip     (contenu du $1 extrait de MCPR.exe via 7-Zip, zippé)
    ├── Install-RemoveOEMAV.ps1
    ├── Detect-RemoveOEMAV.ps1
    └── Uninstall-RemoveOEMAV.ps1
    
    Intune Win32 :
    Install  : powershell.exe -ExecutionPolicy Bypass -File Install-RemoveOEMAV.ps1
    Uninstall: powershell.exe -ExecutionPolicy Bypass -File Uninstall-RemoveOEMAV.ps1
    Detection: Custom script → Detect-RemoveOEMAV.ps1 (64-bit, System)
#>

$ErrorActionPreference = "SilentlyContinue"
$scriptDir = $PSScriptRoot

# Chemins
$zipFile     = Join-Path $scriptDir "McAfeeRemoval.zip"
$tempPath    = "C:\Temp\McAfeeRemoval"
$mccleanup   = "$tempPath\mccleanup.exe"
$markerDir   = "C:\ProgramData\Genesienne"
$markerFile  = "$markerDir\OEMAVRemoved.txt"
$LogFile     = "$markerDir\Logs\Remove-OEMAntivirus.log"

# Créer les dossiers
foreach ($d in @($markerDir, (Split-Path $LogFile), "C:\Temp")) {
    if (!(Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-Log "========== Début suppression AV OEM v2.3 =========="
Write-Log "Script directory: $scriptDir"

# ============================================================
# 1. McAfee - Détection + Extraction ZIP + MCPR mccleanup.exe
# ============================================================
Write-Log "--- Phase 1 : McAfee via MCPR ---"

# Détecter si McAfee est présent (registre, processus, fichiers)
$mcafeeDetected = $false
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS") { $mcafeeDetected = $true }
if (Test-Path "HKLM:\SOFTWARE\McAfee") { $mcafeeDetected = $true }
if (Test-Path "C:\Program Files\McAfee") { $mcafeeDetected = $true }
if (Get-Process -Name "mc-fw-host" -ErrorAction SilentlyContinue) { $mcafeeDetected = $true }
if (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*McAfee*" }) { $mcafeeDetected = $true }

if ($mcafeeDetected -and (Test-Path $zipFile)) {
    Write-Log "McAfee détecté - Extraction du ZIP"
    
    if (Test-Path $tempPath) {
        Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    
    try {
        Expand-Archive -Path $zipFile -DestinationPath $tempPath -Force -ErrorAction Stop
        Write-Log "ZIP extrait dans $tempPath"
    } catch {
        Write-Log "Erreur extraction ZIP : $($_.Exception.Message)"
    }
    
    if (Test-Path $mccleanup) {
        Write-Log "mccleanup.exe trouvé - Lancement MCPR"
        
        $mcafeeParams = "-p StopServices,WPS,MFSY,PEF,MXD,CSP,Sustainability,MOCP,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUE -v -s"
        
        Start-Process -FilePath $mccleanup -ArgumentList $mcafeeParams -Wait -NoNewWindow
        Write-Log "MCPR terminé"
        
        # Copier le log MCPR
        if (Test-Path "$tempPath\mccleanup.txt") {
            Copy-Item "$tempPath\mccleanup.txt" "$markerDir\Logs\mccleanup.txt" -Force
        }
        
        Start-Sleep -Seconds 5
    } else {
        Write-Log "mccleanup.exe non trouvé après extraction"
    }
    
} elseif (!$mcafeeDetected) {
    Write-Log "McAfee non détecté - ZIP non extrait"
} else {
    Write-Log "McAfeeRemoval.zip non trouvé dans $scriptDir"
}

# ============================================================
# 2. McAfee WPS - Bypass driver protection (Lenovo)
# ============================================================
Write-Log "--- Phase 2 : McAfee WPS ---"

$mcafeeWpsPresent = (Test-Path "C:\Program Files\McAfee\WPS") -or
    (Get-Process -Name "mc-fw-host" -ErrorAction SilentlyContinue) -or
    (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS")

if ($mcafeeWpsPresent) {
    Write-Log "McAfee WPS détecté - Suppression forcée"
    
    # Extraire le zip si pas encore fait (phase 1 peut l'avoir nettoyé)
    if (!(Test-Path $tempPath) -and (Test-Path $zipFile)) {
        Expand-Archive -Path $zipFile -DestinationPath $tempPath -Force -ErrorAction SilentlyContinue
    }
    
    # a) mc-sec-unprotector.exe
    $unprotector = "$tempPath\WPS\drivers\22.6\x64\mc-sec-unprotector.exe"
    if (Test-Path $unprotector) {
        Write-Log "Lancement mc-sec-unprotector.exe"
        Start-Process $unprotector -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    
    # b) Tuer les processus en premier (libérer les verrous fichiers)
    foreach ($procName in @("mc-fw-host", "mc-neo-host", "mc-update", "McUICnt", "mc-launch", "mc-web-view", "mc-dad", "mc-vpn", "mc-sustainability", "mc-extn-browserhost", "mc-oem-subjob", "mc-sync-agent")) {
        Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3

    # c) Arrêter et supprimer services McAfee (avant suppression dossiers)
    Get-Service | Where-Object { $_.DisplayName -like "*McAfee*" } | ForEach-Object {
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        sc.exe delete $_.Name 2>&1 | Out-Null
        Write-Log "Service $($_.Name) supprimé"
    }
    foreach ($d in @("mfesec","mfeelam","mfewfpk","mfeavfk","mfefirek","cfwids")) {
        sc.exe delete $d 2>&1 | Out-Null
    }

    # d) Désactiver les drivers kernel
    foreach ($driver in @("mfesec", "mfeelam", "McAfeeWPS", "mfewfpk")) {
        $result = sc.exe query $driver 2>&1
        if ($result -notlike "*FAILED*") {
            sc.exe config $driver start= disabled 2>&1 | Out-Null
            Write-Log "Driver $driver désactivé"
        }
    }

    # e) Supprimer les clés registre McAfee
    Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SOFTWARE\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SOFTWARE\WOW6432Node\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Clés registre McAfee supprimées"

    # f) Suppression dossiers + raccourci menu démarrer
    foreach ($folder in @("C:\Program Files\McAfee", "C:\Program Files (x86)\McAfee", "C:\ProgramData\McAfee", "C:\Program Files\Common Files\McAfee", "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\McAfee")) {
        if (Test-Path $folder) {
            cmd /c "rd /s /q `"$folder`"" 2>$null
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # g) Supprimer tâches planifiées McAfee
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*McAfee*" } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    # h) Shell extensions (menu contextuel Analyser/Broyer)
    Write-Log "Nettoyage shell extensions"
    foreach ($root in @("HKLM:\SOFTWARE\Classes", "HKLM:\SOFTWARE\WOW6432Node\Classes")) {
        foreach ($sub in @("*", "Directory", "Drive", "Folder", "Directory\Background")) {
            Get-ChildItem "$root\$sub\shellex\ContextMenuHandlers" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*McAfee*" -or $_.Name -like "*Shredder*" } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($clsid in @("{4B3803EA-5230-4DC3-A7FC-33638F3D3542}", "{B748F331-FF92-4BA8-B71E-53C15EBB26A8}")) {
        Remove-Item "HKLM:\SOFTWARE\Classes\CLSID\$clsid" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID\$clsid" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # i) Si fichiers verrouillés, planifier nettoyage au reboot
    if (Test-Path "C:\Program Files\McAfee") {
        Write-Log "Fichiers verrouillés - Tâche post-reboot"
        
        $cleanupScript = "$markerDir\CleanMcAfee.ps1"
        @'
Start-Sleep -Seconds 15
Get-Service | Where-Object { $_.DisplayName -like "*McAfee*" } | ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    sc.exe delete $_.Name 2>&1 | Out-Null
}
foreach ($d in @("mfesec","mfeelam","mfewfpk","mfeavfk","mfefirek","cfwids")) {
    sc.exe delete $d 2>&1 | Out-Null
}
Remove-Item "C:\Program Files\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files (x86)\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\Common Files\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
foreach ($root in @("HKLM:\SOFTWARE\Classes", "HKLM:\SOFTWARE\WOW6432Node\Classes")) {
    foreach ($sub in @("*", "Directory", "Drive", "Folder")) {
        Get-ChildItem "$root\$sub\shellex\ContextMenuHandlers" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*McAfee*" -or $_.Name -like "*Shredder*" } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Get-ScheduledTask | Where-Object { $_.TaskName -like "*McAfee*" } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Genesienne-CleanMcAfee" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
'@ | Out-File $cleanupScript -Encoding UTF8
        
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$cleanupScript`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "Genesienne-CleanMcAfee" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        
        Write-Log "Tâche Genesienne-CleanMcAfee créée"
    } else {
        Write-Log "Dossiers McAfee supprimés"
    }
} else {
    Write-Log "McAfee WPS non détecté"
}

# ============================================================
# 3. AppX McAfee
# ============================================================
Write-Log "--- Phase 3 : AppX McAfee ---"

Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*McAfee*" } | ForEach-Object {
    Write-Log "Suppression provisionné : $($_.DisplayName)"
    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
}
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*McAfee*" } | ForEach-Object {
    Write-Log "Suppression AppX : $($_.Name)"
    Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
}

# ============================================================
# 4. Autres AV - Registre
# ============================================================
Write-Log "--- Phase 4 : Autres AV (registre) ---"

$avPatterns = @("*Norton*", "*Avast*", "*AVG Antivirus*", "*Kaspersky*", "*Trend Micro*", "*Bitdefender*")

foreach ($regPath in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
    Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        foreach ($pattern in $avPatterns) {
            if ($props.DisplayName -like $pattern -and ($props.UninstallString -or $props.QuietUninstallString)) {
                Write-Log "Désinstallation : $($props.DisplayName)"
                if ($props.QuietUninstallString) {
                    Start-Process cmd.exe -ArgumentList "/c `"$($props.QuietUninstallString)`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                }
                elseif ($props.UninstallString -like "MsiExec*") {
                    $guid = [regex]::Match($props.UninstallString, '\{[A-Fa-f0-9-]+\}').Value
                    if ($guid) { Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -Wait -NoNewWindow }
                }
                else {
                    Start-Process cmd.exe -ArgumentList "/c `"$($props.UninstallString)`" /quiet /silent /norestart" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

# ============================================================
# 5. Autres AV - AppX
# ============================================================
Write-Log "--- Phase 5 : Autres AV AppX ---"

$allPatterns = @("*Norton*", "*Avast*", "*AVG Antivirus*", "*Kaspersky*", "*Trend Micro*", "*Bitdefender*", "*WildTangent*", "*ExpressVPN*", "*Dropbox*Trial*")

$provApps = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
foreach ($pattern in $allPatterns) {
    $provApps | Where-Object { $_.DisplayName -like $pattern } | ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
    }
}
$allAppx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
foreach ($pattern in $allPatterns) {
    $allAppx | Where-Object { $_.Name -like $pattern } | ForEach-Object {
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
}

# ============================================================
# 6. Nettoyage résiduel autres AV
# ============================================================
Write-Log "--- Phase 6 : Nettoyage ---"

$allServices = Get-Service -ErrorAction SilentlyContinue
foreach ($pattern in $avPatterns) {
    $allServices | Where-Object { $_.DisplayName -like $pattern } | ForEach-Object {
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        sc.exe delete $_.Name 2>&1 | Out-Null
    }
}

foreach ($folder in @(
    "$env:ProgramFiles\Norton Security", "${env:ProgramFiles(x86)}\Norton Security",
    "$env:ProgramData\Norton", "$env:ProgramFiles\NortonInstaller",
    "$env:ProgramFiles\Avast Software", "${env:ProgramFiles(x86)}\Avast Software",
    "$env:ProgramFiles\AVG", "${env:ProgramFiles(x86)}\AVG",
    "$env:ProgramFiles\Kaspersky Lab", "${env:ProgramFiles(x86)}\Kaspersky Lab",
    "$env:ProgramFiles\Trend Micro", "${env:ProgramFiles(x86)}\Trend Micro",
    "$env:ProgramFiles\Bitdefender", "${env:ProgramFiles(x86)}\Bitdefender",
    "$env:ProgramData\Bitdefender"
)) {
    if (Test-Path $folder) { Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue }
}

foreach ($runKey in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")) {
    $entries = Get-ItemProperty $runKey -ErrorAction SilentlyContinue
    if ($entries) {
        $entries.PSObject.Properties | Where-Object {
            $_.Value -like "*McAfee*" -or $_.Value -like "*Norton*" -or $_.Value -like "*Avast*" -or $_.Value -like "*AVG*" -or $_.Value -like "*Kaspersky*" -or $_.Value -like "*Trend Micro*" -or $_.Value -like "*Bitdefender*"
        } | ForEach-Object {
            Remove-ItemProperty -Path $runKey -Name $_.Name -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# 7. Defender
# ============================================================
Write-Log "--- Phase 7 : Defender ---"
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($defender -and !$defender.AntivirusEnabled) {
    Set-MpPreference -DisableRealtimeMonitoring $false
    Write-Log "Defender réactivé"
} else {
    Write-Log "Defender OK"
}

# ============================================================
# 8. Nettoyage temp + Marqueur
# ============================================================
Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue

"AV OEM supprimés le $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - v2.3" | Out-File $markerFile -Encoding UTF8

Write-Log "========== Suppression terminée v2.3 =========="
exit 0