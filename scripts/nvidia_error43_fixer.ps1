# Script:   nvidia-error43-fixer.ps1
# Author:   (C) 2018-2021 nando4eva@ymail.com (Converted to PowerShell by @pythoninthegrass)
# Repository adaptation: adapted for local automation workflows.
# Homepage: https://egpu.io/nvidia-error43-fixer

param(
    [switch]$Force
)

# Check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Request administrator privileges if not running as admin
if (-not (Test-Administrator)) {
    Write-Host "Requesting administrative privileges..." -ForegroundColor Yellow
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    if ($Force) {
        $arguments += " -Force"
    }
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
    exit
}

# Constants
$SCRIPT_NAME = "nvidia-error43-fixer"
$SCRIPT_VER = "v1.1.3-PS"
$SCRIPT_AUTH = "(C) 2018-2021 nando4eva@ymail.com"
$SCRIPT_HOME = "https://egpu.io/nvidia-error43-fixer"

# Registry patch settings
$NV_KEY = "RM1774520"
$NV_KEY_DATA = 0x1
$NV_KEY_TYPE = "DWORD"

# Text strings
$PRESS_KEY = "Press any key to exit..."
$NO_NV_GPUS = "No Nvidia GPUs found. Please attach one and ensure its driver is installed."
$NO_NV_ERROR43_GPUS = "No Nvidia GPUs in error code 43 state found. Nothing to do."
$ALREADY_FIXED = "is already registry patched but still has error code 43."
$APPLY_FIX = "has error code 43. Applying registry patch."
$FIX_FAILED = "ERROR. Registry patch failed. Please manually add using regedit:"
$IS_FIXED = "is fixed. Now reports as:"
$IS_NOT_FIXED = "still has a problem:"
$RESTART_GPU = "restarting adapter."
$MORE_EGPUIO_FIXES = ". Press any key to see other fixes for error code 43 at eGPU.io..."
$EGPUIO_FIXES_URL = "https://egpu.io/forums/expresscard-mpcie-m-2-adapters/mpcieecngff-m2-resolving-detection-bootup-and-stability-problems/"

function Show-Banner {
    Write-Host ""
    Write-Host "                                          " -BackgroundColor Green -ForegroundColor White
    Write-Host "   $SCRIPT_NAME $SCRIPT_VER            " -BackgroundColor Green -ForegroundColor White
    Write-Host "   $SCRIPT_AUTH      " -BackgroundColor Green -ForegroundColor White
    Write-Host "                                          " -BackgroundColor Green -ForegroundColor White
    Write-Host "   $SCRIPT_HOME   " -BackgroundColor Green -ForegroundColor White
    Write-Host "                                          " -BackgroundColor Green -ForegroundColor White
    Write-Host ""
}

function Get-DeviceStatus {
    param([string]$HardwareId, [string]$AdapterName)

    try {
        # Method 1: Try Get-CimInstance (more reliable than WMI)
        $devices = Get-CimInstance -Class Win32_PnPEntity | Where-Object { 
            ($_.HardwareID -like "*$HardwareId*") -or 
            ($_.Name -like "*$AdapterName*") -or
            ($_.DeviceID -like "*$HardwareId*")
        }

        foreach ($device in $devices) {
            if ($device.ConfigManagerErrorCode -eq 43) {
                return "Windows has stopped this device because it has reported problems. (code 43)"
            }
            elseif ($device.ConfigManagerErrorCode -eq 0) {
                return "Driver is running."
            }
            else {
                return "Device status: $($device.Status) (Error Code: $($device.ConfigManagerErrorCode))"
            }
        }

        # Method 2: Try Get-PnpDevice if available (Windows 8+)
        if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
            $pnpDevices = Get-PnpDevice | Where-Object { 
                ($_.HardwareID -like "*$HardwareId*") -or 
                ($_.FriendlyName -like "*$AdapterName*") -or
                ($_.InstanceId -like "*$HardwareId*")
            }

            foreach ($pnpDevice in $pnpDevices) {
                if ($pnpDevice.Status -eq "Error") {
                    return "Windows has stopped this device because it has reported problems. (code 43)"
                }
                elseif ($pnpDevice.Status -eq "OK") {
                    return "Driver is running."
                }
                else {
                    return "Device status: $($pnpDevice.Status)"
                }
            }
        }

        return "Device not found with ID: $HardwareId"
    }
    catch {
        return "Error checking device status: $($_.Exception.Message)"
    }
}

