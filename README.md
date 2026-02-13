# Azure VM Maintenance Automation

> **DISCLAIMER**  
> This script is provided as sample guidance only and is not a supported Microsoft product. It is provided "AS IS", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. Microsoft and the author(s) are not liable for any damages arising from the use of this code. Review and test in a non-production environment before use.

Automated VM maintenance runbooks for Azure Automation. This solution starts deallocated VMs before scheduled maintenance windows and stops them afterward, saving the state to Azure Storage.

## Features

- **Flexible VM Filtering**: Filter VMs by name pattern (regex) or Azure tags
- **Environment Separation**: Dedicated runbooks for PRE/PRD or unified runbooks with parameters
- **Scheduled Execution**: Automatically runs on the 3rd Sunday of each month
- **Multi-Subscription**: Scans all enabled subscriptions in your tenant
- **State Persistence**: Saves VM state to Azure Blob Storage for reliable post-maintenance recovery
- **DryRun Mode**: Test changes without affecting VMs
- **Idempotent**: Safe to run multiple times - only starts deallocated VMs

## VM Filtering Options

The runbooks support two filtering methods to identify which VMs to manage:

### Option 1: Filter by VM Name (Default)

Uses regex pattern matching against VM names. Great for naming conventions.

| Parameter | Default (PRE) | Default (PRD) | Description |
|-----------|---------------|---------------|-------------|
| `FilterBy` | `Name` | `Name` | Filter method |
| `NamePattern` | `PRE` | `PRD` | Regex pattern to match VM names |

**Examples:**
```powershell
# Match VMs containing "PRE" anywhere in the name
-NamePattern "PRE"          # Matches: VM-PRE-01, PREVM, MyPREServer

# Match VMs starting with "DEV" or "TST"
-NamePattern "^(DEV|TST)"   # Matches: DEV-Server01, TST-DB01

# Match VMs ending with "-prod"
-NamePattern "-prod$"       # Matches: Web-prod, API-prod

# Match specific prefixes with numbers
-NamePattern "^APP[0-9]+"   # Matches: APP01, APP123
```

### Option 2: Filter by Azure Tags

Uses Azure resource tags for flexible grouping. Ideal for complex environments.

| Parameter | Default (PRE) | Default (PRD) | Description |
|-----------|---------------|---------------|-------------|
| `FilterBy` | `Tag` | `Tag` | Filter method |
| `TagName` | `env` | `env` | Tag key to filter by |
| `TagValue` | `pre` | `prod` | Tag value to match |

**Common Tag Strategies:**
```powershell
# By environment
-FilterBy "Tag" -TagName "env" -TagValue "production"

# By maintenance window
-FilterBy "Tag" -TagName "MaintenanceWindow" -TagValue "Sunday-0600"

# By application
-FilterBy "Tag" -TagName "Application" -TagValue "SAP"

# By patch group
-FilterBy "Tag" -TagName "PatchGroup" -TagValue "Group1"
```

**Recommended Tags for VMs:**
| Tag | Values | Purpose |
|-----|--------|---------|
| `env` | `dev`, `test`, `pre`, `prod` | Environment classification |
| `MaintenanceWindow` | `Sunday-0600`, `Sunday-2200` | Specific maintenance schedule |
| `AutoStart` | `true`, `false` | Include/exclude from automation |
| `StartOrder` | `1`, `2`, `3` | Startup sequencing (for dependencies) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Automation Account                      │
├─────────────────────────────────────────────────────────────────┤
│  Runbooks (Choose Your Style):                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ Option A: Environment-Specific Runbooks                │    │
│  │   PreMaintenance-PRE   │   PostMaintenance-PRE        │    │
│  │   PreMaintenance-PRD   │   PostMaintenance-PRD        │    │
│  ├────────────────────────────────────────────────────────┤    │
│  │ Option B: Unified Runbooks with Environment Parameter  │    │
│  │   PreMaintenance -Environment PRE|PRD                 │    │
│  │   PostMaintenance -Environment PRE|PRD                │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Schedules: 3rd Sunday each month                               │
│  └─► PRE: 06:00 (Pre) / 22:00 (Post)                           │
│  └─► PRD: 06:00 (Pre) / 22:00 (Post)                           │
│                                                                  │
│  System-Assigned Managed Identity                               │
│  └─► VM Contributor (across subscriptions)                     │
│  └─► Storage Blob Data Contributor                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Storage Account                         │
│  Container: vm-maintenance                                       │
│  └─► PRE-started-vms-2026-02-15-060000.json                    │
│  └─► PRD-started-vms-2026-02-15-060000.json                    │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Azure subscription with Contributor access
- Azure CLI or Azure PowerShell installed
- Storage account for state persistence

