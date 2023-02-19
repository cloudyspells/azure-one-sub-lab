targetScope = 'resourceGroup'

@description('Name convention parts for resources')
param NameConventionParts string
@description('Location / Region for the deployment')
param location string = resourceGroup().location
@description('Tags for resources')
param tags object

resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${ NameConventionParts }-central-monitoring'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
  }
}

output logAnalyticsId string = law.id

