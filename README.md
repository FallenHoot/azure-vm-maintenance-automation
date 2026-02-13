# Azure VM Maintenance Automation

> **DISCLAIMER**  
> This script is provided as sample guidance only and is not a supported Microsoft product. It is provided "AS IS", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. Microsoft and the author(s) are not liable for any damages arising from the use of this code. Review and test in a non-production environment before use.

**Set it and forget it.** This Azure Automation solution automatically starts deallocated VMs before scheduled maintenance windows and stops them afterward. Once deployed, it runs on schedule without manual intervention.

## How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│  3rd Sunday of Each Month                                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  06:00 ─► PreMaintenance Runbook                                │
│           • Scans all subscriptions for deallocated VMs         │
│           • Filters VMs by name pattern or tag                  │
│           • Starts matching VMs                                 │
│           • Saves state to Azure Blob Storage                   │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │         Maintenance Window (VMs Running)               │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  22:00 ─► PostMaintenance Runbook                               │
│           • Reads state file from Blob Storage                  │
│           • Stops only the VMs that were started                │
│           • Cleans up state file                                │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Configure Your Settings

Edit [infra/main.bicepparam](infra/main.bicepparam) **before deployment**:

```bicep
// Storage account for state persistence (must exist)
param storageAccountName = 'yourstorageaccount'
param storageAccountRG = 'your-storage-rg'

// Schedule times (24-hour format)
param preMaintenanceTimePRE = '06:00'   // When to start VMs
param postMaintenanceTimePRE = '22:00'  // When to stop VMs

// Time zone
param timeZone = 'America/Chicago'

// Runbook style: 'Separate' (4 runbooks) or 'Combined' (2 runbooks)
param runbookStyle = 'Separate'
```

### 2. Configure VM Filtering

Choose how VMs are identified. Edit the default values in the runbook files **before deployment**:

**Option A: Filter by VM Name** (default)
```powershell
# In PreMaintenance-PRE.ps1 / PreMaintenance-PRD.ps1
$NamePattern = "PRE"    # Matches VMs with "PRE" in the name
$NamePattern = "PRD"    # Matches VMs with "PRD" in the name

# Regex examples:
$NamePattern = "^YOURPREFIX"     # Starts with YOURPREFIX
$NamePattern = "-prod$"          # Ends with -prod
$NamePattern = "^(APP|WEB|DB)"   # Starts with APP, WEB, or DB
```

**Option B: Filter by Azure Tag**
```powershell
# In PreMaintenance-PRE.ps1 / PreMaintenance-PRD.ps1
$FilterBy = "Tag"
$TagName = "env"
$TagValue = "pre"       # or "prod", "dev", etc.

# Common tag strategies:
$TagName = "MaintenanceWindow"
$TagValue = "Sunday-0600"

$TagName = "PatchGroup"
$TagValue = "Group1"
```

### 3. Deploy

```powershell
git clone https://github.com/FallenHoot/azure-vm-maintenance-automation.git
cd azure-vm-maintenance-automation

# Deploy (choose one style)
.\scripts\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus"

# Or for combined runbooks
.\scripts\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus" -RunbookStyle "Combined"
```

### 4. Assign Roles to Additional Subscriptions

If VMs span multiple subscriptions, assign the Managed Identity to each:

```powershell
# Get the Principal ID from deployment output, then:
$principalId = "<from-deployment-output>"
$subscriptionIds = @("sub-1", "sub-2", "sub-3")

foreach ($subId in $subscriptionIds) {
    New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Virtual Machine Contributor" -Scope "/subscriptions/$subId"
    New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Reader" -Scope "/subscriptions/$subId"
}
```

### 5. Test Before Production (Required)

⚠️ **Always validate your configuration before relying on scheduled execution.**

**Step 1: DryRun Test**
```powershell
# In Azure Portal: Automation Account → Runbooks → PreMaintenance-PRE → Start
# Set parameter: DryRun = true
```

Review the job output to confirm the correct VMs are being targeted:
- Check "VMs to start" list matches your expectations
- Verify no unexpected VMs are included
- Confirm storage account connectivity works

**Step 2: Live Test (Non-Production)**

Run against PRE/non-production VMs first with DryRun = false:
```powershell
# Start PRE VMs
Start-AzAutomationRunbook -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" -Name "PreMaintenance-PRE"

# Wait, verify VMs started, then stop them
Start-AzAutomationRunbook -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" -Name "PostMaintenance-PRE"
```

**Step 3: Verify Results**
- Confirm VMs started and stopped as expected
- Check state file was created and deleted in storage container
- Review job output for any warnings

