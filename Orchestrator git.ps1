# =========================================================================
# Script: Orchestrator.ps1 (Pure PowerShell Fileless Execution)
# =========================================================================

$ErrorActionPreference = "Stop"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ==========================================
# 1. AUTO-ELEVASI KE ADMINISTRATOR
# ==========================================
if (-not $isAdmin) {
    Write-Host "[INFO] Meminta akses Administrator..." -ForegroundColor Yellow
    # UBAH URL DI BAWAH INI DENGAN LINK RAW GITHUB KAMU NANTI:
    $RemoteUrl = "https://raw.githubusercontent.com/UsernameKamu/NamaRepo/main/Orchestrator.ps1"
    $RelaunchCmd = "irm $RemoteUrl | iex"
    
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$RelaunchCmd`"" -Verb RunAs
    exit
}

# ==========================================
# 2. DEFINISI FOLDER SMB JARINGAN & TEMP
# ==========================================
# UBAH PATH DI BAWAH INI SESUAI DENGAN LOKASI FOLDER MODULES DI SERVER SMB KANTOR:
$ModulesFolder = "\\192.168.x.x\IT_Share\Scripts\Modules"
$LocalTempDir = "$env:Public\PostInstallTemp"

if (-not (Test-Path $ModulesFolder)) {
    Write-Host "[ERROR] Folder modul jaringan tidak ditemukan: $ModulesFolder" -ForegroundColor Red
    Write-Host "Pastikan PC ini terhubung ke jaringan lokal/LAN." -ForegroundColor Yellow
    Read-Host "Tekan Enter untuk keluar..."
    exit
}

# Bersihkan sisa temp lokal jika ada
if (Test-Path $LocalTempDir) {
    Remove-Item -Path $LocalTempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ==========================================
# 3. LOAD MODUL DINAMIS DARI SMB SERVER
# ==========================================
$ModuleFiles = Get-ChildItem -Path $ModulesFolder -Filter "*.ps1" | Sort-Object Name
$Modules = @()

foreach ($file in $ModuleFiles) {
    try {
        $module = . $file.FullName
        if ($null -ne $module) {
            $module | Add-Member -MemberType NoteProperty -Name "Id" -Value ($Modules.Count + 1) -Force
            $module | Add-Member -MemberType NoteProperty -Name "ConfigParams" -Value $null -Force
            $module | Add-Member -MemberType NoteProperty -Name "FileName" -Value $file.Name -Force
            $Modules += $module
        }
    } catch {}
}

# ==========================================
# 4. MENU UTAMA ORCHESTRATOR
# ==========================================
while ($true) {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "        WINDOWS POST-INSTALL ORCHESTRATOR         " -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    
    if ($Modules.Count -eq 0) {
        Write-Host "  (Tidak ada modul .ps1 di $ModulesFolder)" -ForegroundColor Yellow
    } else {
        foreach ($m in $Modules) { Write-Host "  $($m.Id). $($m.Name)" }
    }
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "`nPilih Mode Jalankan:" -ForegroundColor Yellow
    Write-Host "  1. Install Semua Modul"
    Write-Host "  2. Install Sebagian (Pilih Manual)"
    Write-Host "  3. Keluar`n"
    
    $modeChoice = Read-Host "Masukkan pilihan Anda (1-3)"
    
    if ($modeChoice -eq "3") { exit }
    if ($Modules.Count -eq 0) { continue }
    
    $selectedModules = @()
    if ($modeChoice -eq "1") {
        $selectedModules = $Modules
    } elseif ($modeChoice -eq "2") {
        $selections = Read-Host "Masukkan nomor installer yang diinginkan (contoh: 1,3)"
        $selectedIds = $selections.Split(',') | ForEach-Object { [int]$_.Trim() }
        $selectedModules = $Modules | Where-Object { $selectedIds -contains $_.Id }
    } else { continue }
    
    if ($selectedModules.Count -eq 0) { continue }

    # Konfigurasi parameter
    $configuredModules = @()
    foreach ($m in $selectedModules) {
        $params = if ($m.RequiresConfig) { & $m.Configure } else { & $m.Configure }
        if ($m.RequiresConfig -and $null -eq $params) { continue }
        
        $m.ConfigParams = $params
        $configuredModules += $m
    }

    if ($configuredModules.Count -eq 0) { continue }

    # ==========================================
    # 5. EKSEKUSI INSTALASI
    # ==========================================
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "        MENGEKSEKUSI INSTALLATION TASKS           " -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    
    if (-not (Test-Path $LocalTempDir)) {
        New-Item -ItemType Directory -Path $LocalTempDir -Force | Out-Null
    }

    # PreCopy
    $allCopiesSuccess = $true
    foreach ($m in $configuredModules) {
        if ($null -ne $m.PreCopy) {
            $success = & $m.PreCopy $LocalTempDir
            if (-not $success) {
                Write-Host "[ERROR] PreCopy gagal untuk $($m.Name)" -ForegroundColor Red
                $allCopiesSuccess = $false
                break
            }
        }
    }

    if (-not $allCopiesSuccess) {
        Remove-Item -Path $LocalTempDir -Recurse -Force -ErrorAction SilentlyContinue
        Read-Host "Tekan Enter untuk kembali ke Menu Utama..."
        continue
    }

    # Install
    foreach ($m in $configuredModules) {
        try {
            Write-Host "`n>>> MENGEKSEKUSI: $($m.Name) <<<" -ForegroundColor Green
            & $m.Install $m.ConfigParams $LocalTempDir
        } catch {
            Write-Host "[ERROR] Kegagalan instalasi pada modul: $($m.Name)" -ForegroundColor Red
            Write-Host "Detail: $_" -ForegroundColor Red
        }
    }

    # Bersihkan temp lokal
    if (Test-Path $LocalTempDir) {
        Remove-Item -Path $LocalTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "`n==================================================" -ForegroundColor Green
    Write-Host "          ALL PROCESSES COMPLETED                 " -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Read-Host "Tekan Enter untuk kembali ke menu..."
}