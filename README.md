# Azure VM Maintenance Automation

> ** DISCLAIMER**  
> This script is provided as sample guidance only and is not a supported Microsoft product. It is provided "AS IS", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. Microsoft and the author(s) are not liable for any damages arising from the use of this code. Review and test in a non-production environment before use.

Automated VM maintenance runbooks for Azure Automation. This solution starts deallocated VMs before scheduled maintenance windows and stops them afterward, saving the state to Azure Storage.

## Features

- **Separate Environment Runbooks**: Dedicated runbooks for PRE (Pre-Production) and PRD (Production) environments
- **Scheduled Execution**: Automatically runs on the 3rd Sunday of each month
- **Azure Automation Native**: Designed for Azure Automation with System-Assigned Managed Identity
- **State Persistence**: Saves VM state to Azure Blob Storage for reliable post-maintenance recovery
- **DryRun Mode**: Test changes without affecting VMs
- **Flexible Filtering**: Filter VMs by name pattern or tags

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Automation Account                      │
├─────────────────────────────────────────────────────────────────┤
│  Runbooks:                        Schedules:                    │
│  ┌──────────────────────┐        ┌──────────────────────────┐  │
│  │ PreMaintenance-PRE   │◄───────│ 3rd Sunday 06:00 (PRE)   │  │
│  │ PreMaintenance-PRD   │◄───────│ 3rd Sunday 06:00 (PRD)   │  │
│  │ PostMaintenance-PRE  │◄───────│ 3rd Sunday 22:00 (PRE)   │  │
│  │ PostMaintenance-PRD  │◄───────│ 3rd Sunday 22:00 (PRD)   │  │
│  └──────────────────────┘        └──────────────────────────┘  │
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
   # Deploy infrastructure
   az deployment group create \
     --resource-group rg-automation \
     --template-file infra/main.bicep \
     --parameters infra/main.bicepparam
   
   # Get the Managed Identity Principal ID
   PRINCIPAL_ID=$(az automation account show \
     --resource-group rg-automation \
     --name aa-vm-maintenance \
     --query identity.principalId -o tsv)
   
   # Assign roles (repeat for each subscription with VMs)
   az role assignment create \
     --assignee-object-id $PRINCIPAL_ID \
     --role "Virtual Machine Contributor" \
     --scope /subscriptions/<subscription-id>
   ```

## Runbooks

| Runbook | Environment | Purpose | Schedule |
|---------|-------------|---------|----------|
| `PreMaintenance-PRE` | Pre-Production | Start deallocated VMs | 3rd Sunday, 06:00 |
| `PreMaintenance-PRD` | Production | Start deallocated VMs | 3rd Sunday, 06:00 |
| `PostMaintenance-PRE` | Pre-Production | Stop VMs started for maintenance | 3rd Sunday, 22:00 |
| `PostMaintenance-PRD` | Production | Stop VMs started for maintenance | 3rd Sunday, 22:00 |

### Parameters

#### PreMaintenance Runbooks

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
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
| `StorageAccountName` | string | `patchingvmlist` | Storage account for state |
| `StorageAccountRG` | string | `CAP-TST-01` | Storage account resource group |
| `ContainerName` | string | `vm-maintenance` | Blob container name |
| `StateFileName` | string | `` | Specific state file (optional) |
| `DeleteStateFile` | bool | `true` | Delete state file after processing |
| `DryRun` | bool | `false` | Simulate without changes |

## Testing

### DryRun Mode

Test the runbooks without affecting VMs:

```powershell
# In Azure Portal or via Az PowerShell
Start-AzAutomationRunbook `
  -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" `
  -Name "PreMaintenance-PRE" `
  -Parameters @{ DryRun = $true }
```

### Manual Execution

Run immediately for the upcoming Sunday patching:

```powershell
# Start PRE environment VMs
Start-AzAutomationRunbook `
  -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" `
  -Name "PreMaintenance-PRE" `
  -Parameters @{ DryRun = $false }
```

## Role Assignments

The Automation Account's Managed Identity requires these roles:

| Role | Scope | Purpose |
|------|-------|---------|
| Virtual Machine Contributor | Subscription(s) with VMs | Start/Stop VMs |
| Reader | Subscription(s) with VMs | List subscriptions and VMs |
| Storage Blob Data Contributor | Storage account | Read/write state files |

### Multi-Subscription Setup

If VMs span multiple subscriptions:

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
│   ├── PreMaintenance-PRE.ps1    # PRE environment pre-maintenance
│   ├── PreMaintenance-PRD.ps1    # PRD environment pre-maintenance
│   ├── PostMaintenance-PRE.ps1   # PRE environment post-maintenance
│   └── PostMaintenance-PRD.ps1   # PRD environment post-maintenance
├── infra/
│   ├── main.bicep                # Automation Account infrastructure
│   ├── main.bicepparam           # Parameter file
│   └── role-assignments.bicep    # Role assignment template
├── scripts/
│   └── Deploy-Automation.ps1     # Deployment script
└── README.md
```

## Schedule Configuration

The schedules are configured for the **3rd Sunday of each month** using Azure Automation's `monthlyOccurrences` feature:

```bicep
advancedSchedule: {
  monthlyOccurrences: [
    {
      occurrence: 3  // 3rd occurrence
      day: 'Sunday'
    }
  ]
}
```

To modify the schedule times, update the parameters in [main.bicepparam](infra/main.bicepparam):

```bicep
param preMaintenanceTimePRE = '06:00'   // Before maintenance
param postMaintenanceTimePRE = '22:00'  // After maintenance
param timeZone = 'America/Chicago'
```

## Monitoring

### View Job Status

```powershell
Get-AzAutomationJob `
  -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" `
  -RunbookName "PreMaintenance-PRE" | 
  Select-Object Status, StartTime, EndTime | 
  Sort-Object StartTime -Descending | 
  Select-Object -First 10
```

### View Job Output

```powershell
$job = Get-AzAutomationJob `
  -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" `
  -RunbookName "PreMaintenance-PRE" | 
  Sort-Object StartTime -Descending | 
  Select-Object -First 1

Get-AzAutomationJobOutput `
  -ResourceGroupName "rg-automation" `
  -AutomationAccountName "aa-vm-maintenance" `
  -Id $job.JobId -Stream Output
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Storage account not found | Verify name/RG, ensure MI has Reader access |
| Managed Identity connection failed | Enable System-Assigned MI, check role assignments |
| No VMs match filter | Check NamePattern/Tag params, verify VMs are deallocated |

## Technical Notes

The runbooks follow [Microsoft Azure Automation best practices](https://learn.microsoft.com/azure/automation/context-switching):

- `Disable-AzContextAutosave -Scope Process` prevents context inheritance
- `-DefaultProfile $AzureContext` on all Az cmdlets ensures consistent context
- System-Assigned Managed Identity for secure authentication
- `$ErrorActionPreference = "Stop"` for strict error handling

**Required Az Modules**: `Az.Accounts`, `Az.Compute`, `Az.Storage`

## License

MIT License
