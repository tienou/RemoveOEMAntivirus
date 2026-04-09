<#
.SYNOPSIS
    Détecte si les AV OEM ont été supprimés avec succès
.DESCRIPTION
    Win32 App Intune - Script de détection compatible ESP Autopilot
    Version 2.0 - Avec mécanisme de fallback
    
    Logique :
    - Exit 0 = Détecté (l'une des conditions suivantes) :
      a) Marqueur présent ET aucun AV dans le registre
      b) FALLBACK : Aucun AV dans le registre ET aucun processus AV actif
         (même si le marqueur est absent - le script d'install a pu échouer
          à créer le marqueur mais a quand même supprimé les AV)
    - Exit 1 = Non détecté (AV encore présent dans le registre ou en mémoire)
    
    IMPORTANT : On vérifie le REGISTRE en priorité, pas les fichiers sur disque.
    Les fichiers McAfee/Norton peuvent rester verrouillés par le driver kernel
    jusqu'au reboot. Le script d'install désactive les drivers et planifie
    le nettoyage fichiers au reboot.
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
    $avServicePatterns = @(
        # McAfee
        "McAfee*", "mfemms", "mfevtp", "McAPExe", "HomeNetSvc",
        # Norton / Symantec / Gen Digital
        "Norton*", "NortonSvc", "NortonVpn", "nortonAvDumper64", "NortonWscReporter",
        "Norton Antivirus", "Norton Firewall", "Norton Tools",
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

    foreach ($pattern in $avServicePatterns) {
        $services = Get-Service -Name $pattern -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Status -eq 'Running' }
        if ($services) {
            Write-Host "Service AV actif : $($services[0].Name)"
            return $true
        }
    }
    return $false
}

# ============================================================
# DÉTECTION PRINCIPALE
# ============================================================

$avInRegistry = Test-AVInRegistry
$markerExists = Test-Path $markerFile

# --- Cas 1 : Marqueur présent ---
if ($markerExists) {
    if ($avInRegistry) {
        # Marqueur présent mais AV encore dans le registre = incohérence
        # Supprimer le marqueur pour forcer la ré-exécution
        Write-Host "Marqueur présent mais AV encore dans le registre - suppression marqueur"
        Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Host "AV OEM supprimés - marqueur présent, registre propre"
    exit 0
}

# --- Cas 2 : Marqueur absent - Vérifier le fallback ---
if (-not $avInRegistry) {
    # Pas d'AV dans le registre - vérifier aussi les processus et services
    $avProcessActive = Test-AVProcessRunning
    $avServiceActive = Test-AVServiceRunning

    if (-not $avProcessActive -and -not $avServiceActive) {
        # FALLBACK : Aucun AV nulle part - le script d'install a fonctionné
        # même si le marqueur n'a pas été créé
        Write-Host "FALLBACK : Aucun AV détecté (registre, processus, services) - considéré comme supprimé"
        
        # Créer le marqueur rétroactivement pour les prochaines détections
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
