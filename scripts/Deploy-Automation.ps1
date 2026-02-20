<#
.SYNOPSIS
    Deploys Azure Automation infrastructure and uploads runbooks.

.DESCRIPTION
    Deploys the Azure Automation Account using Bicep, uploads runbook scripts,
    and configures role assignments. Supports three runbook styles:

    - Scheduled (default): Zero-touch. Config hardcoded in scripts. No manual input needed.
    - Separate: 4 parameterized runbooks. Storage config passed via Bicep job schedules.
    - Combined: 2 runbooks with -Environment param. Config passed via Bicep job schedules.

.PARAMETER ResourceGroupName
    The resource group to deploy into.

.PARAMETER Location
    Azure region for the deployment.

.PARAMETER RunbookStyle
    Deployment style: 'Scheduled' (default), 'Separate', or 'Combined'.

.PARAMETER SubscriptionId
    Target subscription ID for role assignments.

.EXAMPLE
    # Zero-touch (default) - works out of the box for Azure Automation
    .\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus"

.EXAMPLE
    # Parameterized separate runbooks
    .\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus" -RunbookStyle "Separate"

.EXAMPLE
    # Combined runbooks with -Environment parameter
    .\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus" -RunbookStyle "Combined"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "centralus",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Scheduled", "Separate", "Combined")]
    [string]$RunbookStyle = "Scheduled",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = ""
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraPath = Join-Path $scriptPath "..\infra"
$runbooksPath = Join-Path $scriptPath "..\runbooks"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VM Maintenance Automation Deployment" -ForegroundColor Cyan
Write-Host "  Style: $RunbookStyle" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ============================================================================
# Step 1: Ensure Resource Group Exists
# ============================================================================
Write-Host "`n[1/5] Checking resource group..." -ForegroundColor Yellow

$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Creating resource group: $ResourceGroupName in $Location"
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
}
Write-Host "Resource group ready: $ResourceGroupName" -ForegroundColor Green

# ============================================================================
# Step 2: Deploy Bicep Infrastructure
# ============================================================================
Write-Host "`n[2/5] Deploying Bicep infrastructure..." -ForegroundColor Yellow

$bicepFile = Join-Path $infraPath "main.bicep"
$paramFile = Join-Path $infraPath "main.bicepparam"
$deploymentName = "vm-maintenance-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deploymentParams = @{
    ResourceGroupName = $ResourceGroupName
    TemplateFile      = $bicepFile
    Name              = $deploymentName
    runbookStyle      = $RunbookStyle
}

if (Test-Path $paramFile) {
    $deploymentParams.TemplateParameterFile = $paramFile
}

$deployment = New-AzResourceGroupDeployment @deploymentParams

if ($deployment.ProvisioningState -ne "Succeeded") {
    throw "Deployment failed: $($deployment.ProvisioningState)"
}

Write-Host "Infrastructure deployed successfully" -ForegroundColor Green

$principalId = $deployment.Outputs.managedIdentityPrincipalId.Value
$automationAccountName = $deployment.Outputs.automationAccountName.Value

Write-Host "  Automation Account: $automationAccountName"
Write-Host "  Managed Identity Principal ID: $principalId"
Write-Host "  Runbook Style: $RunbookStyle"

# ============================================================================
# Step 3: Upload Runbook Content
# ============================================================================
Write-Host "`n[3/5] Uploading runbook scripts..." -ForegroundColor Yellow

switch ($RunbookStyle) {
    "Scheduled" {
        $runbooks = @(
            @{ Name = "PreMaintenance-PRE"; File = "PreMaintenance-PRE-Scheduled.ps1" },
            @{ Name = "PreMaintenance-PRD"; File = "PreMaintenance-PRD-Scheduled.ps1" },
            @{ Name = "PostMaintenance-PRE"; File = "PostMaintenance-PRE-Scheduled.ps1" },
            @{ Name = "PostMaintenance-PRD"; File = "PostMaintenance-PRD-Scheduled.ps1" }
        )
    }
    "Separate" {
        $runbooks = @(
            @{ Name = "PreMaintenance-PRE"; File = "PreMaintenance-PRE.ps1" },
            @{ Name = "PreMaintenance-PRD"; File = "PreMaintenance-PRD.ps1" },
            @{ Name = "PostMaintenance-PRE"; File = "PostMaintenance-PRE.ps1" },
            @{ Name = "PostMaintenance-PRD"; File = "PostMaintenance-PRD.ps1" }
        )
    }
    "Combined" {
        $runbooks = @(
            @{ Name = "PreMaintenance-Combined"; File = "PreMaintenance-Combined.ps1" },
            @{ Name = "PostMaintenance-Combined"; File = "PostMaintenance-Combined.ps1" }
        )
    }
}