### 6. Done!

Once testing is successful, the runbooks will automatically execute on the 3rd Sunday of each month.

## Configuration Reference

### Runbook Defaults

| Setting | PRE Runbook | PRD Runbook | Description |
|---------|-------------|-------------|-------------|
| `FilterBy` | `Name` | `Name` | `Name` or `Tag` |
| `NamePattern` | `PRE` | `PRD` | Regex to match VM names |
| `TagName` | `env` | `env` | Tag key (if FilterBy=Tag) |
| `TagValue` | `pre` | `prod` | Tag value (if FilterBy=Tag) |
| `StorageAccountName` | `patchingvmlist` | `patchingvmlist` | State storage |
| `StorageAccountRG` | `CAP-TST-01` | `CAP-TST-01` | Storage RG |
| `ContainerName` | `vm-maintenance` | `vm-maintenance` | Blob container |

### Schedule Configuration

| Schedule | Time | Purpose |
|----------|------|---------|
| PreMaintenance-PRE | 06:00 (3rd Sunday) | Start PRE VMs |
| PreMaintenance-PRD | 06:00 (3rd Sunday) | Start PRD VMs |
| PostMaintenance-PRE | 22:00 (3rd Sunday) | Stop PRE VMs |
| PostMaintenance-PRD | 22:00 (3rd Sunday) | Stop PRD VMs |

### Required Role Assignments

| Role | Scope | Purpose |
|------|-------|---------|
| Virtual Machine Contributor | Each subscription with VMs | Start/Stop VMs |
| Reader | Each subscription with VMs | List VMs |
| Storage Blob Data Contributor | Storage account | State persistence |

## Excluding VMs from Automation

To permanently exclude a VM, ensure it doesn't match your filter:

- **Name filter**: Rename VM or change `NamePattern`
- **Tag filter**: Remove the tag or change its value

To temporarily exclude a VM for one maintenance window, ensure it's **running** (not deallocated) before the PreMaintenance runbook executes.

## Monitoring

View job history in Azure Portal:
**Automation Account → Jobs → Select job → Output**

Or enable diagnostic settings to send logs to Log Analytics for long-term monitoring.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Automation Account                      │
├─────────────────────────────────────────────────────────────────┤
│  Runbooks:                        Schedules:                    │
│  ┌──────────────────────┐        ┌──────────────────────────┐  │
│  │ PreMaintenance-PRE   │◄───────│ 3rd Sunday 06:00         │  │
│  │ PreMaintenance-PRD   │◄───────│ 3rd Sunday 06:00         │  │
│  │ PostMaintenance-PRE  │◄───────│ 3rd Sunday 22:00         │  │
│  │ PostMaintenance-PRD  │◄───────│ 3rd Sunday 22:00         │  │
│  └──────────────────────┘        └──────────────────────────┘  │
│                                                                  │
│  System-Assigned Managed Identity                               │
│  └─► Authenticates to Azure (no credentials stored)            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Storage Account                         │
│  Container: vm-maintenance                                       │
│  └─► PRE-started-vms-2026-02-15-060000.json (auto-deleted)     │
│  └─► PRD-started-vms-2026-02-15-060000.json (auto-deleted)     │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
├── runbooks/
│   ├── PreMaintenance-PRE.ps1        # Edit defaults before deployment
│   ├── PreMaintenance-PRD.ps1        # Edit defaults before deployment
│   ├── PostMaintenance-PRE.ps1
│   ├── PostMaintenance-PRD.ps1
│   ├── PreMaintenance-Combined.ps1   # Alternative: single runbook
│   └── PostMaintenance-Combined.ps1  # Alternative: single runbook
├── infra/
│   ├── main.bicep                    # Infrastructure as Code
│   ├── main.bicepparam               # ← Edit this before deployment
│   └── role-assignments.bicep
├── scripts/
│   └── Deploy-Automation.ps1
└── README.md
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| No VMs started | Filter doesn't match | Verify `NamePattern` or `TagName`/`TagValue` in runbook |
| Storage account not found | Wrong name or no access | Check `StorageAccountName` and role assignments |
| VMs not stopping | State file missing | Check storage container for state files |
| Job failed | Managed Identity permissions | Assign VM Contributor to all target subscriptions |

## Technical Details

- **PowerShell 7.2** runtime
- **Managed Identity** authentication (no credentials)
- **Parallel execution** with `-NoWait` for performance
- **Idempotent** - safe to run multiple times
- **Multi-subscription** - scans all enabled subscriptions

**Required Az Modules**: `Az.Accounts`, `Az.Compute`, `Az.Storage`

## License

MIT License