### Deployment

1. **Clone the repository**
   ```powershell
   git clone https://github.com/FallenHoot/azure-vm-maintenance-automation.git
   cd azure-vm-maintenance-automation
   ```

2. **Update parameters** (optional)
   
   Edit [infra/main.bicepparam](infra/main.bicepparam) to customize:
   - Storage account configuration
   - Schedule times
   - Time zone

3. **Deploy using PowerShell**
   ```powershell
   .\scripts\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus"
   ```

4. **Or deploy using Azure CLI**
   ```bash
   az deployment group create \
     --resource-group rg-automation \
     --template-file infra/main.bicep \
     --parameters infra/main.bicepparam
   ```

## Runbooks

### Environment-Specific Runbooks

| Runbook | Environment | Purpose | Default Filter |
|---------|-------------|---------|----------------|
| `PreMaintenance-PRE` | Pre-Production | Start deallocated VMs | Name contains `PRE` |
| `PreMaintenance-PRD` | Production | Start deallocated VMs | Name contains `PRD` |
| `PostMaintenance-PRE` | Pre-Production | Stop started VMs | Uses state file |
| `PostMaintenance-PRD` | Production | Stop started VMs | Uses state file |

### Unified Runbooks

| Runbook | Required Param | Purpose |
|---------|----------------|---------|
| `PreMaintenance` | `-Environment PRE\|PRD` | Start deallocated VMs |
| `PostMaintenance` | `-Environment PRE\|PRD` | Stop started VMs |

### Parameters

#### PreMaintenance Runbooks

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Environment` | string | - | **Unified only**: `PRE` or `PRD` |
| `StorageAccountName` | string | `patchingvmlist` | Storage account for state |
| `StorageAccountRG` | string | `CAP-TST-01` | Storage account resource group |
| `ContainerName` | string | `vm-maintenance` | Blob container name |
| `FilterBy` | string | `Name` | Filter method: `Name` or `Tag` |
| `NamePattern` | string | `PRE`/`PRD` | Regex pattern for VM names |
| `TagName` | string | `env` | Tag key to filter by |
| `TagValue` | string | `pre`/`prod` | Tag value to match |
| `DryRun` | bool | `false` | Simulate without changes |

#### PostMaintenance Runbooks

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Environment` | string | - | **Unified only**: `PRE` or `PRD` |
| `StorageAccountName` | string | `patchingvmlist` | Storage account for state |
| `StorageAccountRG` | string | `CAP-TST-01` | Storage account resource group |
| `ContainerName` | string | `vm-maintenance` | Blob container name |
| `StateFileName` | string | `` | Specific state file (optional) |
| `DeleteStateFile` | bool | `true` | Delete state file after processing |
| `DryRun` | bool | `false` | Simulate without changes |

## Pro Tips

### 1. Use DryRun First

Always test with DryRun before running in production:
```powershell
Start-AzAutomationRunbook -Name "PreMaintenance-PRE" `
  -Parameters @{ DryRun = $true } `
  -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance"
```

### 2. Combine Filters with Tags

Use tags for maximum flexibility:
```powershell
# Tag VMs that should NOT auto-start
az vm update --ids <vm-id> --set tags.AutoStart=false

# Then filter in runbook
-FilterBy "Tag" -TagName "AutoStart" -TagValue "true"
```

### 3. Staged Rollout with Start Order

For VMs with dependencies (DB before App), use a StartOrder tag and run multiple times:
```powershell
# First wave - Infrastructure (Domain Controllers, DNS)
-FilterBy "Tag" -TagName "StartOrder" -TagValue "1"

# Second wave - Databases
-FilterBy "Tag" -TagName "StartOrder" -TagValue "2"

# Third wave - Application Servers
-FilterBy "Tag" -TagName "StartOrder" -TagValue "3"
```

