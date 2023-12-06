# - Generate Private/Public SSH Key for Linux Virtual Machine
resource "tls_private_key" "this" {
  for_each  = var.resource_prefix
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "this" { 
  for_each  = var.resource_prefix
  filename = "${path.module}/${each.key}-${each.value["vm_name"]}.pem"
  content = tls_private_key.this[each.key].private_key_pem
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "this" {
  for_each                 = var.resource_prefix
  name                     = "${var.resoure_prefix}diag${each.key}${each.value["vm_name"]}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = each.value["location"]
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = var.tags
}

locals {
  vm_names_with_pip = [
    for x in var.resource_prefix : x.vm_name if lookup(x, "enable_public_ip", false) == true
  ]
  vm_names_with_pip_enabled = [
    for k, v in var.resource_prefix : {
      public_ip_name = "${k}-${v.vm_name}-pip"
      location       = v.location
    } if lookup(v, "enable_public_ip", false) == true
  ]
  public_ip_list = zipmap(local.vm_names_with_pip, local.vm_names_with_pip_enabled)
}

# - Public IP address
resource "azurerm_public_ip" "this" {
  for_each            = local.public_ip_list
  name                = each.value["public_ip_name"]
  location            = each.value["location"]
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
  
  depends_on = [azurerm_resource_group.this]
}

# - Linux Network Interfaces
resource "azurerm_network_interface" "linux_nics" {
  for_each            = var.resource_prefix
  name                = "${each.key}-${each.value["vm_name"]}-nic"
  location            = each.value["location"]
  resource_group_name = azurerm_resource_group.this.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = lookup(azurerm_subnet.this, each.key)["id"]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.value["enable_public_ip"] == true ? azurerm_public_ip.this[each.value["vm_name"]].id : null
  }
  tags = var.tags

  depends_on = [azurerm_resource_group.this, azurerm_subnet.this]
}

# - Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "linux_vms" {
  for_each                        = var.resource_prefix
  name                            = "${each.key}-${each.value["vm_name"]}"
  location                        = each.value["location"]
  resource_group_name             = azurerm_resource_group.this.name
  network_interface_ids           = [lookup(azurerm_network_interface.linux_nics, each.key)["id"]] 
  size                            = coalesce(lookup(each.value, "vm_size"), "Standard_DS1_v2")
  disable_password_authentication = true
  admin_username                  = each.value["administrator_user_name"]
  computer_name                   = "${each.key}-${each.value["vm_name"]}"

  admin_ssh_key {
    username   = each.value["administrator_user_name"]
    public_key = lookup(tls_private_key.this, each.key)["public_key_openssh"]
  }

  os_disk {
    name                 = "${each.key}-${each.value["vm_name"]}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         =  each.value["disk_size_gb"]
  }

  source_image_reference {
    publisher = "Canonical"
    offer     =  "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  lifecycle {
    ignore_changes = [
      admin_ssh_key,
      network_interface_ids,
    ]
  }

  boot_diagnostics {
    storage_account_uri = lookup(azurerm_storage_account.this, each.key)["primary_blob_endpoint"]
  }
  tags = var.tags
  
  depends_on = [azurerm_resource_group.this, azurerm_network_interface.linux_nics]
}