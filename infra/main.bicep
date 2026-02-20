// ============================================================================
// Azure Automation Account Infrastructure for VM Maintenance
// Uses Azure Verified Module (AVM) for the Automation Account
// Supports 3 runbook styles: Scheduled (zero-touch), Separate, Combined
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the Automation Account')
param automationAccountName string = 'aa-vm-maintenance'

@description('Runbook style: Scheduled (zero-touch, no params), Separate (4 runbooks with params), Combined (2 runbooks with -Environment param)')
@allowed(['Scheduled', 'Separate', 'Combined'])
param runbookStyle string = 'Scheduled'

@description('Storage account name (used by Separate and Combined styles for job schedule parameters)')
param storageAccountName string = 'patchingvmlist'

@description('Storage account resource group (used by Separate and Combined styles)')
param storageAccountRG string = 'CAP-TST-01'

@description('Blob container name (used by Separate and Combined styles)')
param containerName string = 'vm-maintenance'

@description('Start time for PRE Pre-Maintenance (24-hour format, e.g. 06:00)')
param preMaintenanceTimePRE string = '06:00'

@description('Start time for PRD Pre-Maintenance (24-hour format)')
param preMaintenanceTimePRD string = '06:00'

@description('Start time for PRE Post-Maintenance (24-hour format)')
param postMaintenanceTimePRE string = '22:00'

@description('Start time for PRD Post-Maintenance (24-hour format)')
param postMaintenanceTimePRD string = '22:00'

@description('IANA time zone for schedules (e.g. America/Chicago, America/New_York, Europe/London, Etc/UTC). Times in schedule parameters are interpreted in this time zone.')
param timeZone string = 'America/Chicago'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Automation'
  Purpose: 'VM-Maintenance'
  ManagedBy: 'Bicep-AVM'
}

// ============================================================================
// Variables - Conditional Logic
// ============================================================================

var useIndividual = runbookStyle != 'Combined'
var useCombined = runbookStyle == 'Combined'
var useScheduled = runbookStyle == 'Scheduled'
var useSeparate = runbookStyle == 'Separate'

// ============================================================================
// Variables - Runbook Definitions
// ============================================================================

var individualRunbookDescPrefix = useScheduled ? 'Zero-touch' : 'Parameterized'

var individualRunbooks = [
  {
    name: 'PreMaintenance-PRE'
    type: 'PowerShell72'
    description: '${individualRunbookDescPrefix}: Starts deallocated PRE VMs before maintenance'
  }
  {
    name: 'PreMaintenance-PRD'
    type: 'PowerShell72'
    description: '${individualRunbookDescPrefix}: Starts deallocated PRD VMs before maintenance'
  }
  {
    name: 'PostMaintenance-PRE'
    type: 'PowerShell72'
    description: '${individualRunbookDescPrefix}: Stops PRE VMs after maintenance'
  }
  {
    name: 'PostMaintenance-PRD'
    type: 'PowerShell72'
    description: '${individualRunbookDescPrefix}: Stops PRD VMs after maintenance'
  }
]

var combinedRunbooks = [
  {
    name: 'PreMaintenance-Combined'
    type: 'PowerShell72'
    description: 'Combined: Starts deallocated VMs. Requires -Environment parameter.'
  }
  {
    name: 'PostMaintenance-Combined'
    type: 'PowerShell72'
    description: 'Combined: Stops VMs after maintenance. Requires -Environment parameter.'
  }
]

var runbookDefinitions = useIndividual ? individualRunbooks : combinedRunbooks

// ============================================================================
// Variables - Schedule Definitions (same for all styles)
// NOTE: startTime uses local time format (no Z suffix) - interpreted via timeZone param
// ============================================================================

