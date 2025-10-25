<#
.SYNOPSIS
    Comprehensive Windows maintenance utility for monitoring and remediation.

.DESCRIPTION
    Provides a single entry point (Invoke-SystemMaintenance) that performs:
      * Health checks across CPU, memory, storage, and Windows Update status.
      * Cleanup of transient caches such as Temp folders, Delivery Optimization, and browser caches.
      * Optional removal of bundled applications (Copilot preview, Xbox, Teams consumer, etc.).
      * Triggering of Windows Update scan and installation.

    All actions emit rich logging with color-coded output and a JSON summary file to aid auditing.
    The script avoids third-party dependencies and relies on built-in Windows tooling (PowerShell 5.1+).
#>

[CmdletBinding()]
param(
    [switch]$SkipUpdates,
    [switch]$SkipAppCleanup,
    [switch]$SkipCacheCleanup,
    [string]$SummaryPath = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'system-maintenance-summary.json')
)

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('u')
    switch ($Level) {
        'Info'    { $color = 'Gray' }
        'Warning' { $color = 'Yellow' }
        'Error'   { $color = 'Red' }
        'Success' { $color = 'Green' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-SystemHealth {
    Write-Log 'Collecting system health metrics...' 'Info'
    $health = [ordered]@{}

    if (Test-CommandAvailable 'Get-Counter') {
        try {
            $cpuSample = Get-Counter -Counter '\\Processor(_Total)\\% Processor Time' -ErrorAction Stop
            $health.CPUUtilization = [math]::Round(($cpuSample.CounterSamples.CookedValue | Measure-Object -Average).Average, 2)
        }
        catch {
            Write-Log "Unable to sample CPU counters: $($_.Exception.Message)" 'Warning'
            $health.CPUUtilization = $null
        }
    }
    else {
        Write-Log 'Get-Counter is not available on this platform; skipping CPU utilization metrics.' 'Warning'
        $health.CPUUtilization = $null
    }

    if (Test-CommandAvailable 'Get-CimInstance') {
        try {
            $memory = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $totalMemoryGB = if ($memory.TotalVisibleMemorySize) { [math]::Round($memory.TotalVisibleMemorySize/1MB, 2) } else { 0 }
            $freeMemoryGB = if ($memory.FreePhysicalMemory) { [math]::Round($memory.FreePhysicalMemory/1MB, 2) } else { 0 }
            $utilization = if ($totalMemoryGB -gt 0) {
                [math]::Round((1 - ($freeMemoryGB / $totalMemoryGB)) * 100, 2)
            } else { $null }
            $health.Memory = [ordered]@{
                TotalGB = $totalMemoryGB
                FreeGB  = $freeMemoryGB
                UtilizationPercent = $utilization
            }
        }
        catch {
            Write-Log "Unable to query operating system memory metrics: $($_.Exception.Message)" 'Warning'
            $health.Memory = $null
        }
    }
    else {
        Write-Log 'CIM cmdlets are not available on this platform; skipping detailed memory metrics.' 'Warning'
        $health.Memory = $null
    }

    $health.Storage = @()
    if (Test-CommandAvailable 'Get-CimInstance') {
        try {
            $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
            foreach ($drive in $drives) {
                $total = if ($drive.Size) { [math]::Round($drive.Size / 1GB, 2) } else { 0 }
                $free  = if ($drive.FreeSpace) { [math]::Round($drive.FreeSpace / 1GB, 2) } else { 0 }
                $health.Storage += [ordered]@{
                    Name = $drive.DeviceID
                    TotalGB = $total
                    FreeGB = $free
                    UtilizationPercent = if ($total -eq 0) { $null } else { [math]::Round((1 - ($free/$total)) * 100, 2) }
                }
            }
        }
        catch {
            Write-Log "Unable to collect logical disk metrics: $($_.Exception.Message)" 'Warning'
        }
    }
    else {
        Write-Log 'CIM cmdlets are not available on this platform; skipping storage metrics.' 'Warning'
    }

    if (Test-CommandAvailable 'Get-CimInstance') {
        try {
            $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
            $health.BIOSVersion = $bios.SMBIOSBIOSVersion
        }
        catch {
            Write-Log "Unable to query BIOS information: $($_.Exception.Message)" 'Warning'
            $health.BIOSVersion = $null
        }
    }
    else {
        $health.BIOSVersion = $null
    }

    if (Test-CommandAvailable 'Get-CimInstance') {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            if ($os.LastBootUpTime) {
                $uptime = (Get-Date) - $os.LastBootUpTime
                $health.UptimeHours = [math]::Round($uptime.TotalHours, 2)
            }
            else {
                $health.UptimeHours = $null
            }
        }
        catch {
            Write-Log "Unable to compute system uptime: $($_.Exception.Message)" 'Warning'
            $health.UptimeHours = $null
        }
    }
    else {
        $health.UptimeHours = $null
    }

    $health.WindowsUpdate = Get-WindowsUpdateStatus

    return $health
}

function Get-WindowsUpdateStatus {
    $updateResult = [ordered]@{
        PendingInstallations = @()
        LastError = $null
    }
    if (-not $IsWindows) {
        Write-Log 'Windows Update status is only available on Windows hosts.' 'Warning'
        return $updateResult
    }

    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $searcher = $updateSession.CreateUpdateSearcher()
        $result = $searcher.Search('IsInstalled=0 and Type="Software"')
        foreach ($update in $result.Updates) {
            $updateResult.PendingInstallations += $update.Title
        }
    }
    catch {
        Write-Log "Unable to query Windows Update status: $($_.Exception.Message)" 'Warning'
        $updateResult.LastError = $_.Exception.Message
    }
    return $updateResult
}

