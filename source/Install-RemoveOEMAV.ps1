<#
.SYNOPSIS
    Supprime McAfee, Norton et autres AV OEM en mode silencieux
.DESCRIPTION
    Win32 App Intune - Compatible ESP Autopilot (Required app)
    - McAfee : Extrait McAfeeRemoval.zip, lance mccleanup.exe, bypass WPS
    - Norton : Suppression forcée (kill processus, services, drivers, registre, fichiers)
    - Autres AV : Désinstallation via registre UninstallString
    Retourne exit 0 rapidement pour ne pas bloquer l'ESP
.NOTES
    Genesienne Groupe - Version 3.2 - Avril 2026
    
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

Write-Log "========== Début suppression AV OEM v3.2 =========="
Write-Log "Script directory: $scriptDir"

# ============================================================
# 1. McAfee - Détection + Extraction ZIP + Désactivation self-protection + MCPR
# ============================================================
Write-Log "--- Phase 1 : McAfee ---"

# Détecter si McAfee est présent (registre, processus, fichiers)
$mcafeeDetected = $false
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS") { $mcafeeDetected = $true }
if (Test-Path "HKLM:\SOFTWARE\McAfee") { $mcafeeDetected = $true }
if (Test-Path "C:\Program Files\McAfee") { $mcafeeDetected = $true }
if (Get-Process -Name "mc-fw-host" -ErrorAction SilentlyContinue) { $mcafeeDetected = $true }
if (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*McAfee*" }) { $mcafeeDetected = $true }

if ($mcafeeDetected) {
    Write-Log "McAfee détecté"

    # --- Extraction ZIP ---
    if (Test-Path $zipFile) {
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
    } else {
        Write-Log "McAfeeRemoval.zip non trouvé dans $scriptDir"
    }

    # --- a) Désactiver la self-protection AVANT tout (mc-sec-unprotector.exe) ---
    # Recherche dynamique (le chemin change selon la version MCPR)
    $unprotector = Get-ChildItem "$tempPath" -Recurse -Filter "mc-sec-unprotector.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($unprotector) {
        Write-Log "Lancement mc-sec-unprotector.exe ($($unprotector.FullName))"
        $proc = Start-Process $unprotector.FullName -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
        if ($proc -and !$proc.WaitForExit(60000)) {
            Write-Log "mc-sec-unprotector timeout 60s - Kill"
            $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    } else {
        Write-Log "mc-sec-unprotector.exe non trouvé"
    }

    # --- b) Tuer les processus McAfee (liste + wildcard) ---
    foreach ($procName in @("mc-fw-host", "mc-neo-host", "mc-update", "McUICnt", "mc-launch", "mc-web-view", "mc-dad", "mc-vpn", "mc-sustainability", "mc-extn-browserhost", "mc-oem-subjob", "mc-sync-agent", "McAPExe", "mcshield", "mfemms", "mfevtps", "ModuleCoreService", "PEFService", "McCSPServiceHost", "MMSSHOST", "mfewc", "mc-wps-secdashboardservice")) {
        Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
    }
    Get-Process | Where-Object { $_.ProcessName -like "*McAfee*" -or $_.ProcessName -like "mc-*" -or $_.ProcessName -like "mc*shield*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # --- c) Arrêter et supprimer les services McAfee ---
    Get-Service | Where-Object { $_.DisplayName -like "*McAfee*" -or $_.Name -like "mc-*" } | ForEach-Object {
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        sc.exe config $_.Name start= disabled 2>&1 | Out-Null
        sc.exe delete $_.Name 2>&1 | Out-Null
        Write-Log "Service $($_.Name) supprimé"
    }
    foreach ($svc in @("mfemms", "mfevtp", "HomeNetSvc", "McAPExe", "mc-fw-host", "mc-wps-update", "mc-wps-secdashboardservice")) {
        sc.exe stop $svc 2>&1 | Out-Null
        sc.exe config $svc start= disabled 2>&1 | Out-Null
        sc.exe delete $svc 2>&1 | Out-Null
    }

    # --- d) Désactiver ET supprimer les drivers kernel McAfee ---
    foreach ($driver in @("mfesec", "mfeelam", "mfeelamk", "McAfeeWPS", "mfewfpk", "mfeavfk", "mfehidk", "mfefirek", "cfwids")) {
        sc.exe config $driver start= disabled 2>&1 | Out-Null
        # Supprimer l'entrée dans le registre Services pour empêcher le chargement au boot
        reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\$driver" /f 2>&1 | Out-Null
        Write-Log "Driver $driver désactivé et supprimé du registre"
    }

    # --- e) MCPR mccleanup.exe (après désactivation self-protection) ---
    if (Test-Path $mccleanup) {
        Write-Log "mccleanup.exe trouvé - Lancement MCPR"

        $mcafeeParams = "-p StopServices,WPS,MFSY,PEF,MXD,CSP,Sustainability,MOCP,mc-fw-host,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUE -v -s"

        $proc = Start-Process -FilePath $mccleanup -ArgumentList $mcafeeParams -NoNewWindow -PassThru
        if (!$proc.WaitForExit(300000)) {
            Write-Log "MCPR timeout 5 min - Kill du processus"
            $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        $exitCode1 = $proc.ExitCode
        Write-Log "MCPR 1er passage terminé (ExitCode: $exitCode1)"

        # 2e passage si le 1er a échoué (exit code != 0 = suppression incomplète)
        if ($exitCode1 -ne 0) {
            Write-Log "MCPR 2e passage (1er passage non-zero)"
            Start-Sleep -Seconds 5
            $proc2 = Start-Process -FilePath $mccleanup -ArgumentList $mcafeeParams -NoNewWindow -PassThru
            if (!$proc2.WaitForExit(300000)) {
                $proc2 | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            Write-Log "MCPR 2e passage terminé (ExitCode: $($proc2.ExitCode))"
        }

        # Copier le log MCPR
        if (Test-Path "$tempPath\mccleanup.txt") {
            Copy-Item "$tempPath\mccleanup.txt" "$markerDir\Logs\mccleanup.txt" -Force
        }

        Start-Sleep -Seconds 5
    } else {
        Write-Log "mccleanup.exe non trouvé"
    }

    # f) Registre McAfee - Nettoyage complet Uninstall + produit
    # Supprimer TOUTES les entrées McAfee du registre Uninstall (pas seulement WPS)
    foreach ($regPath in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
        Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -like "*McAfee*" -or $props.Publisher -like "*McAfee*") {
                Write-Log "Suppression clé registre : $($props.DisplayName) ($($_.PSChildName))"
                Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Remove-Item "HKLM:\SOFTWARE\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SOFTWARE\WOW6432Node\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Clés registre McAfee supprimées"

    # g) Dossiers McAfee
    foreach ($folder in @("C:\Program Files\McAfee", "C:\Program Files (x86)\McAfee", "C:\ProgramData\McAfee", "C:\Program Files\Common Files\McAfee", "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\McAfee")) {
        if (Test-Path $folder) {
            cmd /c "rd /s /q `"$folder`"" 2>$null
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # h) Tâches planifiées McAfee
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*McAfee*" } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    # i) Shell extensions McAfee
    Write-Log "Nettoyage shell extensions McAfee"
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
    
    # j) Tâche post-reboot si fichiers verrouillés
    if (Test-Path "C:\Program Files\McAfee") {
        Write-Log "Fichiers McAfee verrouillés - Tâche post-reboot"
        
        $cleanupScript = "$markerDir\CleanMcAfee.ps1"
        @'
Start-Sleep -Seconds 15
Get-Service | Where-Object { $_.DisplayName -like "*McAfee*" -or $_.Name -like "mc-*" } | ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    sc.exe delete $_.Name 2>&1 | Out-Null
}
foreach ($d in @("mfesec","mfeelam","mfeelamk","mfewfpk","mfeavfk","mfehidk","mfefirek","cfwids")) {
    sc.exe delete $d 2>&1 | Out-Null
    reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\$d" /f 2>&1 | Out-Null
}
Get-Process | Where-Object { $_.ProcessName -like "*McAfee*" -or $_.ProcessName -like "mc-*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files (x86)\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\Common Files\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
foreach ($regPath in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
    Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p.DisplayName -like "*McAfee*" -or $p.Publisher -like "*McAfee*") {
            Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
Remove-Item "HKLM:\SOFTWARE\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "HKLM:\SOFTWARE\WOW6432Node\McAfee" -Recurse -Force -ErrorAction SilentlyContinue
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
    Write-Log "McAfee non détecté"
}

# ============================================================
# 2. Norton - Suppression forcée (OEM ne supporte pas /quiet)
# ============================================================
Write-Log "--- Phase 2 : Norton ---"

$nortonDetected = $false
$nortonProducts = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Norton*" }
if ($nortonProducts) { $nortonDetected = $true }
if (Test-Path "HKLM:\SOFTWARE\Norton") { $nortonDetected = $true }
if (Test-Path "HKLM:\SOFTWARE\Symantec") { $nortonDetected = $true }
if (Test-Path "C:\Program Files\Norton Security") { $nortonDetected = $true }
if (Test-Path "C:\Program Files\NortonInstaller") { $nortonDetected = $true }
if (Test-Path "C:\Program Files (x86)\Norton Security") { $nortonDetected = $true }
if (Get-Process -Name "Norton*","NS*","nst*","ccSvcHst","navw32" -ErrorAction SilentlyContinue) { $nortonDetected = $true }

if ($nortonDetected) {
    Write-Log "Norton détecté - Suppression forcée"
    
    # a) Tuer tous les processus Norton/Symantec
    Write-Log "Kill processus Norton"
    $nortonProcs = @("NortonSecurity", "Norton", "NortonLifeLock", "NS", "NST", "nst", "navw32", 
                     "ccSvcHst", "ccApp", "ccEvtMgr", "ccSetMgr", "ccProxy", "ccPwdSvc",
                     "Norton360", "NortonOnlineDashboard", "NortonBrowser", "NortonSample",
                     "NortonCrashRecovery", "NortonAutoFix", "NortonPrivacy",
                     "SymCorpUI", "SymSilentInstall", "nsWscSvc", "SymEFA")
    foreach ($procName in $nortonProcs) {
        Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # Aussi tuer par wildcard
    Get-Process | Where-Object { $_.ProcessName -like "*Norton*" -or $_.ProcessName -like "*Symantec*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    
    # b) Arrêter et supprimer les services Norton/Symantec
    Write-Log "Suppression services Norton"
    Get-Service | Where-Object { $_.DisplayName -like "*Norton*" -or $_.DisplayName -like "*Symantec*" -or $_.Name -like "*Norton*" -or $_.Name -like "*NST*" -or $_.Name -like "*N360*" } | ForEach-Object {
        Write-Log "Arrêt service : $($_.Name) ($($_.DisplayName))"
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        sc.exe config $_.Name start= disabled 2>&1 | Out-Null
        sc.exe delete $_.Name 2>&1 | Out-Null
    }
    # Services connus Norton
    foreach ($svc in @("Norton Security", "Norton AntiVirus", "Norton 360", "NortonLifeLock Update",
                       "nsWscSvc", "N360", "NIS", "NAV", "ccSetMgr", "ccEvtMgr", "ccProxy",
                       "ccPwdSvc", "ccSvcHst", "SymEFA", "SymEvent", "SRTSP", "SRTSPx")) {
        sc.exe stop $svc 2>&1 | Out-Null
        sc.exe config $svc start= disabled 2>&1 | Out-Null
        sc.exe delete $svc 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 3
    
    # c) Désactiver les drivers kernel Norton/Symantec
    Write-Log "Désactivation drivers Norton"
    foreach ($driver in @("SymEFA", "SymEvent", "SymIRON", "SymNetS", "SymDS", "SymELAM",
                          "SRTSP", "SRTSPx", "SRTSPX", "ccSet64", "ccSet",
                          "BHDrvx64", "BHDrvx86", "IDSvia64", "IDSvia86",
                          "eeCtrl64", "eeCtrl", "EraserUtilRebootDrv",
                          "Norton360", "N360")) {
        $result = sc.exe query $driver 2>&1
        if ($result -notlike "*FAILED*") {
            sc.exe config $driver start= disabled 2>&1 | Out-Null
            Write-Log "Driver $driver désactivé"
        }
    }
    
    # d) Supprimer les clés registre Norton (Uninstall + produit)
    Write-Log "Nettoyage registre Norton"
    # Clés Uninstall
    foreach ($regPath in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
        Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -like "*Norton*") {
                Write-Log "Suppression clé registre : $($props.DisplayName)"
                Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    # Clés produit Norton/Symantec
    foreach ($key in @(
        "HKLM:\SOFTWARE\Norton",
        "HKLM:\SOFTWARE\Symantec",
        "HKLM:\SOFTWARE\WOW6432Node\Norton",
        "HKLM:\SOFTWARE\WOW6432Node\Symantec",
        "HKLM:\SOFTWARE\NortonInstaller",
        "HKLM:\SOFTWARE\WOW6432Node\NortonInstaller"
    )) {
        if (Test-Path $key) {
            Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Clé registre supprimée : $key"
        }
    }
    
    # e) Entrées Run au démarrage
    foreach ($runKey in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")) {
        $entries = Get-ItemProperty $runKey -ErrorAction SilentlyContinue
        if ($entries) {
            $entries.PSObject.Properties | Where-Object {
                $_.Value -like "*Norton*" -or $_.Value -like "*Symantec*"
            } | ForEach-Object {
                Remove-ItemProperty -Path $runKey -Name $_.Name -ErrorAction SilentlyContinue
                Write-Log "Entrée Run supprimée : $($_.Name)"
            }
        }
    }
    
    # f) Suppression des dossiers Norton
    Write-Log "Suppression dossiers Norton"
    foreach ($folder in @(
        "C:\Program Files\Norton Security",
        "C:\Program Files (x86)\Norton Security",
        "C:\Program Files\Norton 360",
        "C:\Program Files (x86)\Norton 360",
        "C:\Program Files\NortonInstaller",
        "C:\Program Files (x86)\NortonInstaller",
        "C:\ProgramData\Norton",
        "C:\ProgramData\NortonInstaller",
        "C:\ProgramData\Symantec",
        "C:\Program Files\Common Files\Symantec Shared",
        "C:\Program Files (x86)\Common Files\Symantec Shared",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Norton Security",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Norton 360"
    )) {
        if (Test-Path $folder) {
            cmd /c "rd /s /q `"$folder`"" 2>$null
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Dossier supprimé : $folder"
        }
    }
    
    # g) AppX Norton
    Write-Log "Suppression AppX Norton"
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*Norton*" -or $_.DisplayName -like "*Symantec*" } | ForEach-Object {
        Write-Log "Suppression provisionné : $($_.DisplayName)"
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
    }
    Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*Norton*" -or $_.Name -like "*Symantec*" } | ForEach-Object {
        Write-Log "Suppression AppX : $($_.Name)"
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    
    # h) Tâches planifiées Norton
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*Norton*" -or $_.TaskName -like "*Symantec*" } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Tâche planifiée supprimée : $($_.TaskName)"
    }
    
    # i) Shell extensions Norton
    Write-Log "Nettoyage shell extensions Norton"
    foreach ($root in @("HKLM:\SOFTWARE\Classes", "HKLM:\SOFTWARE\WOW6432Node\Classes")) {
        foreach ($sub in @("*", "Directory", "Drive", "Folder", "Directory\Background")) {
            Get-ChildItem "$root\$sub\shellex\ContextMenuHandlers" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*Norton*" -or $_.Name -like "*Symantec*" } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # j) Tâche post-reboot si fichiers Norton verrouillés
    $nortonFoldersExist = (Test-Path "C:\Program Files\Norton Security") -or (Test-Path "C:\Program Files\Norton 360") -or (Test-Path "C:\Program Files\NortonInstaller")
    if ($nortonFoldersExist) {
        Write-Log "Fichiers Norton verrouillés - Tâche post-reboot"
        
        $cleanupScript = "$markerDir\CleanNorton.ps1"
        @'
Start-Sleep -Seconds 15
Get-Service | Where-Object { $_.DisplayName -like "*Norton*" -or $_.DisplayName -like "*Symantec*" } | ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    sc.exe delete $_.Name 2>&1 | Out-Null
}
foreach ($svc in @("ccSetMgr","ccEvtMgr","ccProxy","ccSvcHst","SymEFA","SymEvent","SRTSP","SRTSPx","nsWscSvc")) {
    sc.exe delete $svc 2>&1 | Out-Null
}
foreach ($driver in @("SymEFA","SymEvent","SymIRON","SymNetS","SymDS","SymELAM","SRTSP","SRTSPx","BHDrvx64","IDSvia64","eeCtrl64","EraserUtilRebootDrv")) {
    sc.exe config $driver start= disabled 2>&1 | Out-Null
    sc.exe delete $driver 2>&1 | Out-Null
}
foreach ($f in @("C:\Program Files\Norton Security","C:\Program Files (x86)\Norton Security","C:\Program Files\Norton 360","C:\Program Files (x86)\Norton 360","C:\Program Files\NortonInstaller","C:\Program Files (x86)\NortonInstaller","C:\ProgramData\Norton","C:\ProgramData\NortonInstaller","C:\ProgramData\Symantec","C:\Program Files\Common Files\Symantec Shared","C:\Program Files (x86)\Common Files\Symantec Shared")) {
    if (Test-Path $f) { cmd /c "rd /s /q `"$f`"" 2>$null; Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
}
Get-ScheduledTask | Where-Object { $_.TaskName -like "*Norton*" -or $_.TaskName -like "*Symantec*" } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Genesienne-CleanNorton" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
'@ | Out-File $cleanupScript -Encoding UTF8
        
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$cleanupScript`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "Genesienne-CleanNorton" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        
        Write-Log "Tâche Genesienne-CleanNorton créée"
    } else {
        Write-Log "Dossiers Norton supprimés"
    }
    
    Write-Log "Norton supprimé"
} else {
    Write-Log "Norton non détecté"
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

$avPatterns = @("*Avast*", "*AVG Antivirus*", "*Kaspersky*", "*Trend Micro*", "*Bitdefender*")

foreach ($regPath in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
    Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        foreach ($pattern in $avPatterns) {
            if ($props.DisplayName -like $pattern -and ($props.UninstallString -or $props.QuietUninstallString)) {
                Write-Log "Désinstallation : $($props.DisplayName)"
                $avTimeout = 120000  # 2 min par AV
                if ($props.QuietUninstallString) {
                    $proc = Start-Process cmd.exe -ArgumentList "/c `"$($props.QuietUninstallString)`"" -NoNewWindow -PassThru -ErrorAction SilentlyContinue
                }
                elseif ($props.UninstallString -like "MsiExec*") {
                    $guid = [regex]::Match($props.UninstallString, '\{[A-Fa-f0-9-]+\}').Value
                    if ($guid) { $proc = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -NoNewWindow -PassThru }
                }
                else {
                    $proc = Start-Process cmd.exe -ArgumentList "/c `"$($props.UninstallString)`" /quiet /silent /norestart" -NoNewWindow -PassThru -ErrorAction SilentlyContinue
                }
                if ($proc -and !$proc.WaitForExit($avTimeout)) {
                    Write-Log "Timeout désinstallation $($props.DisplayName) - Kill"
                    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

# ============================================================
# 5. Autres AV - AppX
# ============================================================
Write-Log "--- Phase 5 : Autres AV AppX ---"

$allPatterns = @("*Avast*", "*AVG Antivirus*", "*Kaspersky*", "*Trend Micro*", "*Bitdefender*", "*WildTangent*", "*ExpressVPN*", "*Dropbox*Trial*")

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
try {
    # Forcer la réactivation de la protection temps réel
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    # Déclencher une mise à jour des signatures
    Start-MpWDOScan -ScanType QuickScan -ErrorAction SilentlyContinue | Out-Null
    Update-MpSignature -ErrorAction SilentlyContinue
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($defender) {
        Write-Log "Defender : RealTimeProtection=$($defender.RealTimeProtectionEnabled), AntivirusEnabled=$($defender.AntivirusEnabled)"
    } else {
        Write-Log "Defender : impossible de lire le statut (sera actif après reboot)"
    }
} catch {
    Write-Log "Defender : erreur réactivation - $($_.Exception.Message)"
}

# ============================================================
# 8. Nettoyage temp + Marqueur
# ============================================================
Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue

"AV OEM supprimés le $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - v3.2" | Out-File $markerFile -Encoding UTF8

Write-Log "========== Suppression terminée v3.2 =========="
exit 0