### 4. Monitor with Log Analytics

Query runbook results in Log Analytics:
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.AUTOMATION"
| where Category == "JobStreams"
| where StreamType_s == "Output"
| project TimeGenerated, ResultDescription
| order by TimeGenerated desc
```

### 5. Exclude VMs Temporarily

To exclude a VM from the next maintenance window:
```powershell
# Option A: Remove the matching tag
az vm update --ids <vm-id> --remove tags.env

# Option B: Add an exclusion tag and update filter
az vm update --ids <vm-id> --set tags.MaintenanceExclude=true
```

### 6. Cost Optimization

VMs are started with `-NoWait` and stopped with `-Force -NoWait` for parallel execution. This minimizes:
- Runbook execution time (and costs)
- Time VMs are running during maintenance

## Role Assignments

The Automation Account's Managed Identity requires these roles:

| Role | Scope | Purpose |
|------|-------|---------|
| Virtual Machine Contributor | Subscription(s) with VMs | Start/Stop VMs |
| Reader | Subscription(s) with VMs | List subscriptions and VMs |
| Storage Blob Data Contributor | Storage account | Read/write state files |

### Multi-Subscription Setup

```powershell
$principalId = "<Managed-Identity-Principal-ID>"
$subscriptions = @("sub-id-1", "sub-id-2", "sub-id-3")

foreach ($subId in $subscriptions) {
    New-AzRoleAssignment `
        -ObjectId $principalId `
        -RoleDefinitionName "Virtual Machine Contributor" `
        -Scope "/subscriptions/$subId"
}
```

## File Structure

```
├── runbooks/
│   ├── PreMaintenance.ps1        # Unified (requires -Environment)
│   ├── PostMaintenance.ps1       # Unified (requires -Environment)
│   ├── PreMaintenance-PRE.ps1    # PRE environment specific
│   ├── PreMaintenance-PRD.ps1    # PRD environment specific
│   ├── PostMaintenance-PRE.ps1   # PRE environment specific
│   └── PostMaintenance-PRD.ps1   # PRD environment specific
├── infra/
│   ├── main.bicep                # Automation Account infrastructure
│   ├── main.bicepparam           # Parameter file
│   └── role-assignments.bicep    # Role assignment template
├── scripts/
│   └── Deploy-Automation.ps1     # Deployment script
└── README.md
```

## Schedule Configuration

Schedules are configured for the **3rd Sunday of each month**:

```bicep
advancedSchedule: {
  monthlyOccurrences: [
    { occurrence: 3, day: 'Sunday' }
  ]
}
```

## Monitoring

### View Job Status

```powershell
Get-AzAutomationJob -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" -RunbookName "PreMaintenance-PRE" | 
  Select-Object Status, StartTime, EndTime | 
  Sort-Object StartTime -Descending | Select-Object -First 10
```

### View Job Output

```powershell
$job = Get-AzAutomationJob -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" -RunbookName "PreMaintenance-PRE" | 
  Sort-Object StartTime -Descending | Select-Object -First 1

Get-AzAutomationJobOutput -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" -Id $job.JobId -Stream Output
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Storage account not found | Verify name/RG, ensure MI has Reader access |
| Managed Identity connection failed | Enable System-Assigned MI, check role assignments |
| No VMs match filter | Check NamePattern/Tag params, verify VMs are deallocated |
| VMs not starting | Check MI has VM Contributor on target subscription |

## Technical Notes

Follows [Microsoft Azure Automation best practices](https://learn.microsoft.com/azure/automation/context-switching):

- `Disable-AzContextAutosave -Scope Process` prevents context inheritance
- `-DefaultProfile $AzureContext` on all Az cmdlets ensures consistent context
- System-Assigned Managed Identity for secure authentication
- `$ErrorActionPreference = "Stop"` for strict error handling
- `-NoWait` for parallel VM operations

**Required Az Modules**: `Az.Accounts`, `Az.Compute`, `Az.Storage`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License
