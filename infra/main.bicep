// ============================================================================
// Azure Automation Account Infrastructure for VM Maintenance
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

@description('Start time for PRE Pre-Maintenance (24-hour format)')
param preMaintenanceTimePRE string = '06:00'

@description('Start time for PRD Pre-Maintenance (24-hour format)')
param preMaintenanceTimePRD string = '06:00'

@description('Start time for PRE Post-Maintenance (24-hour format)')
param postMaintenanceTimePRE string = '22:00'

@description('Start time for PRD Post-Maintenance (24-hour format)')
param postMaintenanceTimePRD string = '22:00'

@description('Time zone for schedules')
param timeZone string = 'America/Chicago'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Automation'
  Purpose: 'VM-Maintenance'
  ManagedBy: 'Bicep'
}

// ============================================================================
// Variables
// ============================================================================

var baseDate = '2026-02-15T${preMaintenanceTimePRE}:00Z'
var useIndividual = runbookStyle != 'Combined'
var useCombined = runbookStyle == 'Combined'
var useScheduled = runbookStyle == 'Scheduled'
var useSeparate = runbookStyle == 'Separate'

// ============================================================================
// Automation Account
// ============================================================================

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
    publicNetworkAccess: true
  }
}

// ============================================================================
// Runbooks - Individual Style (Scheduled or Separate: 4 env-specific runbooks)
// ============================================================================

resource runbookPreMaintenancePRE 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (useIndividual) {
  parent: automationAccount
  name: 'PreMaintenance-PRE'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: useScheduled
      ? 'Zero-touch: Starts deallocated PRE VMs before maintenance'
      : 'Parameterized: Starts deallocated PRE VMs before maintenance'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPreMaintenancePRD 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (useIndividual) {
  parent: automationAccount
  name: 'PreMaintenance-PRD'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: useScheduled
      ? 'Zero-touch: Starts deallocated PRD VMs before maintenance'
      : 'Parameterized: Starts deallocated PRD VMs before maintenance'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPostMaintenancePRE 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (useIndividual) {
  parent: automationAccount
  name: 'PostMaintenance-PRE'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: useScheduled
      ? 'Zero-touch: Stops PRE VMs after maintenance'
      : 'Parameterized: Stops PRE VMs after maintenance'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPostMaintenancePRD 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (useIndividual) {
  parent: automationAccount
  name: 'PostMaintenance-PRD'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: useScheduled
      ? 'Zero-touch: Stops PRD VMs after maintenance'
      : 'Parameterized: Stops PRD VMs after maintenance'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

// ============================================================================
// Runbooks - Combined Style (2 runbooks with -Environment parameter)
// ============================================================================

resource runbookPreMaintenanceCombined 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: 'PreMaintenance-Combined'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Combined: Starts deallocated VMs. Requires -Environment parameter.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPostMaintenanceCombined 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: 'PostMaintenance-Combined'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Combined: Stops VMs after maintenance. Requires -Environment parameter.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

// ============================================================================
// Schedules - 3rd Sunday of Each Month (same for all styles)
// ============================================================================

resource schedulePreMaintenancePRE 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PreMaintenance-PRE'
  properties: {
    description: 'PRE: 3rd Sunday before maintenance'
    startTime: baseDate
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
}

resource schedulePreMaintenancePRD 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PreMaintenance-PRD'
  properties: {
    description: 'PRD: 3rd Sunday before maintenance'
    startTime: '2026-02-15T${preMaintenanceTimePRD}:00Z'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
}

resource schedulePostMaintenancePRE 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PostMaintenance-PRE'
  properties: {
    description: 'PRE: 3rd Sunday after maintenance'
    startTime: '2026-02-15T${postMaintenanceTimePRE}:00Z'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
}

resource schedulePostMaintenancePRD 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PostMaintenance-PRD'
  properties: {
    description: 'PRD: 3rd Sunday after maintenance'
    startTime: '2026-02-15T${postMaintenanceTimePRD}:00Z'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        { occurrence: 3, day: 'Sunday' }
      ]
    }
  }
}

// ============================================================================
// Job Schedules - Scheduled Style (zero-touch, no parameters)
// ============================================================================

resource jobSchedulePrePRE_Scheduled 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useScheduled) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-PRE-Scheduled', schedulePreMaintenancePRE.name)
  properties: {
    runbook: { name: runbookPreMaintenancePRE.name }
    schedule: { name: schedulePreMaintenancePRE.name }
  }
}

