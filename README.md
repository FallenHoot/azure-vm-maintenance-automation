# Azure VM Maintenance Automation

> **DISCLAIMER**  
> This script is provided as sample guidance only and is not a supported Microsoft product. It is provided "AS IS", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. Microsoft and the author(s) are not liable for any damages arising from the use of this code. Review and test in a non-production environment before use.

Automatically starts deallocated VMs before scheduled maintenance windows and stops them afterward. Supports three deployment styles to fit your needs.

## How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│  3rd Sunday of Each Month (Automatic)                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  06:00 ─► PreMaintenance Runbook                                │
│           • Scans all subscriptions for deallocated VMs         │
│           • Filters by name pattern or tag                      │
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

## Choose Your Style

| Style | Files | Configuration | Best For |
|-------|-------|--------------|----------|
| **Scheduled** (default) | 4 `*-Scheduled.ps1` | Hardcoded in script | Azure Automation set-and-forget |
| **Separate** | 4 `*-PRE/PRD.ps1` | Parameters with defaults | Flexible, reusable runbooks |
| **Combined** | 2 `*-Combined.ps1` | `-Environment` parameter | Fewer runbooks to manage |

---

## Option A: Scheduled (Zero-Touch) — Recommended

**Works out of the box for Azure Automation.** Configure once, deploy, forget.

### Step 1: Edit Configuration in Scheduled Runbook Scripts

Edit the `CONFIGURATION` section at the top of each `*-Scheduled.ps1` file:

```powershell
# ============================================================================
# CONFIGURATION - Edit these values before deployment
# ============================================================================
$Environment = "PRE"
$StorageAccountName = "yourstorageaccount"    # ← Change this
$StorageAccountRG = "your-storage-rg"          # ← Change this
$ContainerName = "vm-maintenance"
$FilterBy = "Name"
$NamePattern = "PRE"                           # ← Change to match your VMs
$TagName = "env"
$TagValue = "pre"
# ============================================================================
```

Edit all 4 scheduled runbook files:
- `PreMaintenance-PRE-Scheduled.ps1` — PRE environment
- `PreMaintenance-PRD-Scheduled.ps1` — PRD environment
- `PostMaintenance-PRE-Scheduled.ps1` — Must match Pre storage settings
- `PostMaintenance-PRD-Scheduled.ps1` — Must match Pre storage settings

### Step 2: Deploy

```powershell
.\scripts\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus"
```

### Step 3: Test and Done

1. Go to Automation Account → Runbooks → PreMaintenance-PRE → Start
2. Review output, verify correct VMs targeted
3. Run PostMaintenance-PRE to stop them
4. Runbooks now execute automatically on the 3rd Sunday. No further action needed.

---

## Option B: Separate (Parameterized)

**4 individual runbooks with `param()` blocks.** Storage config passed via Bicep job schedules or overridden at runtime.

### Step 1: Edit Bicep Parameters

Edit [infra/main.bicepparam](infra/main.bicepparam):

```bicep
param runbookStyle = 'Separate'
param storageAccountName = 'yourstorageaccount'
param storageAccountRG = 'your-storage-rg'
```

### Step 2: Deploy

```powershell
.\scripts\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus" -RunbookStyle "Separate"
```

### Step 3: Customize (Optional)

You can override parameters when running manually:
```powershell
Start-AzAutomationRunbook -Name "PreMaintenance-PRE" `
  -Parameters @{ FilterBy = "Tag"; TagName = "env"; TagValue = "pre"; DryRun = $true } `
  -ResourceGroupName "rg-automation" -AutomationAccountName "aa-vm-maintenance"
```

---

## Option C: Combined

**2 runbooks handle both PRE and PRD** via the `-Environment` parameter. Fewer runbooks to manage.

### Step 1: Edit Bicep Parameters

```bicep
param runbookStyle = 'Combined'
param storageAccountName = 'yourstorageaccount'
param storageAccountRG = 'your-storage-rg'
```

### Step 2: Deploy

```powershell
.\scripts\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus" -RunbookStyle "Combined"
```

---

## Post-Deployment (All Styles)

### Assign Roles to Additional Subscriptions

If VMs span multiple subscriptions:

```powershell
$principalId = "<from-deployment-output>"
$subscriptionIds = @("sub-1", "sub-2", "sub-3")

foreach ($subId in $subscriptionIds) {
    New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Virtual Machine Contributor" -Scope "/subscriptions/$subId"
    New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Reader" -Scope "/subscriptions/$subId"
}
```

### Edit Schedule Times

Edit [infra/main.bicepparam](infra/main.bicepparam):

```bicep
param preMaintenanceTimePRE = '06:00'
param postMaintenanceTimePRE = '22:00'
param preMaintenanceTimePRD = '06:00'
param postMaintenanceTimePRD = '22:00'
param timeZone = 'America/Chicago'
```

