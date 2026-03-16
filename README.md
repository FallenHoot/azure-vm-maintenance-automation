# Azure VM Maintenance Automation

> **DISCLAIMER**  
> This script is provided as sample guidance only and is not a supported Microsoft product. It is provided "AS IS", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. Microsoft and the author(s) are not liable for any damages arising from the use of this code. Review and test in a non-production environment before use.

Automatically starts deallocated VMs before scheduled maintenance windows and stops them afterward. Runs on the **3rd Sunday** of each month.

## How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│  3rd Sunday of Each Month (Automatic)                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  06:00 ─► PreMaintenance Runbook                                │
│               • Scans all subscriptions for deallocated VMs     │
│               • Filters by name pattern or tag                  │
│               • Starts matching VMs                             │
│               • Saves state to Azure Blob Storage               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │         Maintenance Window (VMs Running)               │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  22:00 ─► PostMaintenance Runbook                               │
│               • Reads state file from Blob Storage              │
│               • Stops only the VMs that were started            │
│               • Cleans up state file                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Deployment

**4 parameterized runbooks with `param()` blocks.** Storage config defaults are in the scripts; override at runtime or via job schedules. Each runbook includes a built-in 3rd Sunday gate — schedule them to run every Sunday and they automatically skip non-3rd-Sunday weeks.

### Step 1: Deploy

```powershell
.\scripts\Deploy-Automation.ps1 -ResourceGroupName "rg-automation" -Location "centralus"
```

### Step 2: Test

1. Go to Automation Account → Runbooks → PreMaintenance-PRE → Start
2. Pass `-DryRun $true` to preview which VMs would be targeted without making changes
3. Review output, verify correct VMs targeted
4. Run again without DryRun, then run PostMaintenance-PRE to stop them

### Step 3: Customize (Optional)

You can override parameters when running manually:
```powershell
Start-AzAutomationRunbook -Name "PreMaintenance-PRE" `
  -Parameters @{ FilterBy = "Tag"; TagName = "env"; TagValue = "pre"; DryRun = $true } `
  -ResourceGroupName "rg-automation" -AutomationAccountName "aa-vm-maintenance"
```

