// ============================================================================
// Azure Automation Account Infrastructure for VM Maintenance
// Deploys Automation Account with runbooks and schedules for 3rd Sunday
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the Automation Account')
param automationAccountName string = 'aa-vm-maintenance'

@description('Storage account name for state persistence')
param storageAccountName string = 'patchingvmlist'

@description('Storage account resource group')
param storageAccountRG string = 'CAP-TST-01'

@description('Container name for VM state files')
param containerName string = 'vm-maintenance'

@description('Runbook deployment style: Separate (4 env-specific runbooks) or Combined (2 runbooks with Environment parameter)')
@allowed(['Separate', 'Combined'])
param runbookStyle string = 'Separate'

@description('Start time for PRE environment Pre-Maintenance (before maintenance window)')
param preMaintenanceTimePRE string = '06:00'

@description('Start time for PRD environment Pre-Maintenance (before maintenance window)')
param preMaintenanceTimePRD string = '06:00'

@description('Start time for PRE environment Post-Maintenance (after maintenance window)')
param postMaintenanceTimePRE string = '22:00'

@description('Start time for PRD environment Post-Maintenance (after maintenance window)')
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
var useCombined = runbookStyle == 'Combined'

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
// Automation Variables
// ============================================================================

resource varStorageAccountName 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'StorageAccountName'
  properties: {
    value: '"${storageAccountName}"'
    isEncrypted: false
    description: 'Storage account name for state persistence'
  }
}

resource varStorageAccountRG 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'StorageAccountRG'
  properties: {
    value: '"${storageAccountRG}"'
    isEncrypted: false
    description: 'Resource group containing the storage account'
  }
}

resource varContainerName 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'ContainerName'
  properties: {
    value: '"${containerName}"'
    isEncrypted: false
    description: 'Blob container name for state files'
  }
}

// ============================================================================
// Runbooks - SEPARATE Style (4 environment-specific runbooks)
// ============================================================================

resource runbookPreMaintenancePRE 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: 'PreMaintenance-PRE'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Pre-Maintenance runbook for PRE environment. Starts deallocated VMs.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPreMaintenancePRD 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: 'PreMaintenance-PRD'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Pre-Maintenance runbook for PRD environment. Starts deallocated VMs.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPostMaintenancePRE 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: 'PostMaintenance-PRE'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Post-Maintenance runbook for PRE environment. Stops started VMs.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPostMaintenancePRD 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: 'PostMaintenance-PRD'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Post-Maintenance runbook for PRD environment. Stops started VMs.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

// ============================================================================
// Runbooks - COMBINED Style (2 runbooks with Environment parameter)
// ============================================================================

resource runbookPreMaintenanceCombined 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: 'PreMaintenance-Combined'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Pre-Maintenance runbook (Combined). Starts deallocated VMs. Requires -Environment parameter.'
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
    description: 'Post-Maintenance runbook (Combined). Stops started VMs. Requires -Environment parameter.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

// ============================================================================
// Schedules - 3rd Sunday of Each Month
// ============================================================================

resource schedulePreMaintenancePRE 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PreMaintenance-PRE'
  properties: {
    description: 'PRE Environment: 3rd Sunday before maintenance window'
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
    description: 'PRD Environment: 3rd Sunday before maintenance window'
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
    description: 'PRE Environment: 3rd Sunday after maintenance window'
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
    description: 'PRD Environment: 3rd Sunday after maintenance window'
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
// Job Schedules - SEPARATE Style
// ============================================================================

resource jobSchedulePreMaintenancePRE 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-PRE', schedulePreMaintenancePRE.name)
  properties: {
    runbook: { name: 'PreMaintenance-PRE' }
    schedule: { name: schedulePreMaintenancePRE.name }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePreMaintenancePRD 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-PRD', schedulePreMaintenancePRD.name)
  properties: {
    runbook: { name: 'PreMaintenance-PRD' }
    schedule: { name: schedulePreMaintenancePRD.name }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePostMaintenancePRE 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-PRE', schedulePostMaintenancePRE.name)
  properties: {
    runbook: { name: 'PostMaintenance-PRE' }
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

resource jobSchedulePostMaintenancePRD 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (!useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PostMaintenance-PRD', schedulePostMaintenancePRD.name)
  properties: {
    runbook: { name: 'PostMaintenance-PRD' }
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
// Job Schedules - COMBINED Style
// ============================================================================

resource jobSchedulePreCombinedPRE 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (useCombined) {
  parent: automationAccount
  name: guid(automationAccount.id, 'PreMaintenance-Combined-PRE', schedulePreMaintenancePRE.name)
  properties: {
    runbook: { name: 'PreMaintenance-Combined' }
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
    runbook: { name: 'PreMaintenance-Combined' }
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
    runbook: { name: 'PostMaintenance-Combined' }
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
    runbook: { name: 'PostMaintenance-Combined' }
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

@description('Managed Identity Principal ID (use this for role assignments)')
output managedIdentityPrincipalId string = automationAccount.identity.principalId

@description('Managed Identity Tenant ID')
output managedIdentityTenantId string = automationAccount.identity.tenantId

@description('Runbook style deployed')
output runbookStyle string = runbookStyle

@description('Runbook names deployed')
output runbookNames array = useCombined ? [
  'PreMaintenance-Combined'
  'PostMaintenance-Combined'
] : [
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