function Restart-NvidiaDevice {
    param([string]$HardwareId)

    try {
        # Method 1: Try with PnP cmdlets first (most reliable)
        if (Get-Command Disable-PnpDevice -ErrorAction SilentlyContinue) {
            $pnpDevices = Get-PnpDevice | Where-Object { 
                $_.FriendlyName -like "*NVIDIA*" -and $_.Status -eq "Error"
            }

            foreach ($pnpDevice in $pnpDevices) {
                try {
                    Write-Host "   DEBUG: Attempting PnP restart for: $($pnpDevice.FriendlyName)" -ForegroundColor Gray
                    Disable-PnpDevice -InstanceId $pnpDevice.InstanceId -Confirm:$false
                    Start-Sleep -Seconds 2
                    Enable-PnpDevice -InstanceId $pnpDevice.InstanceId -Confirm:$false
                    Start-Sleep -Seconds 3
                    Write-Host "   DEBUG: Device restart attempted via PnP cmdlets" -ForegroundColor Gray
                    return $true
                }
                catch {
                    Write-Host "   DEBUG: PnP restart failed: $($_.Exception.Message)" -ForegroundColor Gray
                }
            }
        }

        # Method 2: Try with CimInstance and Invoke-CimMethod
        $devices = Get-CimInstance -Class Win32_PnPEntity | Where-Object { 
            $_.HardwareID -like "*$HardwareId*" -or $_.Name -like "*NVIDIA*"
        }

        foreach ($device in $devices) {
            if ($device.ConfigManagerErrorCode -eq 43) {
                Write-Host "   DEBUG: Attempting to restart device via CIM: $($device.Name)" -ForegroundColor Gray
                try {
                    Invoke-CimMethod -InputObject $device -MethodName "Disable" | Out-Null
                    Start-Sleep -Seconds 2
                    Invoke-CimMethod -InputObject $device -MethodName "Enable" | Out-Null
                    Start-Sleep -Seconds 3
                    Write-Host "   DEBUG: Device restart attempted via CIM" -ForegroundColor Gray
                    return $true
                }
                catch {
                    Write-Host "   DEBUG: CIM restart failed: $($_.Exception.Message)" -ForegroundColor Gray
                }
            }
        }

        # Method 3: Try with legacy WMI objects
        try {
            $wmiDevices = Get-WmiObject -Class Win32_PnPEntity | Where-Object { 
                $_.HardwareID -like "*$HardwareId*" -or $_.Name -like "*NVIDIA*"
            }

            foreach ($wmiDevice in $wmiDevices) {
                if ($wmiDevice.ConfigManagerErrorCode -eq 43) {
                    Write-Host "   DEBUG: Attempting to restart device via WMI: $($wmiDevice.Name)" -ForegroundColor Gray
                    try {
                        $wmiDevice.InvokeMethod("Disable", $null) | Out-Null
                        Start-Sleep -Seconds 2
                        $wmiDevice.InvokeMethod("Enable", $null) | Out-Null
                        Start-Sleep -Seconds 3
                        Write-Host "   DEBUG: Device restart attempted via WMI" -ForegroundColor Gray
                        return $true
                    }
                    catch {
                        Write-Host "   DEBUG: WMI restart failed: $($_.Exception.Message)" -ForegroundColor Gray
                    }
                }
            }
        }
        catch {
            Write-Host "   DEBUG: WMI method not available: $($_.Exception.Message)" -ForegroundColor Gray
        }

        # Method 4: Suggest manual restart
        Write-Host "   NOTE: Automatic device restart may have failed. You may need to manually disable/enable the device in Device Manager." -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Warning "Could not restart device: $($_.Exception.Message)"
        return $false
    }
}