var scheduleDefinitions = [
  {
    name: 'Schedule-PreMaintenance-PRE'
    description: 'PRE: 3rd Sunday - Start VMs before maintenance'
    startTime: '2026-02-15T${preMaintenanceTimePRE}:00'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
  {
    name: 'Schedule-PreMaintenance-PRD'
    description: 'PRD: 3rd Sunday - Start VMs before maintenance'
    startTime: '2026-02-15T${preMaintenanceTimePRD}:00'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
  {
    name: 'Schedule-PostMaintenance-PRE'
    description: 'PRE: 3rd Sunday - Stop VMs after maintenance'
    startTime: '2026-02-15T${postMaintenanceTimePRE}:00'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
  {
    name: 'Schedule-PostMaintenance-PRD'
    description: 'PRD: 3rd Sunday - Stop VMs after maintenance'
    startTime: '2026-02-15T${postMaintenanceTimePRD}:00'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
]

// ============================================================================
// Variables - Job Schedule Definitions (style-dependent)
// ============================================================================

var storageParams = {
  StorageAccountName: storageAccountName
  StorageAccountRG: storageAccountRG
  ContainerName: containerName
  DryRun: 'false'
}

var storageParamsWithDelete = {
  StorageAccountName: storageAccountName
  StorageAccountRG: storageAccountRG
  ContainerName: containerName
  DeleteStateFile: 'true'
  DryRun: 'false'
}

// Scheduled style: no parameters passed - everything is hardcoded in the runbook
var scheduledJobSchedules = [
  { runbookName: 'PreMaintenance-PRE', scheduleName: 'Schedule-PreMaintenance-PRE' }
  { runbookName: 'PreMaintenance-PRD', scheduleName: 'Schedule-PreMaintenance-PRD' }
  { runbookName: 'PostMaintenance-PRE', scheduleName: 'Schedule-PostMaintenance-PRE' }
  { runbookName: 'PostMaintenance-PRD', scheduleName: 'Schedule-PostMaintenance-PRD' }
]

// Separate style: storage parameters passed via job schedule
var separateJobSchedules = [
  { runbookName: 'PreMaintenance-PRE', scheduleName: 'Schedule-PreMaintenance-PRE', parameters: storageParams }
  { runbookName: 'PreMaintenance-PRD', scheduleName: 'Schedule-PreMaintenance-PRD', parameters: storageParams }
  { runbookName: 'PostMaintenance-PRE', scheduleName: 'Schedule-PostMaintenance-PRE', parameters: storageParamsWithDelete }
  { runbookName: 'PostMaintenance-PRD', scheduleName: 'Schedule-PostMaintenance-PRD', parameters: storageParamsWithDelete }
]

// Combined style: Environment + storage parameters
var combinedJobSchedules = [
  {
    runbookName: 'PreMaintenance-Combined'
    scheduleName: 'Schedule-PreMaintenance-PRE'
    parameters: union(storageParams, { Environment: 'PRE' })
  }
  {
    runbookName: 'PreMaintenance-Combined'
    scheduleName: 'Schedule-PreMaintenance-PRD'
    parameters: union(storageParams, { Environment: 'PRD' })
  }
  {
    runbookName: 'PostMaintenance-Combined'
    scheduleName: 'Schedule-PostMaintenance-PRE'
    parameters: union(storageParamsWithDelete, { Environment: 'PRE' })
  }
  {
    runbookName: 'PostMaintenance-Combined'
    scheduleName: 'Schedule-PostMaintenance-PRD'
    parameters: union(storageParamsWithDelete, { Environment: 'PRD' })
  }
]

var jobScheduleDefinitions = useScheduled
  ? scheduledJobSchedules
  : (useSeparate ? separateJobSchedules : combinedJobSchedules)

// ============================================================================
// Azure Verified Module (AVM) - Automation Account
// Registry: br/public:avm/res/automation/automation-account:0.17.1
// Docs: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/automation/automation-account
// ============================================================================

module automationAccount 'br/public:avm/res/automation/automation-account:0.17.1' = {
  name: 'deploy-automation-account'
  params: {
    name: automationAccountName
    location: location
    tags: tags
    skuName: 'Basic'

    // System-Assigned Managed Identity for VM operations & blob storage access
    managedIdentities: {
      systemAssigned: true
    }

    // Runbook shells - content is uploaded by Deploy-Automation.ps1 after deployment
    runbooks: runbookDefinitions

    // Monthly schedules - 3rd Sunday of each month
    schedules: scheduleDefinitions

    // Link runbooks to schedules (with parameters based on style)
    jobSchedules: jobScheduleDefinitions
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Automation Account resource ID')
output automationAccountId string = automationAccount.outputs.resourceId

@description('Automation Account name')
output automationAccountName string = automationAccount.outputs.name

@description('Managed Identity Principal ID (for role assignments)')
output managedIdentityPrincipalId string = automationAccount.outputs.?systemAssignedMIPrincipalId ?? ''

@description('Runbook style deployed')
output runbookStyle string = runbookStyle

@description('Runbook names deployed')
output runbookNames array = useCombined
  ? [
      'PreMaintenance-Combined'
      'PostMaintenance-Combined'
    ]
  : [
      'PreMaintenance-PRE'
      'PreMaintenance-PRD'
      'PostMaintenance-PRE'
      'PostMaintenance-PRD'
    ]

@description('Schedule names')
output scheduleNames array = [
  'Schedule-PreMaintenance-PRE'
  'Schedule-PreMaintenance-PRD'
  'Schedule-PostMaintenance-PRE'
  'Schedule-PostMaintenance-PRD'
]
