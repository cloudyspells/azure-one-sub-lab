targetScope = 'resourceGroup'

@description('Azure resource ID of the existing Hub VNet')
param hubVnetId string
@description('IP of the existing Azure Firewall')
param firewallIp string
@description('Name for the new Azure VNet')
param vNetName string
@description('/24 IP Prefix for the new Azure VNet, this will be devided in 3 subnets with addres space for 1 /26 to spare')
param vNetAddressPrefix string
@description('Location / Azure Region for the deployment')
param location string = resourceGroup().location
@description('Tags for the resources')
param tags object

// Get names for the subnets from the vNetName
var subnetNames = {
  frontend: '${ replace(vNetName, 'vnet-','snet-') }-frontend'
  backend: '${ replace(vNetName, 'vnet-','snet-') }-backend'
  paas: '${ replace(vNetName, 'vnet-','snet-') }-paas'
}
// Get names for the NSGs from the vNetName
var nsgNames = {
  frontend: '${ replace(vNetName, 'vnet-','nsg-') }-frontend'
  backend: '${ replace(vNetName, 'vnet-','nsg-') }-backend'
  paas: '${ replace(vNetName, 'vnet-','nsg-') }-paas'
}

// Create the IP octets from the supplied prefix
var octets = split(vNetAddressPrefix, '.')

// Create /26 subnet prefixes from the vnet prefix octets
var subnetPrefixes = {
  frontend: '${ octets[0] }.${ octets[1] }.${ octets[2]}.0/26'
  backend: '${ octets[0] }.${ octets[1] }.${ octets[2]}.64/26'
  paas: '${ octets[0] }.${ octets[1] }.${ octets[2]}.128/26'
}

// Create the NSGs for the subnets
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = [for item in items(nsgNames): {
  name: item.value
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'deny-hop-outbound'
        properties: {
          access: 'Deny'
          direction: 'Outbound'
          priority: 200
          protocol: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '3389'
            '22'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
    ]
  }
}]

// Create a route table for the subnets pointing to the Azure Firewall
resource routeTable 'Microsoft.Network/routeTables@2022-07-01' = {
  name: '${ vNetName }-route-table'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'AzureFirewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallIp
        }
      }
    ]
  }
}

// Create the vnet and subnets
resource newVnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: vNetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['${ vNetAddressPrefix }/24']
    }
    subnets: [ for (subnet, i) in items(subnetNames): {
      name: subnet.value
      properties: {
        addressPrefix: subnetPrefixes[subnet.key]
        networkSecurityGroup: {
          id: nsg[i].id
        }
        routeTable: {
          id: routeTable.id
        }
      }
    }]
  }
}

// Peer the new vnet to the hub vnet
resource peerVnetToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-07-01' = {
  name: '${ vNetName }-to-hub'
  parent: newVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowGatewayTransit: false
    useRemoteGateways: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: {
      id: hubVnetId
    }
  }
}