function Test-Error43Status {
    param([string]$HardwareId, [string]$AdapterName)

    # Method 1: Check via CIM
    try {
        $devices = Get-CimInstance -Class Win32_PnPEntity | Where-Object { 
            ($_.Name -like "*NVIDIA*" -and $_.Name -like "*$($AdapterName.Split(' ')[-1])*") -or
            ($_.HardwareID -like "*$HardwareId*") -or
            ($_.DeviceID -like "*$HardwareId*")
        }

        foreach ($device in $devices) {
            Write-Host "   DEBUG: Found device - Name: $($device.Name), Status: $($device.Status), ErrorCode: $($device.ConfigManagerErrorCode)" -ForegroundColor Gray
            if ($device.ConfigManagerErrorCode -eq 43) {
                return $true
            }
        }
    }
    catch {
        Write-Host "   DEBUG: CIM method failed: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # Method 2: Check via PnP cmdlets
    try {
        if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
            $pnpDevices = Get-PnpDevice | Where-Object { 
                $_.FriendlyName -like "*NVIDIA*" -and 
                ($_.FriendlyName -like "*$($AdapterName.Split(' ')[-1])*" -or $_.InstanceId -like "*$HardwareId*")
            }

            foreach ($pnpDevice in $pnpDevices) {
                Write-Host "   DEBUG: Found PnP device - Name: $($pnpDevice.FriendlyName), Status: $($pnpDevice.Status)" -ForegroundColor Gray
                if ($pnpDevice.Status -eq "Error") {
                    return $true
                }
            }
        }
    }
    catch {
        Write-Host "   DEBUG: PnP method failed: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # Method 3: Check all NVIDIA devices for any with error 43
    try {
        $allNvidiaDevices = Get-CimInstance -Class Win32_PnPEntity | Where-Object { $_.Name -like "*NVIDIA*" }
        foreach ($device in $allNvidiaDevices) {
            Write-Host "   DEBUG: NVIDIA device - $($device.Name), ErrorCode: $($device.ConfigManagerErrorCode)" -ForegroundColor Gray
            if ($device.ConfigManagerErrorCode -eq 43) {
                Write-Host "   DEBUG: Found Error 43 on: $($device.Name)" -ForegroundColor Yellow
                return $true
            }
        }
    }
    catch {
        Write-Host "   DEBUG: All NVIDIA scan failed: $($_.Exception.Message)" -ForegroundColor Gray
    }

    return $false
}

function Patch-NvidiaAdapter {
    param([string]$DeviceKey, [string]$HardwareId, [string]$AdapterName)

    Write-Host "   DEBUG: Checking adapter: $AdapterName with HW ID: $HardwareId" -ForegroundColor Gray

    # Check if adapter has error code 43
    if (-not (Test-Error43Status -HardwareId $HardwareId -AdapterName $AdapterName)) {
        Write-Host "   DEBUG: No error 43 found for $AdapterName" -ForegroundColor Gray
        return
    }

    $script:NV_ERR43_FOUND = $true

    # Check if already patched
    try {
        $existingValue = Get-ItemProperty -Path "HKLM:\$DeviceKey" -Name $NV_KEY -ErrorAction SilentlyContinue
        if ($existingValue -and $existingValue.$NV_KEY -eq $NV_KEY_DATA) {
            Write-Host "   [$AdapterName] $ALREADY_FIXED" -ForegroundColor Yellow
            return
        }
    }
    catch {
        # Key doesn't exist, which is fine
    }

    # Apply the patch
    Write-Host "   [$AdapterName] $APPLY_FIX" -ForegroundColor Cyan

    try {
        Set-ItemProperty -Path "HKLM:\$DeviceKey" -Name $NV_KEY -Value $NV_KEY_DATA -Type $NV_KEY_TYPE -Force

        # Verify patch was applied
        $verifyValue = Get-ItemProperty -Path "HKLM:\$DeviceKey" -Name $NV_KEY -ErrorAction SilentlyContinue
        if (-not $verifyValue -or $verifyValue.$NV_KEY -ne $NV_KEY_DATA) {
            throw "Registry verification failed"
        }

        # Restart the GPU
        Write-Host "   [$AdapterName] $RESTART_GPU" -ForegroundColor Yellow
        Restart-NvidiaDevice -HardwareId $HardwareId

        # Check if fix worked
        $newStatus = Get-DeviceStatus -HardwareId $HardwareId -AdapterName $AdapterName
        if ($newStatus -like "*Driver is running*") {
            $script:NV_FIXED = $true
            Write-Host "   [$AdapterName] $IS_FIXED '$newStatus'" -ForegroundColor Green
        }
        else {
            Write-Host "   [$AdapterName] $IS_NOT_FIXED '$newStatus'" -ForegroundColor Red
        }
    }
    catch {
        Write-Host ""
        Write-Host "   [$AdapterName] $FIX_FAILED" -ForegroundColor Red
        Write-Host ""
        Write-Host "   Key:  HKLM:\$DeviceKey"
        Write-Host "   Data: $NV_KEY = $NV_KEY_DATA ($NV_KEY_TYPE)"
        Write-Host ""
    }
}

# Main execution
Show-Banner

# Initialize tracking variables
$script:NV_FIXED = $false
$script:NV_ERR43_FOUND = $false

# Find NVIDIA display adapters
$displayAdaptersPath = "HKLM:\System\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$nvidiaAdapters = @()

try {
    $subKeys = Get-ChildItem -Path $displayAdaptersPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\[0-9]{4}$" }

    foreach ($subKey in $subKeys) {
        try {
            $driverDesc = Get-ItemProperty -Path $subKey.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue
            $matchingDeviceId = Get-ItemProperty -Path $subKey.PSPath -Name "MatchingDeviceId" -ErrorAction SilentlyContinue

            if ($driverDesc -and $driverDesc.DriverDesc -like "*NVIDIA*") {
                $deviceKey = $subKey.PSPath -replace "Microsoft.PowerShell.Core\\Registry::", ""
                $nvidiaAdapters += @{
                    DeviceKey   = $deviceKey
                    AdapterName = $driverDesc.DriverDesc
                    HardwareId  = $matchingDeviceId.MatchingDeviceId
                }
            }
        }
        catch {
            # Skip problematic entries
            continue
        }
    }
}
catch {
    Write-Error "Failed to query registry for NVIDIA adapters: $($_.Exception.Message)"
}

# Process each NVIDIA adapter
foreach ($adapter in $nvidiaAdapters) {
    Patch-NvidiaAdapter -DeviceKey $adapter.DeviceKey -HardwareId $adapter.HardwareId -AdapterName $adapter.AdapterName
}

# Fallback: If no error 43 found but user says there is one, scan all NVIDIA devices directly
if (-not $script:NV_ERR43_FOUND) {
    Write-Host "   DEBUG: No error 43 found via registry method. Scanning all NVIDIA devices directly..." -ForegroundColor Yellow

    try {
        $allNvidiaDevices = Get-CimInstance -Class Win32_PnPEntity | Where-Object { $_.Name -like "*NVIDIA*" }

        foreach ($device in $allNvidiaDevices) {
            Write-Host "   DEBUG: Checking device: $($device.Name) - Error Code: $($device.ConfigManagerErrorCode)" -ForegroundColor Gray

            if ($device.ConfigManagerErrorCode -eq 43) {
                Write-Host "   Found NVIDIA device with Error 43: $($device.Name)" -ForegroundColor Red
                $script:NV_ERR43_FOUND = $true

                # Try to find corresponding registry entry
                $deviceId = $device.DeviceID
                if ($deviceId -match "VEN_(\w+)&DEV_(\w+)") {
                    $hardwareId = "VEN_$($matches[1])&DEV_$($matches[2])"
                    Write-Host "   Extracted Hardware ID: $hardwareId" -ForegroundColor Gray

                    # Apply patch to all possible registry locations
                    foreach ($adapter in $nvidiaAdapters) {
                        Write-Host "   Applying patch to: $($adapter.AdapterName)" -ForegroundColor Cyan

                        try {
                            Set-ItemProperty -Path "HKLM:\$($adapter.DeviceKey)" -Name $NV_KEY -Value $NV_KEY_DATA -Type $NV_KEY_TYPE -Force
                            Write-Host "   Registry patch applied to: $($adapter.DeviceKey)" -ForegroundColor Green
                            $script:NV_FIXED = $true
                        }
                        catch {
                            Write-Host "   Failed to patch: $($adapter.DeviceKey) - $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Host "   ERROR: Failed to scan NVIDIA devices: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Show results
if ($script:NV_FIXED) {
    Write-Host ""
    Write-Host "  Registry changes have been made. Note: " -ForegroundColor Green
    Write-Host ""
    Write-Host "    1. RE-RUN this script if you delete or reinstall this GPU & error code 43 reappears."
    Write-Host "    2. To UNDO this change, uninstall the adapter in Device Manager->Display adapters & restart."
    Write-Host ""
    Write-Host "  Please consider a thank you PayPal donation to nando4eva@ymail.com. Thank you." -ForegroundColor Cyan

    Write-Host ""
    Write-Host ".  $PRESS_KEY" -NoNewline
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

if ($nvidiaAdapters.Count -eq 0) {
    Write-Host "   $NO_NV_GPUS" -ForegroundColor Yellow
    Write-Host ""
    Write-Host ".  $PRESS_KEY" -NoNewline
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

if (-not $script:NV_ERR43_FOUND) {
    Write-Host "   $NO_NV_ERROR43_GPUS" -ForegroundColor Green
    Write-Host ""
    Write-Host ".  $PRESS_KEY" -NoNewline
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# If we get here, error 43 was detected but not fixed
Write-Host ""
Write-Host "  $MORE_EGPUIO_FIXES" -NoNewline
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Start-Process $EGPUIO_FIXES_URL

Write-Host ""
