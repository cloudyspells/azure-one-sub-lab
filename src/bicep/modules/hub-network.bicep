targetScope = 'resourceGroup'

@description('/24 CIDR Prefix for the Hub vNet. E.g.: 10.0.1.0')
param hubVnetPrefix string = '10.0.1.0'
@description('Name convention parts for resources')
param NameConventionParts string
@description('Location / Region for the deployment')
param location string = resourceGroup().location
@description('Tags for resources')
param tags object
@description('Central log analytics workspace ID for monitoring')
param monitoringLawId string

// Create an array of the vnet prefix octets
var octets = split(hubVnetPrefix, '.')

// Create /26 subnet prefixes from the vnet prefix octets
var firewallSubnetPrefix = '${ octets[0] }.${ octets[1] }.${ octets[2]}.0/26'
var servicesSubnetPrefix = '${ octets[0] }.${ octets[1] }.${ octets[2]}.64/26'

// Ensure the hub vnet with a firewall- and a services-subnet exists
resource vNet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: 'vnet-${ NameConventionParts }-hub'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '${ hubVnetPrefix }/24'
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'  
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
      {
        name: 'snet-${ NameConventionParts}-hub-services'
        properties: {
          addressPrefix: servicesSubnetPrefix
        }
      }
    ]
  }
}

// Firewall IP group for the services subnet in the hub network
resource servicesIpGroup 'Microsoft.Network/ipGroups@2022-07-01' = {
  name: 'ipgrp-${NameConventionParts}-hub-services'
  tags: tags
  location: location
  properties: {
    ipAddresses: [
      servicesSubnetPrefix
    ]
  }
}

// 2 Public IP addresses for the firewall
resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2022-07-01' = [for i in range (0, 2): {
  name: 'pip-${NameConventionParts}-${ i + 1}'
  tags: tags
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}]

// Firewall Policy to hold the rule collections
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2022-01-01'= {
  name: 'fwp-${ NameConventionParts }'
  tags: tags
  location: location
  properties: {
    threatIntelMode: 'Alert'
  }
}

// Network rule collection group attached to the firewall policy
resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-01-01' = {
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'azure-global-services-nrc'
        priority: 1250
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'time-windows'
            ipProtocols: [
              'UDP'
            ]
            destinationAddresses: [
              '13.86.101.172'
            ]
            sourceIpGroups: [
              servicesIpGroup.id
            ]
            destinationPorts: [
              '123'
            ]
          }
        ]
      }
    ]
  }
}

// Application rule collection group attached to the firewall policy
resource applicationRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-01-01' = {
  parent: firewallPolicy
  name: 'DefaultApplicationRuleCollectionGroup'
  dependsOn: [
    networkRuleCollectionGroup
  ]
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'global-rule-url-arc'
        priority: 1000
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'winupdate-rule-01'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
              {
                protocolType: 'Http'
                port: 80
              }
            ]
            fqdnTags: [
              'WindowsUpdate'
            ]
            terminateTLS: false
            sourceIpGroups: [
              servicesIpGroup.id
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'Global-rules-arc'
        priority: 1202
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'global-rule-01'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              'www.microsoft.com'
            ]
            terminateTLS: false
            sourceIpGroups: [
              servicesIpGroup.id
            ]
          }
        ]
      }
    ]
  }
}

// The Azure Firewall deployment
resource firewall 'Microsoft.Network/azureFirewalls@2022-07-01' = {
  name: 'fw-${ NameConventionParts }'
  tags: tags
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    ipConfigurations: [
      {
        name: 'IpConfig-${ publicIpAddress[0].name }'
        properties: {
          subnet: {
            id: vNet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIpAddress[0].id
          }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'MgtIpConfig-${ publicIpAddress[0].name }'
      properties: {
        subnet: {
          id: vNet.properties.subnets[1].id
        }
        publicIPAddress: {
          id: publicIpAddress[1].id
        }
      }
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
}

resource firewallLogging 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: firewall
  name: '${ firewall.name }_Diag'
  properties: {
    workspaceId: monitoringLawId
    logs: [
      {
        category: 'AzureFirewallApplicationRule'
        enabled: true
      }
      {
        category: 'AzureFirewallNetworkRule'
        enabled: true
      }
    ]
  }
}


output hubVnetId string = vNet.id
output firewallSubnetId string = vNet.properties.subnets[0].id
output publicIpAddressIds array = [publicIpAddress[0].id, publicIpAddress[1].id]
output firewallPolicyId string = firewallPolicy.id
