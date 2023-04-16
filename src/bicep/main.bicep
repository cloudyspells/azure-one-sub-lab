targetScope = 'subscription'

@description('Location / Region for deployment')
param location string = deployment().location
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
var lzName = '${ shortLocations[location] }-lz-${ labName }'

// Name convention resource group names
var rgNetworkName = 'rg-${ infraName }-network'
var rgMonitoringName = 'rg-${ infraName }-monitoring'
var rgLzName = 'rg-${ lzName }'

// Ensure resource group for monitoring exists
resource rgMonitoring 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgMonitoringName
  location: location
  tags: tags
}

// Ensure monitoring resources are deployed
module monitoring 'modules/monitoring.bicep' = {
  scope: rgMonitoring
  name: 'deploy-monitoring-${ labName }'
  params: {
    NameConventionParts: infraName
    tags: tags
    location: location
  }
}

// Ensure networking resource group exists
resource rgNetwork 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgNetworkName
  location: location
  tags: tags
}

// Deploy hub network resources
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

resource rgLz 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgLzName
  location: location
  tags: tags
}

module lzNetwork 'modules/peered-vnet-to-hub.bicep' = {
  scope: rgLz
  name: 'deploy-lznetwork-${ labName }'
  params: {
    location: location
    firewallIp: hubNetwork.outputs.firewallPrivateIpAddress
    hubVnetId: hubNetwork.outputs.hubVnetId
    tags: tags
    vNetAddressPrefix: '10.0.100.0/24'
    vNetName: 'vnet-${ lzName }'
  }
}
