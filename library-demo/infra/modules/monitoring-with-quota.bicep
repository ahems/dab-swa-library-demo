@description('Required. The name of the Log Analytics workspace.')
param logAnalyticsName string

@description('Required. The name of the Application Insights component.')
param applicationInsightsName string

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. Tags of the resource.')
param tags object?

@description('Optional. The workspace daily quota for ingestion in GB. Default is 1GB (minimum).')
@minValue(1)
param dailyQuotaGb int = 1

@description('Optional. The workspace data retention in days.')
@minValue(30)
@maxValue(730)
param dataRetention int = 30

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

// Log Analytics workspace with daily quota cap
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'logAnalyticsWorkspace'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
    dailyQuotaGb: dailyQuotaGb
    dataRetention: dataRetention
    skuName: 'PerGB2018'
    enableTelemetry: enableTelemetry
  }
}

// Application Insights connected to the Log Analytics workspace
module applicationInsights 'br/public:avm/res/insights/component:0.4.1' = {
  name: 'applicationInsights'
  params: {
    name: applicationInsightsName
    location: location
    tags: tags
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    applicationType: 'web'
    enableTelemetry: enableTelemetry
  }
}

// =========== //
// Outputs     //
// =========== //

@description('The resource ID of the loganalytics workspace.')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.outputs.resourceId

@description('The name of the log analytics workspace.')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.outputs.name

@description('The connection string of the application insights.')
output applicationInsightsConnectionString string = applicationInsights.outputs.connectionString

@description('The resource ID of the application insights.')
output applicationInsightsResourceId string = applicationInsights.outputs.resourceId

@description('The instrumentation key for the application insights.')
output applicationInsightsInstrumentationKey string = applicationInsights.outputs.instrumentationKey

@description('The name of the application insights.')
output applicationInsightsName string = applicationInsights.outputs.name
