<#
.SYNOPSIS
    Post-Maintenance runbook for PRD environment. Stops VMs that were started before maintenance.
.DESCRIPTION
    Zero-touch runbook - all configuration is hardcoded below. Edit values before deployment.
    Runs on schedule without any manual input. Reads state file from PreMaintenance run.
    Pass -DryRun $true to preview what VMs would be stopped without making changes.
#>

param (
    [bool]$DryRun = $false
)

# ============================================================================
# CONFIGURATION - Edit these values before deployment (must match PreMaintenance)
# ============================================================================
$Environment = "PRD"
$StorageAccountName = "patchingvmlist"
$StorageAccountRG = "CAP-TST-01"
$ContainerName = "vm-maintenance"
$DeleteStateFile = $false
# ============================================================================

if ($DryRun) { Write-Output "[DRY RUN] Mode enabled - no VMs will be stopped, state file preserved" }

$ErrorActionPreference = "Stop"
$null = Disable-AzContextAutosave -Scope Process

try {
    $AzureConnection = (Connect-AzAccount -Identity).context
    Write-Output "Connected: $($AzureConnection.Subscription.Name)"
} catch {
    throw "Managed Identity connection failed: $($_.Exception.Message)"
}

$AzureContext = Set-AzContext -SubscriptionName $AzureConnection.Subscription -DefaultProfile $AzureConnection

# Find storage account
$storageAccount = $null
$subscriptions = Get-AzSubscription -DefaultProfile $AzureContext | Where-Object { $_.State -eq "Enabled" }

foreach ($sub in $subscriptions) {
    try {
        Set-AzContext -SubscriptionId $sub.Id -DefaultProfile $AzureContext | Out-Null
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $StorageAccountName -DefaultProfile $AzureContext -ErrorAction SilentlyContinue
        if ($storageAccount) { break }
    } catch { continue }
}

if (-not $storageAccount) { throw "Storage account '$StorageAccountName' not found in resource group '$StorageAccountRG'" }

$ctx = $storageAccount.Context

# Find latest state file for this environment
$blobPattern = "$Environment-started-vms-*.json"
$blob = Get-AzStorageBlob -Container $ContainerName -Context $ctx -DefaultProfile $AzureContext |
    Where-Object { $_.Name -like $blobPattern } |
    Sort-Object LastModified -Descending |
    Select-Object -First 1

if (-not $blob) {
    Write-Output "No state file found for $Environment - nothing to stop"
    return
}

Write-Output "State file: $($blob.Name)"

# Download and parse state file
$tempFile = [System.IO.Path]::GetTempFileName()
try {
    Get-AzStorageBlobContent -Container $ContainerName -Blob $blob.Name -Destination $tempFile -Context $ctx -DefaultProfile $AzureContext -Force | Out-Null
    $stateData = Get-Content $tempFile -Raw | ConvertFrom-Json
} finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

$startedVMs = @($stateData.VMs | Where-Object { $_.Status -eq "Started" })

if ($startedVMs.Count -eq 0) {
    Write-Output "No VMs to stop"
    return
}

Write-Output "VMs to stop: $($startedVMs.Count)"

# Build subscription lookup
$subs = @{}
foreach ($sub in $subscriptions) {
    $subs[$sub.Name] = $sub.Id
}

$stoppedCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($vm in $startedVMs) {
    $subId = $subs[$vm.SubscriptionName]
    if (-not $subId) {
        Write-Warning "Subscription not found: $($vm.SubscriptionName)"
        $skippedCount++
        continue
    }

    try {
        Set-AzContext -SubscriptionId $subId -DefaultProfile $AzureContext | Out-Null
        $currentVM = Get-AzVM -Name $vm.VMName -Status -DefaultProfile $AzureContext -ErrorAction SilentlyContinue

        if (-not $currentVM) {
            Write-Warning "VM not found: $($vm.VMName)"
            $skippedCount++
            continue
        }

        if ($currentVM.PowerState -eq "VM deallocated") {
            Write-Output "Already stopped: $($vm.VMName)"
            $skippedCount++
            continue
        }

        if ($DryRun) {
            Write-Output "[DRY RUN] Would stop: $($vm.VMName)"
        } else {
            Stop-AzVM -Name $vm.VMName -ResourceGroupName $currentVM.ResourceGroupName -Force -NoWait -DefaultProfile $AzureContext | Out-Null
            Write-Output "Stopping: $($vm.VMName)"
        }
        $stoppedCount++
    } catch {
        Write-Warning "Failed: $($vm.VMName) - $($_.Exception.Message)"
        $failedCount++
    }
}

# Clean up state file
if ($DeleteStateFile -and -not $DryRun) {
    Remove-AzStorageBlob -Container $ContainerName -Blob $blob.Name -Context $ctx -DefaultProfile $AzureContext -Force
    Write-Output "State file deleted"
}

$prefix = if ($DryRun) { "[DRY RUN] " } else { "" }
Write-Output "=== ${prefix}SUMMARY: $Environment | Stopped: $stoppedCount | Skipped: $skippedCount | Failed: $failedCount ==="
