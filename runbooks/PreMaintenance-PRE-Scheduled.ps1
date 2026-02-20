<#
.SYNOPSIS
    Pre-Maintenance runbook for PRE environment. Starts deallocated VMs before maintenance window.
.DESCRIPTION
    Zero-touch runbook - all configuration is hardcoded below. Edit values before deployment.
    Runs on schedule without any manual input.
    Pass -DryRun $true to preview what VMs would be started without making changes.
#>

param (
    [bool]$DryRun = $false
)

# ============================================================================
# CONFIGURATION - Edit these values before deployment
# ============================================================================
$Environment = "PRE"
$StorageAccountName = "patchingvmlist"
$StorageAccountRG = "CAP-TST-01"
$ContainerName = "vm-maintenance"

# Filter options: "Name" or "Tag"
$FilterBy = "Name"

# If FilterBy = "Name": Regex pattern to match VM names
$NamePattern = "PRE"

# If FilterBy = "Tag": Tag key and value to match
$TagName = "env"
$TagValue = "pre"
# ============================================================================

if ($DryRun) { Write-Output "[DRY RUN] Mode enabled - no VMs will be started, no state file saved" }

$ErrorActionPreference = "Stop"
$null = Disable-AzContextAutosave -Scope Process

try {
    $AzureConnection = (Connect-AzAccount -Identity).context
    Write-Output "Connected: $($AzureConnection.Subscription.Name)"
} catch {
    throw "Managed Identity connection failed: $($_.Exception.Message)"
}

$AzureContext = Set-AzContext -SubscriptionName $AzureConnection.Subscription -DefaultProfile $AzureConnection

$allVMs = @()
$subscriptions = Get-AzSubscription -DefaultProfile $AzureContext | Where-Object { $_.State -eq "Enabled" }

foreach ($sub in $subscriptions) {
    try {
        Set-AzContext -SubscriptionId $sub.Id -DefaultProfile $AzureContext | Out-Null
        foreach ($vm in (Get-AzVM -Status -DefaultProfile $AzureContext)) {
            $allVMs += @{
                Name = $vm.Name
                ResourceGroup = $vm.ResourceGroupName
                SubscriptionId = $sub.Id
                SubscriptionName = $sub.Name
                PowerState = $vm.PowerState
                Tags = $vm.Tags
            }
        }
    } catch {
        Write-Warning "Scan failed for $($sub.Name): $($_.Exception.Message)"
    }
}

Write-Output "Scanned: $($allVMs.Count) VMs"

$deallocatedVMs = @($allVMs | Where-Object { $_.PowerState -eq "VM deallocated" })

if ($FilterBy -eq "Name") {
    $filteredVMs = @($deallocatedVMs | Where-Object { $_.Name -match $NamePattern })
} else {
    $filteredVMs = @($deallocatedVMs | Where-Object {
        $t = $_.Tags
        if (-not $t) { return $false }
        $k = $t.Keys | Where-Object { $_ -ieq $TagName } | Select-Object -First 1
        if ($k) { $t[$k] -eq $TagValue } else { $false }
    })
}

Write-Output "Deallocated: $($deallocatedVMs.Count) | Filtered ($FilterBy): $($filteredVMs.Count)"

if ($filteredVMs.Count -eq 0) {
    Write-Output "No matching VMs to start"
    return
}

$startedVMs = @()
$failedVMs = @()

foreach ($vm in $filteredVMs) {
    try {
        Set-AzContext -SubscriptionId $vm.SubscriptionId -DefaultProfile $AzureContext | Out-Null
        if ($DryRun) {
            Write-Output "[DRY RUN] Would start: $($vm.Name) in $($vm.ResourceGroup)"
        } else {
            Start-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroup -NoWait -DefaultProfile $AzureContext | Out-Null
            Write-Output "Starting: $($vm.Name)"
        }
        $startedVMs += @{
            SubscriptionName = $vm.SubscriptionName
            VMName = $vm.Name
            ResourceGroup = $vm.ResourceGroup
            Status = "Started"
        }
    } catch {
        Write-Warning "Failed: $($vm.Name) - $($_.Exception.Message)"
        $failedVMs += @{
            SubscriptionName = $vm.SubscriptionName
            VMName = $vm.Name
            ResourceGroup = $vm.ResourceGroup
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
}

# Save state to blob storage (skip in DryRun mode)
if ($DryRun) {
    Write-Output "[DRY RUN] Skipping state file save"
    Write-Output "=== [DRY RUN] SUMMARY: $Environment | Would start: $($startedVMs.Count) | Failed: $($failedVMs.Count) ==="
    return
}

$storageAccount = $null
foreach ($sub in $subscriptions) {
    try {
        Set-AzContext -SubscriptionId $sub.Id -DefaultProfile $AzureContext | Out-Null
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $StorageAccountName -DefaultProfile $AzureContext -ErrorAction SilentlyContinue
        if ($storageAccount) { break }
    } catch { continue }
}

if (-not $storageAccount) { throw "Storage account '$StorageAccountName' not found in resource group '$StorageAccountRG'" }

$ctx = $storageAccount.Context

if (-not (Get-AzStorageContainer -Name $ContainerName -Context $ctx -DefaultProfile $AzureContext -ErrorAction SilentlyContinue)) {
    New-AzStorageContainer -Name $ContainerName -Context $ctx -DefaultProfile $AzureContext -Permission Off | Out-Null
    Write-Output "Created container: $ContainerName"
}

$stateData = @{
    Environment = $Environment
    FilterBy = $FilterBy
    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    TotalScanned = $allVMs.Count
    TotalStarted = $startedVMs.Count
    TotalFailed = $failedVMs.Count
    VMs = ($startedVMs + $failedVMs)
}

$blobName = "$Environment-started-vms-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$tempFile = [System.IO.Path]::GetTempFileName()

try {
    $stateData | ConvertTo-Json -Depth 5 | Out-File $tempFile -Encoding UTF8
    Set-AzStorageBlobContent -File $tempFile -Container $ContainerName -Blob $blobName -Context $ctx -DefaultProfile $AzureContext -Force | Out-Null
} finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Output "=== SUMMARY: $Environment | Started: $($startedVMs.Count) | Failed: $($failedVMs.Count) | State: $blobName ==="