resource jobSchedulePrePRD_Scheduled 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useScheduled) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-PRD-Scheduled', schedulePreMaintenancePRD.name)
  properties: {
    runbook: { name: runbookPreMaintenancePRD.name }
    schedule: { name: schedulePreMaintenancePRD.name }
  }
}

resource jobSchedulePostPRE_Scheduled 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useScheduled) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-PRE-Scheduled', schedulePostMaintenancePRE.name)
  properties: {
    runbook: { name: runbookPostMaintenancePRE.name }
    schedule: { name: schedulePostMaintenancePRE.name }
  }
}

resource jobSchedulePostPRD_Scheduled 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useScheduled) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-PRD-Scheduled', schedulePostMaintenancePRD.name)
  properties: {
    runbook: { name: runbookPostMaintenancePRD.name }
    schedule: { name: schedulePostMaintenancePRD.name }
  }
}

// ============================================================================
// Job Schedules - Separate Style (with parameters passed from Bicep)
// ============================================================================

resource jobSchedulePrePRE_Separate 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useSeparate) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-PRE-Separate', schedulePreMaintenancePRE.name)
  properties: {
    runbook: { name: runbookPreMaintenancePRE.name }
    schedule: { name: schedulePreMaintenancePRE.name }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePrePRD_Separate 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useSeparate) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-PRD-Separate', schedulePreMaintenancePRD.name)
  properties: {
    runbook: { name: runbookPreMaintenancePRD.name }
    schedule: { name: schedulePreMaintenancePRD.name }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePostPRE_Separate 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useSeparate) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-PRE-Separate', schedulePostMaintenancePRE.name)
  properties: {
    runbook: { name: runbookPostMaintenancePRE.name }
    schedule: { name: schedulePostMaintenancePRE.name }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DeleteStateFile: 'true'
      DryRun: 'false'
    }
  }
}

resource jobSchedulePostPRD_Separate 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useSeparate) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-PRD-Separate', schedulePostMaintenancePRD.name)
  properties: {
    runbook: { name: runbookPostMaintenancePRD.name }
    schedule: { name: schedulePostMaintenancePRD.name }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DeleteStateFile: 'true'
      DryRun: 'false'
    }
  }
}

// ============================================================================
// Job Schedules - Combined Style (with Environment parameter)
// ============================================================================

resource jobSchedulePreCombinedPRE 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-Combined-PRE', schedulePreMaintenancePRE.name)
  properties: {
    runbook: { name: runbookPreMaintenanceCombined.name }
    schedule: { name: schedulePreMaintenancePRE.name }
    parameters: {
      Environment: 'PRE'
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePreCombinedPRD 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-Combined-PRD', schedulePreMaintenancePRD.name)
  properties: {
    runbook: { name: runbookPreMaintenanceCombined.name }
    schedule: { name: schedulePreMaintenancePRD.name }
    parameters: {
      Environment: 'PRD'
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePostCombinedPRE 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-Combined-PRE', schedulePostMaintenancePRE.name)
  properties: {
    runbook: { name: runbookPostMaintenanceCombined.name }
    schedule: { name: schedulePostMaintenancePRE.name }
    parameters: {
      Environment: 'PRE'
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DeleteStateFile: 'true'
      DryRun: 'false'
    }
  }
}

resource jobSchedulePostCombinedPRD 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-Combined-PRD', schedulePostMaintenancePRD.name)
  properties: {
    runbook: { name: runbookPostMaintenanceCombined.name }
    schedule: { name: schedulePostMaintenancePRD.name }
    parameters: {
      Environment: 'PRD'
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DeleteStateFile: 'true'
      DryRun: 'false'
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Automation Account resource ID')
output automationAccountId string = automationAccount.id

@description('Automation Account name')
output automationAccountName string = automationAccount.name

@description('Managed Identity Principal ID (for role assignments)')
output managedIdentityPrincipalId string = automationAccount.identity.principalId

@description('Managed Identity Tenant ID')
output managedIdentityTenantId string = automationAccount.identity.tenantId

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
  schedulePreMaintenancePRE.name
  schedulePreMaintenancePRD.name
  schedulePostMaintenancePRE.name
  schedulePostMaintenancePRD.name
]
