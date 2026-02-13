// ============================================================================
// Role Assignments for Automation Account Managed Identity
// Deploy this after the main.bicep to grant necessary permissions
// ============================================================================

@description('Principal ID of the Automation Account Managed Identity')
param principalId string

@description('Subscription IDs where the Managed Identity needs VM Contributor access')
param targetSubscriptionIds array = []

@description('Scope for role assignment (subscription or resource group)')
@allowed(['subscription', 'resourceGroup'])
param roleScope string = 'subscription'

@description('Resource group name (only needed if roleScope is resourceGroup)')
param targetResourceGroupName string = ''

// ============================================================================
// Built-in Role Definition IDs
// ============================================================================

// Virtual Machine Contributor - can manage VMs but not access to them
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

// Reader - can read all resources
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// Storage Blob Data Contributor - can read/write blob data
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ============================================================================
// Role Assignments at Subscription Level
// ============================================================================

// Note: For subscription-level role assignments, deploy this template
// at the subscription scope using:
// az deployment sub create --location <location> --template-file role-assignments.bicep

// VM Contributor role for starting/stopping VMs
resource vmContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (roleScope == 'subscription') {
  name: guid(subscription().id, principalId, vmContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'VM Contributor role for Azure Automation VM Maintenance'
  }
}

// Reader role for listing subscriptions and resources
resource readerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (roleScope == 'subscription') {
  name: guid(subscription().id, principalId, readerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Reader role for Azure Automation VM Maintenance'
  }
}

// Storage Blob Data Contributor for state file management
resource storageBlobContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (roleScope == 'subscription') {
  name: guid(subscription().id, principalId, storageBlobDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Storage Blob Data Contributor for VM state files'
  }
}

// ============================================================================
// Outputs
// ============================================================================

output vmContributorRoleAssignmentId string = roleScope == 'subscription' ? vmContributorRole.id : ''
output readerRoleAssignmentId string = roleScope == 'subscription' ? readerRole.id : ''
output storageBlobContributorRoleAssignmentId string = roleScope == 'subscription' ? storageBlobContributorRole.id : ''