## VM Filtering

### Filter by Name (Default)

Edit `$NamePattern` (or pass as parameter for Separate/Combined):

| Pattern | Matches |
|---------|---------|
| `PRE` | VM-PRE-01, PREVM, MyPREServer |
| `^DEV` | DEV-Server01, DEV-DB01 |
| `-prod$` | Web-prod, API-prod |
| `^(APP\|WEB)` | APP01, WEB02 |

### Filter by Tag

Set `$FilterBy = "Tag"` and configure:

```powershell
$FilterBy = "Tag"
$TagName = "env"
$TagValue = "pre"
```

Common tag strategies:
- `env` = `dev`, `test`, `pre`, `prod`
- `MaintenanceWindow` = `Sunday-0600`
- `PatchGroup` = `Group1`, `Group2`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Automation Account                      │
├─────────────────────────────────────────────────────────────────┤
│  Runbooks (style-dependent):      Schedules:                    │
│  ┌──────────────────────┐        ┌──────────────────────────┐  │
│  │ PreMaintenance-PRE   │◄───────│ 3rd Sunday 06:00         │  │
│  │ PreMaintenance-PRD   │◄───────│ 3rd Sunday 06:00         │  │
│  │ PostMaintenance-PRE  │◄───────│ 3rd Sunday 22:00         │  │
│  │ PostMaintenance-PRD  │◄───────│ 3rd Sunday 22:00         │  │
│  └──────────────────────┘        └──────────────────────────┘  │
│                                                                  │
│  System-Assigned Managed Identity (no credentials)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Storage Account                         │
│  Container: vm-maintenance                                       │
│  └─► PRE-started-vms-YYYY-MM-DD-HHMMSS.json (auto-deleted)     │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
├── runbooks/
│   ├── PreMaintenance-PRE-Scheduled.ps1    # Zero-touch (Scheduled style)
│   ├── PreMaintenance-PRD-Scheduled.ps1    # Zero-touch (Scheduled style)
│   ├── PostMaintenance-PRE-Scheduled.ps1   # Zero-touch (Scheduled style)
│   ├── PostMaintenance-PRD-Scheduled.ps1   # Zero-touch (Scheduled style)
│   ├── PreMaintenance-PRE.ps1              # Parameterized (Separate style)
│   ├── PreMaintenance-PRD.ps1              # Parameterized (Separate style)
│   ├── PostMaintenance-PRE.ps1             # Parameterized (Separate style)
│   ├── PostMaintenance-PRD.ps1             # Parameterized (Separate style)
│   ├── PreMaintenance-Combined.ps1         # Combined style
│   └── PostMaintenance-Combined.ps1        # Combined style
├── infra/
│   ├── main.bicep                          # Infrastructure as Code
│   ├── main.bicepparam                     # Deployment parameters
│   └── role-assignments.bicep              # Role assignment template
├── scripts/
│   └── Deploy-Automation.ps1               # Deployment script (all styles)
└── README.md
```

## Required Role Assignments

| Role | Scope | Purpose |
|------|-------|---------|
| Virtual Machine Contributor | Each subscription with VMs | Start/Stop VMs |
| Reader | Each subscription with VMs | List VMs |
| Storage Blob Data Contributor | Storage account | State persistence |

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| No VMs started | Filter doesn't match | Verify `$NamePattern` or tag settings |
| Storage account not found | Wrong name or no access | Check storage config and role assignments |
| VMs not stopping | State file missing | Check storage container for state files |
| Job failed | Managed Identity permissions | Assign VM Contributor to target subscriptions |

## Excluding VMs

- **Name filter**: Ensure VM name doesn't match `$NamePattern`
- **Tag filter**: Remove or change the tag value
- **Temporary**: Keep VM running (not deallocated) before PreMaintenance runs

## Potential Enhancements

### Sequenced Startup (Start Order)

For environments with dependencies (DB before App):

1. Tag VMs with `StartOrder`: `1`, `2`, `3`
2. Create separate schedules with time delays
3. Wave 1 (06:00): Infrastructure
4. Wave 2 (06:15): Databases
5. Wave 3 (06:30): Application servers

### Other Ideas

| Enhancement | Description |
|-------------|-------------|
| Email notifications | Logic App or SendGrid integration |
| Teams alerts | Webhook to Teams channel |
| Cost tracking | Log VM runtime hours |

## Technical Details

- **PowerShell 7.2** runtime
- **Managed Identity** authentication
- **Parallel execution** with `-NoWait`
- **Multi-subscription** support
- **Idempotent** — safe to run multiple times

**Required Az Modules**: `Az.Accounts`, `Az.Compute`, `Az.Storage`

## License
