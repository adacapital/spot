locals {
  vm_names_with_nat = [
    for k, v in var.resource_prefix : k if lookup(v, "nat_enabled", false) == true
  ]
  vm_names_with_nat_enabled = [
    for k, v in var.resource_prefix : {
      lb_name  = "lb-${k}-${v.vm_name}"
      location = v.location
    } if lookup(v, "nat_enabled", false) == true
  ]
  lb_list = zipmap(local.vm_names_with_nat, local.vm_names_with_nat_enabled)
}

# - Public IP address
resource "azurerm_public_ip" "lbpip" {
  for_each            = local.lb_list
  name                = "${each.value["lb_name"]}-pip"
  location            = each.value["location"]
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = var.tags
  
  depends_on = [azurerm_resource_group.this]
}

# - Load Balancer
resource "azurerm_lb" "this" {
  for_each            = local.lb_list
  name                = each.value["lb_name"]
  location            = each.value["location"]
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "${each.value["lb_name"]}-frontend"
    public_ip_address_id          = azurerm_public_ip.lbpip[each.key].id
  }
  tags = var.tags

  depends_on = [azurerm_public_ip.lbpip]
}

# - Load Balancer NAT Rule
resource "azurerm_lb_nat_rule" "this" {
  for_each                       = local.lb_list
  name                           = "${each.value["lb_name"]}-ssh-nat-rule"
  resource_group_name            = azurerm_resource_group.this.name
  loadbalancer_id                = azurerm_lb.this[each.key].id
  protocol                       = "Tcp"
  frontend_port                  = var.lb_port
  backend_port                   = 22
  frontend_ip_configuration_name = "${each.value["lb_name"]}-frontend"
  idle_timeout_in_minutes        = 5
  depends_on                     = [azurerm_lb.this]
}

# Linux Network Interfaces - NAT Rules Association
resource "azurerm_network_interface_nat_rule_association" "this" {
  for_each              = local.lb_list
  network_interface_id  = (azurerm_network_interface.linux_nics[each.key])["id"]
  ip_configuration_name = "internal"
  nat_rule_id           = azurerm_lb_nat_rule.this[each.key].id

  lifecycle {
    ignore_changes = [network_interface_id]
  }

  depends_on = [azurerm_network_interface.linux_nics]
}
