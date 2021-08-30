##############################################################################################################
# Default values
##############################################################################################################
resoure_group_name     = "spo-testnet-multiple"
resoure_group_location = "uksouth"

tags = {
  Environment = "test"
}

resource_prefix = { 
  bp = { 
    location                = "uksouth"
    vnet_address_space      = ["10.0.0.0/16"]
    subnet_address_prefixes = ["10.0.0.0/24"]
    vm_name                 = "vm0"
    administrator_user_name = "cardano"
    vm_size                 = "Standard_D2as_v4"
    disk_size_gb            = 32
    enable_public_ip        = false
    nat_enabled             = true
  },
  relay1 = { 
    location                = "uksouth"
    vnet_address_space      = ["192.168.0.0/16"]
    subnet_address_prefixes = ["192.168.0.0/24"]
    vm_name                 = "vm1"
    administrator_user_name = "cardano"
    vm_size                 = "Standard_D2as_v4"
    disk_size_gb            = 32
    enable_public_ip        = true
    nat_enabled             = false
  },
  relay2 = { 
    location                = "centralus"
    vnet_address_space      = ["193.168.0.0/16"]
    subnet_address_prefixes = ["193.168.0.0/24"]
    vm_name                 = "vm2"
    administrator_user_name = "cardano"
    vm_size                 = "Standard_D2as_v4"
    disk_size_gb            = 32
    enable_public_ip        = true
    nat_enabled             = false
  }
}

bp_key_name     = "bp"
relay1_key_name = "relay1"
relay2_key_name = "relay2"

bp_port     = 3000
relay1_port = 3001
relay2_port = 3001

vnet_peering = {
  bp-to-relay1 =  {
  source_resource_prefix      = "bp"
  destination_resource_prefix = "relay1"
  },
  relay1-to-bp =  {
  source_resource_prefix      = "relay1"
  destination_resource_prefix = "bp"
  },
  bp-to-relay2 =  {
  source_resource_prefix      = "bp"
  destination_resource_prefix = "relay2"
  },
  relay2-to-bp =  {
  source_resource_prefix      = "relay2"
  destination_resource_prefix = "bp"
  },
  relay1-to-relay2 =  {
  source_resource_prefix      = "relay1"
  destination_resource_prefix = "relay2"
  },
  relay2-to-relay1 =  {
  source_resource_prefix      = "relay2"
  destination_resource_prefix = "relay1"
  }
}