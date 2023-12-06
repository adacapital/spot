

variable "resoure_prefix" {
  type        = string
  description = "Specifies a name prefix for resources"
}
variable "resoure_group_name" {
  type        = string
  description = "Specifies the name of the Resource Group as part of Base Infrastructure"
}

variable "resoure_group_location" {
  type        = string
  description = "Specifies the location of the Resource Group"
}

variable "tags" {
  type        = map(string)
  description = "Specifies the tags of the Resources"
}

variable "bp_key_name" {
  type        = string
}

variable "relay1_key_name" {
  type        = string
}

variable "relay2_key_name" {
  type        = string
}

variable "bp_port" {
  type        = number
}

variable "relay1_port" {
  type        = number
}

variable "relay2_port" {
  type        = number
}

variable "lb_port" {
  type        = number
}

variable "resource_prefix" {
  type = map(object({
    location                = string
    vnet_address_space      = list(string)
    subnet_address_prefixes = list(string)
    vm_name                 = string
    administrator_user_name = string
    vm_size                 = string
    disk_size_gb            = number
    enable_public_ip        = bool
    nat_enabled             = bool
  }))
  default = {}
}

variable "vnet_peering" {
  type = map(object({
    source_resource_prefix      = string
    destination_resource_prefix = string
  }))
  description = "Specifies the map of objects for vnet peering."
  default     = {}
}