# =========================================================================
# Script: Orchestrator.ps1 (Pure PowerShell Fileless Execution)
# Deskripsi: Engine Utama Orchestrator yang dimuat dari Jaringan/Github
# =========================================================================

$ErrorActionPreference = "Stop"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$LocalTempDir = "$env:Public\KyoceraDriver"
$ConfigFile = Join-Path $LocalTempDir "config.json"

# UBAH URL DI BAWAH INI SESUAI DOMAIN CLOUDFLARE/GITHUB RAW ANDA:
$RemoteUrl = "https://j4deploy.jenaela.my.id"

# ==========================================
# SESI ELEVATED ADMINISTRATOR (EKSEKUSI INSTALASI LOKAL)
# ==========================================
if ($isAdmin) {
    if (Test-Path $ConfigFile) {
        $ConfigData = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        $LocalModulesFolder = Join-Path $LocalTempDir "modules"
        
        # Load modul secara lokal di memori (bypasses execution policy)
        $ModuleFiles = Get-ChildItem -Path $LocalModulesFolder -Filter "*.ps1" | Sort-Object Name
        $Modules = @()
        foreach ($file in $ModuleFiles) {
            try {
                $moduleContent = Get-Content $file.FullName -Raw
                $module = iex $moduleContent
                if ($null -ne $module) {
                    $module | Add-Member -MemberType NoteProperty -Name "ConfigParams" -Value $null -Force
                    $module | Add-Member -MemberType NoteProperty -Name "FileName" -Value $file.Name -Force
                    $Modules += $module
                }
            } catch {
                Write-Host "[WARNING] Gagal memuat modul lokal $($file.Name):" -ForegroundColor Yellow
                Write-Host "Detail: $_" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
        
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "      EXECUTING INSTALLATION TASKS         " -ForegroundColor Cyan
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($moduleData in $ConfigData) {
            $matchingModule = $Modules | Where-Object { $_.FileName -eq $moduleData.FileName }
            if ($null -ne $matchingModule) {
                try {
                    Write-Host ">>> MENGEKSEKUSI: $($matchingModule.Name) <<<" -ForegroundColor Green
                    # Jalankan block script Install milik modul
                    & $matchingModule.Install $moduleData.ConfigParams $LocalTempDir
                }
                catch {
                    Write-Host "`n[ERROR] Kegagalan instalasi pada modul: $($matchingModule.Name)" -ForegroundColor Red
                    Write-Host "Detail: $_" -ForegroundColor Red
                }
                Write-Host ""
            }
        }
        
        # Bersihkan folder lokal temp
        if (Test-Path $LocalTempDir) {
            Write-Host "[INFO] Membersihkan file instalasi lokal..." -ForegroundColor Yellow
            Remove-Item -Path $LocalTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-Host "===========================================" -ForegroundColor Green
        Write-Host "          ALL PROCESSES COMPLETED          " -ForegroundColor Green
        Write-Host "===========================================" -ForegroundColor Green
        Write-Host ""
        Read-Host "Tekan Enter untuk menutup installer..."
    } else {
        Write-Host "[ERROR] Sesi Administrator dijalankan tanpa file konfigurasi lokal." -ForegroundColor Red
        Read-Host "Tekan Enter untuk keluar..."
    }
    exit
}

# ==========================================
# SESI STANDARD USER (KONFIGURASI & PRE-COPY DARI JARINGAN)
# ==========================================

# Tentukan path SMB modules jaringan kantor Anda
#$ModulesFolder = "\\10.37.10.116\j4\public\allsystem\hnf\j4deploy\Modules"
$ModulesFolder = "\\10.37.11.222\hnf\j4deploy\Modules"

if (-not (Test-Path $ModulesFolder)) {
    Write-Host "[ERROR] Folder modul jaringan tidak ditemukan: $ModulesFolder" -ForegroundColor Red
    Write-Host "Pastikan PC terhubung ke jaringan lokal/LAN." -ForegroundColor Yellow
    Read-Host "Tekan Enter untuk keluar..."
    exit
}

# Hapus sisa temp lama jika ada
if (Test-Path $LocalTempDir) {
    Remove-Item -Path $LocalTempDir -Recurse -Force -ErrorAction SilentlyContinue
}

while ($true) {
    # Muat modul secara dinamis dari folder jaringan SMB ke memori (bypasses execution policy)
    $ModuleFiles = Get-ChildItem -Path $ModulesFolder -Filter "*.ps1" | Sort-Object Name
    $Modules = @()
    foreach ($file in $ModuleFiles) {
        try {
            $moduleContent = Get-Content $file.FullName -Raw
            $module = iex $moduleContent
            if ($null -ne $module) {
                $module | Add-Member -MemberType NoteProperty -Name "Id" -Value ($Modules.Count + 1) -Force
                $module | Add-Member -MemberType NoteProperty -Name "ConfigParams" -Value $null -Force
                $module | Add-Member -MemberType NoteProperty -Name "FileName" -Value $file.Name -Force
                $module | Add-Member -MemberType NoteProperty -Name "FullPath" -Value $file.FullName -Force
                $Modules += $module
            }
        } catch {
            Write-Host "[WARNING] Gagal memuat file modul jaringan $($file.Name):" -ForegroundColor Yellow
            Write-Host "Detail: $_" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "        WINDOWS POST-INSTALL ORCHESTRATOR         " -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "Modul-modul installer yang terdeteksi di SMB:"
    if ($Modules.Count -eq 0) {
        Write-Host "  (Tidak ada modul .ps1 yang ditemukan di folder modules/)" -ForegroundColor Yellow
    } else {
        foreach ($m in $Modules) {
            Write-Host "  $($m.Id). $($m.Name)"
        }
    }
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Pilih Mode Jalankan:" -ForegroundColor Yellow
    Write-Host "  1. Install Semua Modul"
    Write-Host "  2. Install Sebagian (Pilih Manual)"
    Write-Host "  3. Keluar"
    Write-Host ""
    
    $modeChoice = Read-Host "Masukkan pilihan Anda (1-3)"
    
    if ($modeChoice -eq "3") {
        Write-Host "Keluar dari program..."
        exit
    }
    
    if ($Modules.Count -eq 0) {
        Write-Host "Tidak ada modul untuk dijalankan." -ForegroundColor Red
        Start-Sleep -Seconds 1.5
        continue
    }
    
    $selectedModules = @()
    
    if ($modeChoice -eq "1") {
        $selectedModules = $Modules
    }
    elseif ($modeChoice -eq "2") {
        Clear-Host
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "          PILIH SEBAGIAN INSTALLER                " -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
        foreach ($m in $Modules) {
            Write-Host "  $($m.Id). $($m.Name)"
        }
        Write-Host ""
        $selections = Read-Host "Masukkan nomor installer yang diinginkan (pisahkan dengan koma, contoh: 1,3)"
        
        $selectedIds = @()
        foreach ($sel in $selections.Split(',')) {
            $id = 0
            if ([int]::TryParse($sel.Trim(), [ref]$id)) {
                $selectedIds += $id
            }
        }
        
        $selectedModules = $Modules | Where-Object { $selectedIds -contains $_.Id }
    }
    else {
        continue
    }
    
    if ($selectedModules.Count -eq 0) {
        Write-Host "Tidak ada modul valid yang dipilih." -ForegroundColor Red
        Start-Sleep -Seconds 1.5
        continue
    }
    
    # Konfigurasi parameter modul
    $configuredModules = @()
    foreach ($m in $selectedModules) {
        $params = @{}
        if ($m.RequiresConfig) {
            $params = & $m.Configure
            if ($null -eq $params) {
                Write-Host "Modul '$($m.Name)' dilewati karena konfigurasi dibatalkan." -ForegroundColor Yellow
                Start-Sleep -Seconds 1.5
                continue
            }
        } else {
            $params = & $m.Configure
        }
        $m.ConfigParams = $params
        $configuredModules += $m
    }
    
    if ($configuredModules.Count -eq 0) {
        Write-Host "Tidak ada modul yang dikonfigurasi." -ForegroundColor Red
        Read-Host "Tekan Enter untuk kembali..."
        continue
    }
    
    # Summary
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "        RINGKASAN TARGET INSTALASI                " -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    foreach ($m in $configuredModules) {
        Write-Host "  [x] $($m.Name)" -ForegroundColor Green
        if ($m.RequiresConfig) {
            foreach ($k in $m.ConfigParams.Keys) {
                Write-Host "      - $k : $($m.ConfigParams[$k])" -ForegroundColor Gray
            }
        }
    }
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    $proceed = Read-Host "Apakah Anda ingin memulai proses instalasi? (Y/N)"
    
    if (-not ($proceed -match '^[yY]')) {
        continue
    }
    
    # Buat folder lokal temp
    if (-not (Test-Path $LocalTempDir)) {
        New-Item -ItemType Directory -Path $LocalTempDir -Force | Out-Null
    }
    
    # Salin file modul .ps1 terpilih ke lokal temp agar bisa diakses saat elevated
    $LocalModulesFolder = Join-Path $LocalTempDir "modules"
    New-Item -ItemType Directory -Path $LocalModulesFolder -Force | Out-Null
    foreach ($m in $configuredModules) {
        Copy-Item -Path $m.FullPath -Destination (Join-Path $LocalModulesFolder $m.FileName) -Force
    }
    
    # Jalankan proses pre-copy untuk file driver jaringan
    $allCopiesSuccess = $true
    foreach ($m in $configuredModules) {
        if ($null -ne $m.PreCopy) {
            $success = & $m.PreCopy $LocalTempDir
            if (-not $success) {
                $allCopiesSuccess = $false
                break
            }
        }
    }
    
    if (-not $allCopiesSuccess) {
        Write-Host "`n[ERROR] Gagal menyalin file driver dari jaringan. Instalasi dibatalkan." -ForegroundColor Red
        Remove-Item -Path $LocalTempDir -Recurse -Force -ErrorAction SilentlyContinue
        Read-Host "Tekan Enter untuk kembali ke Menu Utama..."
        continue
    }
    
    # Simpan konfigurasi parameter ke file JSON
    $exportData = @()
    foreach ($m in $configuredModules) {
        $exportData += @{
            "FileName"     = $m.FileName
            "ConfigParams" = $m.ConfigParams
        }
    }
    $exportData | ConvertTo-Json -Depth 5 | Out-File $ConfigFile -Encoding utf8
    
    # Salin script Orchestrator itu sendiri (script ini) ke lokal agar bisa dijalankan secara elevated
    $LocalScriptPath = Join-Path $LocalTempDir "Orchestrator.ps1"
    Write-Host "[INFO] Mengunduh script utama untuk sesi Administrator..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri $RemoteUrl -OutFile $LocalScriptPath
    
    # Jalankan elevasi sebagai Administrator
    try {
        Write-Host "[INFO] Elevasi ke sesi Administrator untuk memulai eksekusi instalasi..." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`"" -Verb RunAs -PassThru -Wait
    }
    catch {
        Write-Host "`n[PERINGATAN] Elevasi Administrator ditolak oleh pengguna." -ForegroundColor Red
        if (Test-Path $LocalTempDir) {
            Remove-Item -Path $LocalTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Read-Host "Tekan Enter untuk kembali ke Menu Utama..."
        continue
    }
    
    # Pembersihan setelah selesai
    if (Test-Path $ConfigFile) {
        Remove-Item $ConfigFile -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
    Write-Host "[INFO] Proses instalasi selesai. Kembali ke Menu Utama..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}
