data "http" "myip" {
  url = "https://ifconfig.co/json"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  my_ip = jsondecode(data.http.myip.body)
}

locals {
 
relay1_nsg_security_rules = {
  ssh = {
    name                       = "allow-ssh"
    description                = "Allow SSH from Load Balancer IP address"
    protocol                   = "Tcp"
    direction                  = "Inbound"
    access                     = "Allow"
    priority                   = 1000
    source_address_prefix      = (azurerm_network_interface.linux_nics[var.bp_key_name]).private_ip_address
    source_address_prefixes    = null
    destination_address_prefix = (azurerm_network_interface.linux_nics[var.relay1_key_name]).private_ip_address
    source_port_range          = "*"
    destination_port_range     = "22"
  },
  port = {
    name                       = "allow-port-${var.relay1_port}"
    description                = "Allow port ${var.relay1_port}"
    protocol                   = "Tcp"
    direction                  = "Inbound"
    access                     = "Allow"
    priority                   = 2000
    source_address_prefix      = "*"
    source_address_prefixes    = null
    destination_address_prefix = (azurerm_network_interface.linux_nics[var.relay1_key_name]).private_ip_address
    source_port_range          = "*"
    destination_port_range     = var.relay1_port
    }
  }
relay2_nsg_security_rules = {
  ssh = {
    name                       = "allow-ssh"
    description                = "Allow SSH from ${var.bp_key_name} vm"
    protocol                   = "Tcp"
    direction                  = "Inbound"
    access                     = "Allow"
    priority                   = 1000
    source_address_prefix      = (azurerm_network_interface.linux_nics[var.bp_key_name]).private_ip_address
    source_address_prefixes    = null
    destination_address_prefix = (azurerm_network_interface.linux_nics[var.relay2_key_name]).private_ip_address
    source_port_range          = "*"
    destination_port_range     = "22"
  },
  port = {
    name                       = "allow-port-${var.relay2_port}"
    description                = "Allow port ${var.relay2_port}"
    protocol                   = "Tcp"
    direction                  = "Inbound"
    access                     = "Allow"
    priority                   = 2000
    source_address_prefix      = "*"
    source_address_prefixes    = null
    destination_address_prefix = (azurerm_network_interface.linux_nics[var.relay2_key_name]).private_ip_address
    source_port_range          = "*"
    destination_port_range     = var.relay2_port
    }
  }
  bp_nsg_security_rules = {
  ssh = {
    name                       = "allow-ssh"
    description                = "Allow SSH from ${var.relay1_key_name} vm"
    protocol                   = "Tcp"
    direction                  = "Inbound"
    access                     = "Allow"
    priority                   = 1000
    source_address_prefix      = null
    source_address_prefixes    = [local.my_ip.ip]
    destination_address_prefix = (azurerm_network_interface.linux_nics[var.bp_key_name]).private_ip_address
    source_port_range          = "*"
    destination_port_range     = "22"
  },
  port = {
    name                       = "Allow port ${var.bp_port}"
    description                = "Allow communication from ${var.relay1_key_name} and ${var.relay2_key_name} vm"
    protocol                   = "Tcp"
    direction                  = "Inbound"
    access                     = "Allow"
    priority                   = 2000
    source_address_prefix      = null
    source_address_prefixes    = [(azurerm_network_interface.linux_nics[var.relay1_key_name]).private_ip_address, (azurerm_network_interface.linux_nics[var.relay2_key_name]).private_ip_address]
    destination_address_prefix = (azurerm_network_interface.linux_nics[var.bp_key_name]).private_ip_address
    source_port_range          = "*"
    destination_port_range     = var.bp_port
    }
  }
}

resource "azurerm_network_security_rule" "bp" {
  for_each                    = local.bp_nsg_security_rules 
  name                        = each.value.name
  description                 = each.value.description
  protocol                    = each.value.protocol
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  source_address_prefix       = each.value.source_address_prefix
  source_address_prefixes     = each.value.source_address_prefixes
  destination_address_prefix  = each.value.destination_address_prefix
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = "${var.bp_key_name}-nsg"
  depends_on = [
    azurerm_network_security_group.this
  ]
}

resource "azurerm_network_security_rule" "relay1" {
  for_each                    = local.relay1_nsg_security_rules 
  name                        = each.value.name
  description                 = each.value.description
  protocol                    = each.value.protocol
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  source_address_prefix       = each.value.source_address_prefix
  source_address_prefixes     = each.value.source_address_prefixes
  destination_address_prefix  = each.value.destination_address_prefix
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = "${var.relay1_key_name}-nsg"
  depends_on = [
    azurerm_network_security_group.this
  ]
}

resource "azurerm_network_security_rule" "relay2" {
  for_each                    = local.relay2_nsg_security_rules 
  name                        = each.value.name
  description                 = each.value.description
  protocol                    = each.value.protocol
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  source_address_prefix       = each.value.source_address_prefix
  source_address_prefixes     = each.value.source_address_prefixes
  destination_address_prefix  = each.value.destination_address_prefix
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = "${var.relay2_key_name}-nsg"
  depends_on = [
    azurerm_network_security_group.this
  ]
}