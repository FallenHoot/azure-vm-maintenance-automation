param (
    [string]$StorageAccountName = "autopatchingvmlist",
    [string]$StorageAccountRG = "Patching-Automation",
    [string]$ContainerName = "vm-maintenance",
    [string]$StateFileName = "",
    [bool]$DeleteStateFile = $false,
    [bool]$DryRun = $false,
    [string]$ScheduleTimeZone = "Europe/Amsterdam"
)
$Environment = "PRD"

# --- 3rd Sunday gate (uses schedule timezone, not UTC) ---
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($ScheduleTimeZone)
$today = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tz)
Write-Output "Schedule timezone: $($tz.DisplayName) | Local time: $($today.ToString('yyyy-MM-dd HH:mm:ss dddd'))"
$weekOfMonth = [math]::Ceiling($today.Day / 7)
if ($today.DayOfWeek -ne 'Sunday') {
    Write-Output "Today is $($today.DayOfWeek), not Sunday. Exiting."
    return
}
if ($weekOfMonth -ne 3) {
    Write-Output "Today is Sunday week $weekOfMonth, not the 3rd Sunday. Exiting."
    return
}
Write-Output "3rd Sunday confirmed - proceeding with $Environment maintenance."

$ErrorActionPreference = "Stop"
$null = Disable-AzContextAutosave -Scope Process
try {
    $AzureConnection = (Connect-AzAccount -Identity).context
    Write-Output "Connected: $($AzureConnection.Subscription.Name)"
} catch {
    throw "Managed Identity connection failed: $($_.Exception.Message)"
}
$AzureContext = Set-AzContext -SubscriptionName $AzureConnection.Subscription -DefaultProfile $AzureConnection

$storageAccount = $null
$subscriptions = Get-AzSubscription -DefaultProfile $AzureContext | Where-Object { $_.State -eq "Enabled" }
foreach ($sub in $subscriptions) {
    try {
        Set-AzContext -SubscriptionId $sub.Id -DefaultProfile $AzureContext | Out-Null
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $StorageAccountName -DefaultProfile $AzureContext -ErrorAction SilentlyContinue
        if ($storageAccount) { break }
    } catch { continue }
}
if (-not $storageAccount) { throw "Storage account not found" }
$ctx = $storageAccount.Context

$blobPattern = "$Environment-vm-state-live-*.json"
if ($StateFileName) {
    $blob = Get-AzStorageBlob -Container $ContainerName -Blob $StateFileName -Context $ctx -DefaultProfile $AzureContext -ErrorAction Stop
} else {
    $blob = Get-AzStorageBlob -Container $ContainerName -Context $ctx -DefaultProfile $AzureContext | Where-Object { $_.Name -like $blobPattern } | Sort-Object LastModified -Descending | Select-Object -First 1
    if (-not $blob) { Write-Output "No state file found"; return }
}
Write-Output "State file: $($blob.Name)"

$tempFile = [System.IO.Path]::GetTempFileName()
try {
    Get-AzStorageBlobContent -Container $ContainerName -Blob $blob.Name -Destination $tempFile -Context $ctx -DefaultProfile $AzureContext -Force | Out-Null
    $stateData = Get-Content $tempFile -Raw | ConvertFrom-Json
} finally { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }

$startedVMs = @($stateData.VMs | Where-Object { $_.Status -in @("Started", "WouldStart") })
if ($startedVMs.Count -eq 0) { Write-Output "No VMs to stop"; return }
Write-Output "VMs to stop: $($startedVMs.Count)"

$subs = @{}; foreach ($sub in $subscriptions) { $subs[$sub.Name] = $sub.Id }
$stoppedCount = 0; $skippedCount = 0; $failedCount = 0

foreach ($vm in $startedVMs) {
    $subId = $subs[$vm.SubscriptionName]
    if (-not $subId) { Write-Warning "Sub not found: $($vm.SubscriptionName)"; $skippedCount++; continue }
    try {
        Set-AzContext -SubscriptionId $subId -DefaultProfile $AzureContext | Out-Null
        $currentVM = Get-AzVM -Name $vm.VMName -Status -DefaultProfile $AzureContext -ErrorAction SilentlyContinue
        if (-not $currentVM) { Write-Warning "VM not found: $($vm.VMName)"; $skippedCount++; continue }
        if ($currentVM.PowerState -eq "VM deallocated") { Write-Output "Already stopped: $($vm.VMName)"; $skippedCount++; continue }
        if ($DryRun) {
            Write-Output "[DryRun] Would stop: $($vm.VMName)"; $stoppedCount++
        } else {
            Stop-AzVM -Name $vm.VMName -ResourceGroupName $currentVM.ResourceGroupName -Force -NoWait -DefaultProfile $AzureContext | Out-Null
            Write-Output "Stopping: $($vm.VMName)"; $stoppedCount++
        }
    } catch { Write-Warning "Failed: $($vm.VMName) - $($_.Exception.Message)"; $failedCount++ }
}

if (-not $DryRun -and $DeleteStateFile) {
    Remove-AzStorageBlob -Container $ContainerName -Blob $blob.Name -Context $ctx -DefaultProfile $AzureContext -Force
    Write-Output "State file deleted"
}

Write-Output "=== SUMMARY: $Environment | Stopped:$stoppedCount Skipped:$skippedCount Failed:$failedCount ==="
