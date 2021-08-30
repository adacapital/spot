# - Create Resource Groups and assign mandatory tags
resource "azurerm_resource_group" "this" {
  name     = "${var.resoure_group_name}-rg"
  location = var.resoure_group_location
  tags     = var.tags
}

# - Virtual Network
resource "azurerm_virtual_network" "this" {
  for_each            = var.resource_prefix
  name                = "${each.key}-vnet"
  location            = each.value["location"]
  resource_group_name = azurerm_resource_group.this.name
  address_space       = each.value["vnet_address_space"]
  tags                = var.tags
  
  depends_on = [azurerm_resource_group.this]
}

# - Subnet
resource "azurerm_subnet" "this" {
  for_each             = var.resource_prefix
  name                 = "${each.key}-snet"
  resource_group_name  = azurerm_resource_group.this.name
  address_prefixes     = each.value["subnet_address_prefixes"]
  virtual_network_name = "${each.key}-vnet"

  depends_on = [azurerm_virtual_network.this]
}

# - Network Security Group
resource "azurerm_network_security_group" "this" {
  for_each            = var.resource_prefix
  name                = "${each.key}-nsg"
  location            = each.value["location"]
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  depends_on = [azurerm_resource_group.this]
}


# - Network Security Group association to Subnet
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = var.resource_prefix
  network_security_group_id = lookup(azurerm_network_security_group.this, each.key)["id"]
  subnet_id                 = lookup(azurerm_subnet.this, each.key)["id"]
  
  depends_on = [azurerm_subnet.this, azurerm_network_security_group.this ]
}

# - VNet Peering
resource "azurerm_virtual_network_peering" "source_to_destination" {
  for_each                     = var.vnet_peering
  name                         = "${(azurerm_virtual_network.this[each.value["source_resource_prefix"]])["name"]}-to-${(azurerm_virtual_network.this[each.value["destination_resource_prefix"]])["name"]}"
  resource_group_name          = azurerm_resource_group.this.name
  remote_virtual_network_id    = (azurerm_virtual_network.this[each.value["destination_resource_prefix"]])["id"]
  virtual_network_name         = (azurerm_virtual_network.this[each.value["source_resource_prefix"]])["name"]
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  lifecycle {
    ignore_changes = [remote_virtual_network_id]
  }
  depends_on = [azurerm_virtual_network.this]
}