> **DryRun mode:** PreMaintenance always writes a report blob to storage for both modes (`DryRun=$true` and `$false`) even when zero VMs match the filter. Blob files include mode in filename: `*-vm-state-dryrun-true-*.json` or `*-vm-state-dryrun-false-*.json`. JSON payload includes `"DryRun": true|false` and `"Mode": "TEST TEST TEST"` or `"LIVE LIVE LIVE"`.

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
param preMaintenanceTimePRE = '06:00'   // 6:00 AM in your time zone
param postMaintenanceTimePRE = '22:00'  // 10:00 PM in your time zone
param preMaintenanceTimePRD = '06:00'
param postMaintenanceTimePRD = '22:00'
param timeZone = 'America/Chicago'      // IANA time zone — change to match your region
```

> **Time Zone Note:** Schedule times are interpreted in the `timeZone` you specify (IANA format). Common values: `America/Chicago`, `America/New_York`, `Asia/Kolkata`, `Europe/London`, `Etc/UTC`. Change this to match your ops team's local time zone.

## VM Filtering

### Filter by Name (Default)

Edit `$NamePattern` (or pass as parameter):

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

Infrastructure is deployed using [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) via `br/public:avm/res/automation/automation-account:0.17.1`. The Bicep template deploys runbook shells, schedules, and job schedules. The deploy script (`Deploy-Automation.ps1`) uploads the runbook files.

```
┌─────────────────────────────────────────────────────────────────┐
│              Azure Automation Account (AVM)                      │
├─────────────────────────────────────────────────────────────────┤
│  Runbooks:                        Schedules (every Sunday):     │
│  ┌──────────────────────┐        ┌──────────────────────────┐  │
│  │ PreMaintenance-PRE   │◄───────│ Every Sunday 06:00        │  │
│  │ PreMaintenance-PRD   │◄───────│ Every Sunday 06:00        │  │
│  │ PostMaintenance-PRE  │◄───────│ Every Sunday 22:00        │  │
│  │ PostMaintenance-PRD  │◄───────│ Every Sunday 22:00        │  │
│  └──────────────────────┘        └──────────────────────────┘  │
│  (3rd Sunday gate built into each runbook)                      │
│                                                                  │
│  System-Assigned Managed Identity (no credentials)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Storage Account                         │
│  Container: vm-maintenance                                       │
│  └─► PRE-vm-state-dryrun-true-YYYY-MM-DD-HHMMSS.json           │
│  └─► PRE-vm-state-dryrun-false-YYYY-MM-DD-HHMMSS.json          │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
├── runbooks/
│   ├── PreMaintenance-PRE.ps1              # PRE pre-maintenance (start VMs)
│   ├── PreMaintenance-PRD.ps1              # PRD pre-maintenance (start VMs)
│   ├── PostMaintenance-PRE.ps1             # PRE post-maintenance (stop VMs)
│   └── PostMaintenance-PRD.ps1             # PRD post-maintenance (stop VMs)
├── infra/
│   ├── main.bicep                          # Infrastructure as Code (AVM)
│   ├── main.bicepparam                     # Deployment parameters
│   └── role-assignments.bicep              # Role assignment template
├── scripts/
│   └── Deploy-Automation.ps1               # Deployment script
└── README.md
```

## Required Role Assignments

| Role | Scope | Purpose |
|------|-------|---------|
| Virtual Machine Contributor | Each subscription with VMs | Start/Stop VMs |
| Reader | Each subscription with VMs | List VMs |
| Storage Blob Data Contributor | Storage account | State persistence |

## Troubleshooting

### Scheduling on 3rd Sunday of Month

Azure Automation does not natively support scheduling runbooks for the "nth Sunday" of the month. To work around this:

1. **Create a schedule to run the runbook every Sunday** (weekly recurrence).
2. **The runbooks include built-in logic** to check if today is the 3rd Sunday.

#### Timezone Handling

> **Important:** Azure Automation runs in **UTC**. If your schedule fires near midnight UTC (e.g., 01:00 CET), `Get-Date` may return the previous day (Saturday) instead of Sunday. All runbooks convert UTC to the schedule's timezone before checking the day.

Each runbook has a `$ScheduleTimeZone` parameter (defaults to `"Europe/Amsterdam"`). This **must match the timezone configured in your Azure Automation schedule**. Uses standard [IANA timezone IDs](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

```powershell
# Converts UTC to the schedule's timezone before checking the day
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($ScheduleTimeZone)
$today = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tz)

$weekOfMonth = [math]::Ceiling($today.Day / 7)
if ($today.DayOfWeek -ne 'Sunday') {
    Write-Output "Today is $($today.DayOfWeek), not Sunday. Exiting."
    return
}
if ($weekOfMonth -ne 3) {
    Write-Output "Today is Sunday week $weekOfMonth, not the 3rd Sunday. Exiting."
    return
}
```

Common `$ScheduleTimeZone` values (IANA format):

| Schedule Timezone | `$ScheduleTimeZone` value |
|---|---|
| (UTC+01:00) Amsterdam, Berlin, Rome | `Europe/Amsterdam` |
| (UTC+05:30) Chennai, Kolkata, Mumbai | `Asia/Kolkata` |
| (UTC-05:00) Eastern Time (US) | `America/New_York` |
| (UTC-06:00) Central Time (US) | `America/Chicago` |
| (UTC) Coordinated Universal Time | `UTC` |

> Full list: [IANA Time Zone Database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)

This logic is already embedded in all 4 runbooks. The schedule triggers every Sunday, but the runbook exits early unless it's the 3rd Sunday in the configured timezone.

> **Tip:** You can test this logic by manually running the runbook on any day and observing the output — it will log the converted local time and day of week.

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
