terraform {
	required_providers {
		azurerm = {
		source  = "hashicorp/azurerm"
		# The "feature" block is required for AzureRM provider 2.x. 
		version = "~> 2.1.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
	features {}
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
	name     = "${var.resource-prefix}-rg"
	location = var.pool-location
	tags = {
		environment = var.tag-environment
	}
}

# Create Virtual network
resource "azurerm_virtual_network" "vnet" {
	name                = "${var.resource-prefix}-vnet"
	address_space       = ["10.0.0.0/16"]
	location            = var.pool-location
	resource_group_name = azurerm_resource_group.rg.name
	tags = {
		environment = var.tag-environment
	}
}

# Create Subnets
resource "azurerm_subnet" "coresnet" {
	name                 = "${var.resource-prefix}-vnet-core-snet"
	resource_group_name  = azurerm_resource_group.rg.name
	virtual_network_name = azurerm_virtual_network.vnet.name
	address_prefix       = "10.0.1.0/24"
}

# Create Public IPs
resource "azurerm_public_ip" "core0pip" {
	name                = "${var.resource-prefix}-core0pip"
	location            = var.pool-location
	resource_group_name = azurerm_resource_group.rg.name
	sku                 = "Standard"
	allocation_method   = "Static"
	tags = {
		environment = var.tag-environment
	}
}

# Request your IP 
data "http" "myip" {
  url = "https://ifconfig.co/json"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  ifconfig_co_json = jsondecode(data.http.myip.body)
}

# Create Network Security Groups
resource "azurerm_network_security_group" "corensg" {
	name                = "${var.resource-prefix}-core-nsg"
	location            = var.pool-location
	resource_group_name = azurerm_resource_group.rg.name
	security_rule {
		name                       = "SSH"
		priority                   = 1001
		direction                  = "Inbound"
		access                     = "Allow"
		protocol                   = "Tcp"
		source_port_range          = "*"
		destination_port_range     = "22"
		source_address_prefixes    = [local.ifconfig_co_json.ip]
		destination_address_prefix = "*"
	}
	security_rule {
		name                       = "relay-in"
		priority                   = 1002
		direction                  = "Inbound"
		access                     = "Allow"
		protocol                   = "Tcp"
		source_port_range          = "*"
		destination_port_range     = var.core-node-port
		source_address_prefixes    = [azurerm_public_ip.core0pip.ip_address]
		destination_address_prefix = "*"
	}
	security_rule {
		name                       = "mon-in"
		priority                   = 1003
		direction                  = "Inbound"
		access                     = "Allow"
		protocol                   = "Tcp"
		source_port_range          = "*"
		destination_port_ranges    = ["12789", "9100"]
		source_address_prefixes    = [azurerm_public_ip.core0pip.ip_address]
		destination_address_prefix = "*"
	}
	security_rule {
		name                       = "http-in"
		priority                   = 1004
		direction                  = "Inbound"
		access                     = "Allow"
		protocol                   = "Tcp"
		source_port_range          = "*"
		destination_port_ranges    = ["80","443"]
		source_address_prefix      = "*"
		destination_address_prefix = "*"
	}
	security_rule {
		name                       = "graf-in"
		priority                   = 1005
		direction                  = "Inbound"
		access                     = "Allow"
		protocol                   = "Tcp"
		source_port_range          = "*"
		destination_port_range     = 3000
		source_address_prefix      = "*"
		destination_address_prefix = "*"
	}
	tags = {
		environment = var.tag-environment
	}
}

# Create Network interfaces
	resource "azurerm_network_interface" "core0nic" {
	name                          = "${var.resource-prefix}-core0nic"
	location                      = var.pool-location
	resource_group_name           = azurerm_resource_group.rg.name
	enable_accelerated_networking = var.corevm-nic-accelerated-networking
	ip_configuration {
		name                          = "core0nic-ipconfig"
		subnet_id                     = azurerm_subnet.coresnet.id
		private_ip_address_allocation = "Dynamic"
		public_ip_address_id          = azurerm_public_ip.core0pip.id
	}
	tags = {
		environment = var.tag-environment
	}
}

# Connect Network Security Groups to the Network Interfaces
resource "azurerm_network_interface_security_group_association" "core0nicnsg" {
	network_interface_id      = azurerm_network_interface.core0nic.id
	network_security_group_id = azurerm_network_security_group.corensg.id
}

# Network Watcher for location
# resource "azurerm_network_watcher" "nwatcher" {
# 	name                = "${var.resource-prefix}-nwatcher"
# 	location            = var.pool-location
# 	resource_group_name = azurerm_resource_group.rg.name
# }

# As each storage account must have a unique name, the following section generates some random text
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.rg.name
    }

    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "corestorageaccount" {
	name                     = "diag${random_id.randomId.hex}core"
	resource_group_name      = azurerm_resource_group.rg.name
	location                 = var.pool-location
	account_tier             = "Standard"
	account_replication_type = "LRS"
	tags = {
		environment = var.tag-environment
	}
}

# Create (and display) an SSH key 
resource "tls_private_key" "sshkey" {
	algorithm = "RSA"
	rsa_bits  = 4096
}

# Create virtual machines
resource "azurerm_linux_virtual_machine" "core0vm" {
	name                            = "${var.resource-prefix}-core0vm"
	location                        = var.pool-location
	resource_group_name             = azurerm_resource_group.rg.name
	network_interface_ids           = [azurerm_network_interface.core0nic.id]
	size                            = var.corevm-size
	computer_name                   = "${var.corevm-comp-name}0"
	admin_username                  = var.vm-username
	disable_password_authentication = true
	zone                            = "1"
	os_disk {
		name                 = "${var.resource-prefix}-core0vm-osdisk"
		caching              = "ReadWrite"
		storage_account_type = "Premium_LRS"
		disk_size_gb         = "256"
	}
	source_image_reference {
		publisher = "Canonical"
		offer     = "0001-com-ubuntu-server-focal"
		sku       = "20_04-lts"
		version   = "latest"
	}
	admin_ssh_key {
		username   = var.vm-username
		public_key = tls_private_key.sshkey.public_key_openssh
	}
	boot_diagnostics {
		storage_account_uri = azurerm_storage_account.corestorageaccount.primary_blob_endpoint
	}
	tags = {
		environment = var.tag-environment
	}
}

output "sshpvk" {
	value       = tls_private_key.sshkey.private_key_pem
	description = "SSH private key"
	sensitive   = false
}

output "c0pip" {
	value       = azurerm_public_ip.core0pip.ip_address
	description = "Core VM 0 Active Public IP Address"
	sensitive   = false
}