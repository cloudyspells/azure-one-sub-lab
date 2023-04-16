targetScope = 'resourceGroup'

@description('Azure resource ID of the existing Hub VNet')
param hubVnetId string
@description('Azure resource ID of the configured Spoke Azure VNet')
param spokeVnetId string

// Hub Vnet Name
var hubVnetName = last(split(hubVnetId, '/'))

// Spoke Vnet Name
var spokeVnetName = last(split(spokeVnetId, '/'))


resource hubVnet 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  name: hubVnetName
}

resource peerHubToNewVnet 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-07-01' = {
  name: 'hub-to-${ spokeVnetName }'
  parent: hubVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowGatewayTransit: true
    useRemoteGateways: false
    allowForwardedTraffic: true
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
  }
}