function Clear-TempCaches {
    Write-Log 'Starting cache and temporary file cleanup...' 'Info'
    $paths = @(
        $env:TEMP,
        "$env:SystemRoot\\Temp",
        "$env:LOCALAPPDATA\\Microsoft\\Windows\\INetCache",
        "$env:LOCALAPPDATA\\Temp",
        "$env:LOCALAPPDATA\\Packages\\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\\LocalState\\Assets",
        "$env:ProgramData\\Microsoft\\Windows\\WER\\ReportQueue"
    ) | Sort-Object -Unique

    foreach ($path in $paths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            Write-Log "Clearing $path" 'Info'
            try {
                Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                $message = "Failed to clean {0}: {1}" -f $path, $_.Exception.Message
                Write-Log $message 'Warning'
            }
        }
    }

    if ($IsWindows -and (Test-CommandAvailable 'cleanmgr.exe')) {
        Write-Log 'Invoking Windows Disk Cleanup for system component cleanup...' 'Info'
        Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -Wait -ErrorAction SilentlyContinue
    }
    else {
        Write-Log 'Disk Cleanup utility (cleanmgr.exe) is not available; skipping system component cleanup.' 'Warning'
    }
}

function Remove-UnwantedApps {
    Write-Log 'Removing bundled applications (Copilot preview, Xbox, Teams consumer)...' 'Info'
    if (-not $IsWindows -or -not (Test-CommandAvailable 'Get-AppxPackage')) {
        Write-Log 'Appx cmdlets are not available; skipping bundled application removal.' 'Warning'
        return
    }

    $appPatterns = @(
        'Microsoft.549981C3F5F10', # Microsoft Copilot preview
        'Microsoft.GamingApp',     # Xbox app
        'Microsoft.Xbox',          # Legacy Xbox components
        'Microsoft.Teams',         # Personal Teams
        'Microsoft.GetHelp',
        'Microsoft.Getstarted'
    )

    foreach ($pattern in $appPatterns) {
        $apps = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$pattern*" }
        foreach ($app in $apps) {
            try {
                Write-Log "Removing $($app.Name) for all users" 'Info'
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
            }
            catch {
                $message = "Failed to remove {0}: {1}" -f $app.Name, $_.Exception.Message
                Write-Log $message 'Warning'
            }
        }
    }
}

