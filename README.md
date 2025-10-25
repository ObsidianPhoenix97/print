# PC Health Maintenance Utility

This repository provides a PowerShell-based maintenance utility for Windows 10/11 devices. The script automates routine hygiene tasks such as clearing caches, uninstalling bundled applications (Copilot preview, Xbox, Teams consumer), triggering Windows Update, and collecting a detailed health snapshot of CPU, memory, disks, and hardware stability indicators.

## Features

- **Health reporting** – captures CPU load, memory usage, storage utilization, BIOS version, uptime, and Windows Update status.
- **Cache cleanup** – purges system and user temp folders, Delivery Optimization remnants, browser cache, and invokes Disk Cleanup.
- **App removal** – removes selected preinstalled applications across all users (Copilot preview, Xbox, Teams consumer, Get Help, Tips).
- **Windows Update automation** – initiates scan, download, and install cycles using `UsoClient`.
- **Hardware stability check** – summarizes disk SMART status, processor load, and memory module health metadata.
- **JSON reporting** – outputs a structured report for auditing or further processing.
- **Platform awareness** – gracefully skips Windows-only maintenance steps when executed on non-Windows hosts, surfacing warnings instead of terminating with errors.

## Requirements

- Windows 10/11 with PowerShell 5.1 or later.
- Execution policy that allows the script to run (`Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`).
- Administrative privileges for application removal and system cleanup actions.

## Usage

1. Download or clone this repository.
2. Open an elevated PowerShell session.
3. Run the script:

   ```powershell
   cd <path-to-repo>
   .\scripts\pc_health_maintenance.ps1
   ```

   A JSON summary is written to `%TEMP%\system-maintenance-summary.json`. Use the parameters below to customize execution.

### Parameters

- `-SkipUpdates` – skip Windows Update initiation.
- `-SkipAppCleanup` – skip bundled application removal.
- `-SkipCacheCleanup` – skip cache/temp cleanup.
- `-SummaryPath <path>` – write the JSON report to a custom location.

### Example

```powershell
# Run maintenance but skip app removal and store the summary on the desktop
.\scripts\pc_health_maintenance.ps1 -SkipAppCleanup -SummaryPath "$env:USERPROFILE\Desktop\maintenance-summary.json"
```

## Notes

- Windows Update automation relies on `UsoClient`, which is available on most modern Windows builds. If unavailable, the script logs a warning.
- App removal targets the Microsoft Store packages that commonly include Copilot preview and Xbox. Modify the `$appPatterns` array to customize removal.
- Disk Cleanup (`cleanmgr`) may prompt for initial configuration when run for the first time; configure settings using `cleanmgr /sageset:1` prior to automated runs.
- Hardware health readings are informational and should be combined with vendor diagnostics for mission-critical environments.
- When run on non-Windows platforms (e.g., during CI smoke tests), the script emits warnings and omits Windows-only checks rather than failing outright.

## Extending

- Integrate with centralized logging by forwarding `$summary` to your telemetry pipeline.
- Schedule the script via Task Scheduler with `-SkipAppCleanup` for regular hygiene while preserving user applications.
- Expand the cleanup list with browser-specific caches or additional system directories as needed.
