targetScope = 'subscription'

@description('Location / Region for deployment')
param location string = 'westeurope'
@description('Name part to use in lab name convention')
param labName string = 'ssl'
@description('/24 CIDR Prefix for the Hub vNet')
param hubVnetPrefix string = '10.0.1.0'
@description('Tags for resources')
param tags object = {
  'Cost Centre': 'Research and Development'
  'Resource Owner': 'CloudySpells Labs'
  'Technical Contact': 'Roderick Bant'
}

// Lookup table for short location names for name convention
var shortLocations = {
  westeurope: 'weu'
  northeurope: 'neu'
  swedencentral: 'swc'
  uksouth: 'uks'
  francecentral: 'frc'
  germanywestcentral: 'dewc'
  norwayeast: 'noe'
  francesouth: 'frs'
  germanynorth: 'den'
  norwaywest: 'now'
  ukwest: 'ukw'
}

// Name convention parts for infra
var infraName = '${ shortLocations[location] }-infra-${ labName }'

// Name convention resource group names
var rgNetworkName = 'rg-${ infraName }-network'
var rgMonitoringName = 'rg-${ infraName }-monitoring'

resource rgMonitoring 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgMonitoringName
  location: location
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rgMonitoring
  name: 'deploy-monitoring-${ labName }'
  params: {
    NameConventionParts: infraName
    tags: tags
    location: location
  }
}

resource rgNetwork 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgNetworkName
  location: location
}

module hubNetwork 'modules/hub-network.bicep' = {
  scope: rgNetwork
  name: 'deploy-hubnetwork-${ labName }'
  params: {
    NameConventionParts: infraName
    hubVnetPrefix: hubVnetPrefix
    monitoringLawId: monitoring.outputs.logAnalyticsId
    location: location
    tags: tags
  }
}