foreach ($runbook in $runbooks) {
    $runbookFile = Join-Path $runbooksPath $runbook.File

    if (-not (Test-Path $runbookFile)) {
        Write-Warning "Runbook file not found: $runbookFile"
        continue
    }

    Write-Host "  Uploading: $($runbook.Name) ← $($runbook.File)"

    Import-AzAutomationRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $automationAccountName `
        -Name $runbook.Name `
        -Path $runbookFile `
        -Type PowerShell72 `
        -Force | Out-Null

    Publish-AzAutomationRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $automationAccountName `
        -Name $runbook.Name | Out-Null

    Write-Host "    Published: $($runbook.Name)" -ForegroundColor Green
}

# ============================================================================
# Step 4: Configure Role Assignments
# ============================================================================
Write-Host "`n[4/5] Configuring role assignments..." -ForegroundColor Yellow

if (-not $SubscriptionId) {
    $SubscriptionId = (Get-AzContext).Subscription.Id
}

$roles = @(
    @{ Name = "Virtual Machine Contributor"; Id = "9980e02c-c2be-4d73-94e8-173b1dc7cf3c" },
    @{ Name = "Reader"; Id = "acdd72a7-3385-48ef-bd42-f606fba81ae7" },
    @{ Name = "Storage Blob Data Contributor"; Id = "ba92f5b4-2d11-453d-a403-e96b0029c9fe" }
)

foreach ($role in $roles) {
    Write-Host "  Assigning: $($role.Name)"

    try {
        $existing = Get-AzRoleAssignment `
            -ObjectId $principalId `
            -RoleDefinitionId $role.Id `
            -Scope "/subscriptions/$SubscriptionId" `
            -ErrorAction SilentlyContinue

        if ($existing) {
            Write-Host "    Already assigned" -ForegroundColor Yellow
        } else {
            New-AzRoleAssignment `
                -ObjectId $principalId `
                -RoleDefinitionId $role.Id `
                -Scope "/subscriptions/$SubscriptionId" | Out-Null
            Write-Host "    Assigned" -ForegroundColor Green
        }
    } catch {
        Write-Warning "    Failed: $($_.Exception.Message)"
    }
}

# ============================================================================
# Step 5: Verify Deployment
# ============================================================================
Write-Host "`n[5/5] Verifying deployment..." -ForegroundColor Yellow

$aa = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $automationAccountName
$publishedRunbooks = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $automationAccountName | Where-Object { $_.State -eq "Published" }
$schedules = Get-AzAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $automationAccountName

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Automation Account: $($aa.AutomationAccountName)"
Write-Host "Location: $($aa.Location)"
Write-Host "Identity Type: $($aa.Identity.Type)"
Write-Host "Runbook Style: $RunbookStyle"
Write-Host "Published Runbooks: $($publishedRunbooks.Count)"
foreach ($rb in $publishedRunbooks) {
    Write-Host "  - $($rb.Name)"
}
Write-Host "Schedules: $($schedules.Count)"
foreach ($sch in $schedules) {
    Write-Host "  - $($sch.Name): $($sch.Frequency) at $($sch.StartTime)"
}
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nDeployment completed successfully!" -ForegroundColor Green

switch ($RunbookStyle) {
    "Scheduled" {
        Write-Host "`nZero-Touch Operation:" -ForegroundColor Yellow
        Write-Host "  - Runbooks execute automatically on the 3rd Sunday of each month"
        Write-Host "  - No manual input required"
        Write-Host "  - Configuration is hardcoded in the *-Scheduled.ps1 scripts"
    }
    "Separate" {
        Write-Host "`nParameterized Operation:" -ForegroundColor Yellow
        Write-Host "  - Runbooks accept parameters for storage config and DryRun"
        Write-Host "  - Job schedules pass storage configuration from Bicep params"
        Write-Host "  - Override defaults by editing runbook parameters or Bicep params"
    }
    "Combined" {
        Write-Host "`nCombined Operation:" -ForegroundColor Yellow
        Write-Host "  - 2 runbooks handle both PRE and PRD via -Environment parameter"
        Write-Host "  - Job schedules pass Environment and storage config from Bicep params"
        Write-Host "  - Override defaults by editing Bicep params"
    }
}

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. If VMs span multiple subscriptions, assign roles to each subscription"
Write-Host "2. Test runbooks manually before the first scheduled maintenance window"
