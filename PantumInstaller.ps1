#requires -Version 3.0
<#!
.SYNOPSIS
    Installs the Pantum M7105DN printer driver and sets up a network printer.
.DESCRIPTION
    Searches for Pantum driver files in D:\pantum, installs the Pantum M7105DN driver,
    adds a printer on the specified IP address, and sets it as the default printer.
!#>

param(
    [string]$DriverRoot = 'D:\pantum',
    [string]$PrinterName = 'Pantum M7105DN',
    [string]$DriverName = 'Pantum M7105DN',
    [string]$PrinterIpAddress = '192.168.100.105'
)

function Get-DriverInfFile {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [Parameter(Mandatory)]
        [string]$DriverName
    )

    if (-not (Test-Path -Path $RootPath)) {
        throw "Driver directory '$RootPath' does not exist."
    }

    Write-Verbose "Searching for INF files in '$RootPath'."
    $infFiles = Get-ChildItem -Path $RootPath -Filter '*.inf' -Recurse -ErrorAction Stop

    foreach ($infFile in $infFiles) {
        try {
            $content = Get-Content -Path $infFile.FullName -Raw -ErrorAction Stop
            if ($content -match [Regex]::Escape($DriverName)) {
                Write-Verbose "Found matching driver INF: $($infFile.FullName)"
                return $infFile.FullName
            }
        }
        catch {
            Write-Warning "Unable to read file '$($infFile.FullName)': $_"
        }
    }

    throw "No INF file containing driver name '$DriverName' was found under '$RootPath'."
}

function Ensure-PrintSpooler {
    try {
        $service = Get-Service -Name 'Spooler' -ErrorAction Stop
    }
    catch {
        throw "Unable to query Print Spooler service: $_"
    }

    if ($service.Status -ne 'Running') {
        Write-Verbose "Starting Print Spooler service."
        try {
            Start-Service -Name 'Spooler' -ErrorAction Stop
            $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
        }
        catch {
            throw "Failed to start the Print Spooler service: $_"
        }
    }
}

function Ensure-PrinterDriver {
    param(
        [Parameter(Mandatory)]
        [string]$DriverName,
        [Parameter(Mandatory)]
        [string]$InfPath
    )

    $existingDriver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
    if ($null -ne $existingDriver) {
        Write-Verbose "Printer driver '$DriverName' is already installed."
        return
    }

    Write-Verbose "Installing printer driver '$DriverName' from '$InfPath'."
    $addPrinterDriverCmd = Get-Command -Name Add-PrinterDriver -ErrorAction Stop
    if ($addPrinterDriverCmd.Parameters.ContainsKey('InfPath')) {
        try {
            Add-PrinterDriver -Name $DriverName -InfPath $InfPath -ErrorAction Stop
            return
        }
        catch {
            Write-Warning "Add-PrinterDriver failed with -InfPath: $_"
        }
    }

    $pnputilPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\\pnputil.exe'
    if (-not (Test-Path -Path $pnputilPath)) {
        throw "Unable to install driver. Neither Add-PrinterDriver nor pnputil.exe succeeded."
    }

    $arguments = @('/add-driver', '"{0}"' -f $InfPath, '/install')
    $process = Start-Process -FilePath $pnputilPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "pnputil.exe failed with exit code $($process.ExitCode)."
    }

    $existingDriver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
    if ($null -eq $existingDriver) {
        throw "Driver '$DriverName' was not installed even though pnputil.exe reported success."
    }
}

function Ensure-TcpPort {
    param(
        [Parameter(Mandatory)]
        [string]$PortName,
        [Parameter(Mandatory)]
        [string]$PrinterIpAddress
    )

    $existingPort = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if ($null -ne $existingPort) {
        Write-Verbose "Printer port '$PortName' already exists."
        return
    }

    Write-Verbose "Creating TCP/IP printer port '$PortName' for $PrinterIpAddress."
    Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIpAddress -ErrorAction Stop
}

function Ensure-Printer {
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        [Parameter(Mandatory)]
        [string]$DriverName,
        [Parameter(Mandatory)]
        [string]$PortName
    )

    $existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($null -ne $existingPrinter) {
        Write-Verbose "Printer '$PrinterName' already exists."
    }
    else {
        Write-Verbose "Creating printer '$PrinterName' using driver '$DriverName' on port '$PortName'."
        Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName -ErrorAction Stop
    }

    Write-Verbose "Setting printer '$PrinterName' as the default printer."
    Set-Printer -Name $PrinterName -IsDefault $true -ErrorAction Stop
}

try {
    Ensure-PrintSpooler

    $infPath = Get-DriverInfFile -RootPath $DriverRoot -DriverName $DriverName
    Ensure-PrinterDriver -DriverName $DriverName -InfPath $infPath

    $portName = "IP_$PrinterIpAddress"
    Ensure-TcpPort -PortName $portName -PrinterIpAddress $PrinterIpAddress

    Ensure-Printer -PrinterName $PrinterName -DriverName $DriverName -PortName $portName

    Write-Output "Pantum M7105DN printer installation completed successfully."
}
catch {
    Write-Error $_
    exit 1
}
