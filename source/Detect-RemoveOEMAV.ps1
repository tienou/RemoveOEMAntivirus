<#
.SYNOPSIS
    Détecte si les AV OEM ont été supprimés avec succès
.DESCRIPTION
    Win32 App Intune - Script de détection compatible ESP Autopilot
    Version 3.0 - Anti-blocage ESP

    Logique (conçue pour NE JAMAIS bloquer l'ESP) :
    - Exit 0 = Détecté (l'une des conditions suivantes) :
      a) Marqueur présent → on fait confiance au script d'install
         (les résidus seront nettoyés par la tâche post-reboot)
      b) FALLBACK : Aucun AV dans le registre ET aucun processus/service AV actif
    - Exit 1 = Non détecté (marqueur absent ET AV encore présent)

    IMPORTANT : Le marqueur est créé à la FIN du script d'install.
    S'il existe, le script s'est exécuté complètement.
    On ne supprime JAMAIS le marqueur depuis la détection car cela
    provoque une boucle de retry infinie pendant l'ESP Autopilot.
    Les drivers kernel peuvent empêcher la suppression totale des
    services/fichiers avant reboot — c'est normal et géré par la
    tâche planifiée post-reboot.
#>

$markerFile = "C:\ProgramData\Genesienne\OEMAVRemoved.txt"

# --- Fonction : Vérifier la présence d'AV dans le registre ---
function Test-AVInRegistry {
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
            return $true
        }
    }
    return $false
}

# --- Fonction : Vérifier la présence de processus AV actifs ---
function Test-AVProcessRunning {
    $avProcessNames = @(
        # McAfee
        "McAPExe", "mcshield", "mfemms", "mfevtps", "ModuleCoreService",
        "PEFService", "McCSPServiceHost", "MMSSHOST", "mfewc",
        # Norton / Symantec / Gen Digital
        "Norton*", "Symantec*", "NortonSvc", "NortonUI", "ccSvcHst", "navw32", "nsWscSvc",
        "NortonSecurity", "NortonLifeLock*", "icarus*",
        # Avast / AVG
        "AvastSvc", "AvastUI", "avgnt", "avgsvc",
        # Kaspersky
        "avp", "avpui",
        # Trend Micro
        "PccNTMon", "TmListen",
        # Bitdefender
        "bdagent", "vsserv", "bdservicehost"
    )

    foreach ($procName in $avProcessNames) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Host "Processus AV actif : $($procs[0].ProcessName)"
            return $true
        }
    }
    return $false
}

# --- Fonction : Vérifier les services AV actifs ---
function Test-AVServiceRunning {
    # Patterns par Name (pas d'espace)
    $avServiceByName = @(
        # McAfee
        "McAfee*", "mfemms", "mfevtp", "McAPExe", "HomeNetSvc", "mc-*",
        # Norton / Symantec / Gen Digital
        "Norton*", "NortonSvc", "NortonVpn", "nortonAvDumper64", "NortonWscReporter",
        "Symantec*", "NortonSecurity",
        # Avast / AVG
        "avast*", "avg*",
        # Kaspersky
        "AVP*", "klnagent",
        # Trend Micro
        "TrendMicro*", "Amsp",
        # Bitdefender
        "VSSERV", "bdredline*"
    )

    foreach ($pattern in $avServiceByName) {
        $services = Get-Service -Name $pattern -ErrorAction SilentlyContinue |
                    Where-Object { $_.Status -eq 'Running' }
        if ($services) {
            Write-Host "Service AV actif : $($services[0].Name)"
            return $true
        }
    }

    # Patterns par DisplayName (noms avec espaces - Norton Gen Digital)
    $avServiceByDisplayName = @("*Norton*", "*McAfee*", "*Symantec*")
    foreach ($pattern in $avServiceByDisplayName) {
        $services = Get-Service -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like $pattern -and $_.Status -eq 'Running' }
        if ($services) {
            Write-Host "Service AV actif : $($services[0].Name) ($($services[0].DisplayName))"
            return $true
        }
    }

    return $false
}

# ============================================================
# DÉTECTION PRINCIPALE
# ============================================================

$markerExists = Test-Path $markerFile

# --- Cas 1 : Marqueur présent = le script d'install s'est exécuté ---
# On fait confiance au marqueur. Ne JAMAIS le supprimer ici.
# Les résidus (services protégés par driver kernel, fichiers verrouillés)
# seront nettoyés par la tâche planifiée post-reboot.
if ($markerExists) {
    Write-Host "Marqueur présent - script d'install exécuté, détection OK"
    exit 0
}

# --- Cas 2 : Marqueur absent - Vérifier si les AV sont déjà absents ---
$avInRegistry = Test-AVInRegistry

if (-not $avInRegistry) {
    $avProcessActive = Test-AVProcessRunning
    $avServiceActive = Test-AVServiceRunning

    if (-not $avProcessActive -and -not $avServiceActive) {
        # FALLBACK : Aucun AV nulle part - considéré comme supprimé
        Write-Host "FALLBACK : Aucun AV détecté (registre, processus, services) - considéré comme supprimé"

        # Créer le marqueur rétroactivement
        $markerDir = Split-Path $markerFile -Parent
        if (!(Test-Path $markerDir)) {
            New-Item -Path $markerDir -ItemType Directory -Force | Out-Null
        }
        "Removed by fallback detection - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $markerFile -Encoding UTF8

        exit 0
    }
    else {
        Write-Host "Marqueur absent - AV encore actif en mémoire malgré registre propre"
        exit 1
    }
}

# --- Cas 3 : Marqueur absent ET AV dans le registre = pas encore traité ---
Write-Host "Marqueur absent - AV encore dans le registre"
exit 1
