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

// Calculate the next 3rd Sunday for initial schedule start
// Note: Azure Automation schedules use monthlyOccurrence for monthly patterns
var baseDate = '2026-02-15T${preMaintenanceTimePRE}:00Z' // Next occurrence

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
// Automation Variables (for runbook configuration)
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
// Runbooks - Placeholders (content uploaded separately via deployment script)
// ============================================================================

resource runbookPreMaintenancePRE 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'PreMaintenance-PRE'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Pre-Maintenance runbook for PRE (Pre-Production) environment. Starts deallocated VMs before maintenance window.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPreMaintenancePRD 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'PreMaintenance-PRD'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Pre-Maintenance runbook for PRD (Production) environment. Starts deallocated VMs before maintenance window.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPostMaintenancePRE 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'PostMaintenance-PRE'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Post-Maintenance runbook for PRE environment. Stops VMs that were started for maintenance.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

resource runbookPostMaintenancePRD 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'PostMaintenance-PRD'
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Post-Maintenance runbook for PRD environment. Stops VMs that were started for maintenance.'
    logProgress: true
    logVerbose: true
    logActivityTrace: 0
  }
}

// ============================================================================
// Schedules - 3rd Sunday of Each Month
// ============================================================================

// PRE Environment - Pre-Maintenance Schedule (3rd Sunday, before maintenance)
resource schedulePreMaintenancePRE 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PreMaintenance-PRE'
  properties: {
    description: 'PRE Environment: Runs on 3rd Sunday of each month before maintenance window'
    startTime: baseDate
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        {
          occurrence: 3  // 3rd occurrence
          day: 'Sunday'
        }
      ]
    }
  }
}

// PRD Environment - Pre-Maintenance Schedule (3rd Sunday, before maintenance)
resource schedulePreMaintenancePRD 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PreMaintenance-PRD'
  properties: {
    description: 'PRD Environment: Runs on 3rd Sunday of each month before maintenance window'
    startTime: '2026-02-15T${preMaintenanceTimePRD}:00Z'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        {
          occurrence: 3
          day: 'Sunday'
        }
      ]
    }
  }
}

// PRE Environment - Post-Maintenance Schedule (3rd Sunday, after maintenance)
resource schedulePostMaintenancePRE 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PostMaintenance-PRE'
  properties: {
    description: 'PRE Environment: Runs on 3rd Sunday of each month after maintenance window'
    startTime: '2026-02-15T${postMaintenanceTimePRE}:00Z'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        {
          occurrence: 3
          day: 'Sunday'
        }
      ]
    }
  }
}

// PRD Environment - Post-Maintenance Schedule (3rd Sunday, after maintenance)
resource schedulePostMaintenancePRD 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Schedule-PostMaintenance-PRD'
  properties: {
    description: 'PRD Environment: Runs on 3rd Sunday of each month after maintenance window'
    startTime: '2026-02-15T${postMaintenanceTimePRD}:00Z'
    frequency: 'Month'
    interval: 1
    timeZone: timeZone
    advancedSchedule: {
      monthlyOccurrences: [
        {
          occurrence: 3
          day: 'Sunday'
        }
      ]
    }
  }
}

// ============================================================================
// Job Schedules - Link Runbooks to Schedules
// ============================================================================

resource jobSchedulePreMaintenancePRE 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, runbookPreMaintenancePRE.name, schedulePreMaintenancePRE.name)
  properties: {
    runbook: {
      name: runbookPreMaintenancePRE.name
    }
    schedule: {
      name: schedulePreMaintenancePRE.name
    }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePreMaintenancePRD 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, runbookPreMaintenancePRD.name, schedulePreMaintenancePRD.name)
  properties: {
    runbook: {
      name: runbookPreMaintenancePRD.name
    }
    schedule: {
      name: schedulePreMaintenancePRD.name
    }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DryRun: 'false'
    }
  }
}

resource jobSchedulePostMaintenancePRE 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, runbookPostMaintenancePRE.name, schedulePostMaintenancePRE.name)
  properties: {
    runbook: {
      name: runbookPostMaintenancePRE.name
    }
    schedule: {
      name: schedulePostMaintenancePRE.name
    }
    parameters: {
      StorageAccountName: storageAccountName
      StorageAccountRG: storageAccountRG
      ContainerName: containerName
      DeleteStateFile: 'true'
      DryRun: 'false'
    }
  }
}

resource jobSchedulePostMaintenancePRD 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, runbookPostMaintenancePRD.name, schedulePostMaintenancePRD.name)
  properties: {
    runbook: {
      name: runbookPostMaintenancePRD.name
    }
    schedule: {
      name: schedulePostMaintenancePRD.name
    }
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

@description('Runbook names')
output runbookNames array = [
  runbookPreMaintenancePRE.name
  runbookPreMaintenancePRD.name
  runbookPostMaintenancePRE.name
  runbookPostMaintenancePRD.name
]

@description('Schedule names')
output scheduleNames array = [
  schedulePreMaintenancePRE.name
  schedulePreMaintenancePRD.name
  schedulePostMaintenancePRE.name
  schedulePostMaintenancePRD.name
]