function Install-SystemUpdates {
    Write-Log 'Triggering Windows Update scan and install...' 'Info'
    if (-not $IsWindows) {
        Write-Log 'Windows Update automation is only available on Windows hosts.' 'Warning'
        return
    }

    $usoPath = (Get-Command 'UsoClient.exe' -ErrorAction SilentlyContinue)?.Source
    if (-not $usoPath) {
        Write-Log 'UsoClient.exe is not available; unable to trigger Windows Update.' 'Warning'
        return
    }

    $commands = @(
        'Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan" -Wait',
        'Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartDownload" -Wait',
        'Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartInstall" -Wait'
    )
    foreach ($cmd in $commands) {
        try {
            Write-Log "Executing: $cmd" 'Info'
            Invoke-Expression $cmd
        }
        catch {
            Write-Log "Windows Update command failed: $($_.Exception.Message)" 'Warning'
        }
    }
}

function Test-HardwareStability {
    Write-Log 'Validating hardware health (disk, CPU, memory) ...' 'Info'
    $hardware = [ordered]@{}

    if (Test-CommandAvailable 'Get-CimInstance') {
        try {
            $disks = Get-CimInstance Win32_DiskDrive -ErrorAction Stop
            $hardware.Disks = foreach ($disk in $disks) {
                [ordered]@{
                    Model = $disk.Model
                    Status = $disk.Status
                    PredictFailure = $disk.PredictFailure
                }
            }
        }
        catch {
            Write-Log "Unable to query disk health: $($_.Exception.Message)" 'Warning'
            $hardware.Disks = @()
        }

        try {
            $processors = Get-CimInstance Win32_Processor -ErrorAction Stop
            $hardware.CPU = foreach ($cpu in $processors) {
                $load = $null
                try {
                    $load = $cpu.LoadPercentage
                }
                catch {
                    $load = $null
                }
                [ordered]@{
                    Name = $cpu.Name
                    LoadPercent = $load
                    Status = $cpu.Status
                }
            }
        }
        catch {
            Write-Log "Unable to query CPU health: $($_.Exception.Message)" 'Warning'
            $hardware.CPU = @()
        }

        try {
            $memoryModules = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop
            $hardware.MemoryModules = foreach ($module in $memoryModules) {
                [ordered]@{
                    Manufacturer = $module.Manufacturer
                    PartNumber = $module.PartNumber
                    CapacityGB = if ($module.Capacity) { [math]::Round($module.Capacity / 1GB, 2) } else { $null }
                    HealthStatus = $module.HealthStatus
                }
            }
        }
        catch {
            Write-Log "Unable to query memory module health: $($_.Exception.Message)" 'Warning'
            $hardware.MemoryModules = @()
        }
    }
    else {
        Write-Log 'CIM cmdlets are not available; hardware stability checks are skipped.' 'Warning'
        $hardware.Disks = @()
        $hardware.CPU = @()
        $hardware.MemoryModules = @()
    }

    return $hardware
}

function Save-Summary {
    param(
        [hashtable]$Data,
        [string]$Path
    )
    try {
        $json = $Data | ConvertTo-Json -Depth 6
        $folder = Split-Path -Path $Path -Parent
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        $json | Set-Content -Path $Path -Encoding UTF8
        Write-Log "Saved summary report to $Path" 'Success'
    }
    catch {
        Write-Log "Failed to save summary: $($_.Exception.Message)" 'Warning'
    }
}

function Invoke-SystemMaintenance {
    Write-Log '===== Starting system maintenance workflow =====' 'Success'
    $summary = [ordered]@{
        StartedAt = (Get-Date)
        CacheCleanup = $false
        AppCleanup = $false
        UpdatesTriggered = $false
    }

    if (-not $SkipCacheCleanup) {
        Clear-TempCaches
        $summary.CacheCleanup = $true
    }
    else {
        Write-Log 'Skipping cache cleanup as requested.' 'Warning'
    }

    if (-not $SkipAppCleanup) {
        Remove-UnwantedApps
        $summary.AppCleanup = $true
    }
    else {
        Write-Log 'Skipping bundled app removal as requested.' 'Warning'
    }

    if (-not $SkipUpdates) {
        Install-SystemUpdates
        $summary.UpdatesTriggered = $true
    }
    else {
        Write-Log 'Skipping Windows Update trigger as requested.' 'Warning'
    }

    $summary.Health = Test-SystemHealth
    $summary.Hardware = Test-HardwareStability
    $summary.CompletedAt = (Get-Date)

    Save-Summary -Data $summary -Path $SummaryPath
    Write-Log '===== Maintenance workflow completed =====' 'Success'
    return $summary
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SystemMaintenance
}
