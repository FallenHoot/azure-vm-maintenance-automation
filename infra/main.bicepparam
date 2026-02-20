using './main.bicep'

// ============================================================================
// Production Parameters for VM Maintenance Automation
// Customize these values for your environment
// ============================================================================

// Location - use the same region as your VMs for better performance
param location = 'centralus'

// Automation Account name
param automationAccountName = 'aa-vm-maintenance'

// Runbook style: 'Scheduled' (zero-touch), 'Separate' (4 with params), 'Combined' (2 with -Environment)
param runbookStyle = 'Scheduled'

// Storage configuration (used by Separate and Combined styles for job schedule parameters)
param storageAccountName = 'patchingvmlist'
param storageAccountRG = 'CAP-TST-01'
param containerName = 'vm-maintenance'

// Schedule times (24-hour format, UTC)
// Adjust based on your maintenance window
param preMaintenanceTimePRE = '06:00'   // 6:00 AM - Start VMs before maintenance
param preMaintenanceTimePRD = '06:00'   // 6:00 AM - Start VMs before maintenance
param postMaintenanceTimePRE = '22:00'  // 10:00 PM - Stop VMs after maintenance
param postMaintenanceTimePRD = '22:00'  // 10:00 PM - Stop VMs after maintenance

// Time zone for schedules
param timeZone = 'America/Chicago'

// Resource tags
param tags = {
  Environment: 'Production'
  Purpose: 'VM-Maintenance-Automation'
  Owner: 'Infrastructure-Team'
  CostCenter: 'IT-Operations'
  ManagedBy: 'Bicep'
}
