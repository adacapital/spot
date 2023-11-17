# variables.tf

variable "tenancy_ocid" {
  description = "The OCID of the tenancy"
  type        = string
}

variable "tenancy_region" {
  description = "The region of the tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "The OCID of the compartment"
  type        = string
}

# Network Configuration Variables

variable "oci_vcn_cidr_block" {
  default     = "10.2.0.0/16"
  description = "CIDR Address range for OCI Networks Block VCN"
}

variable "oci_vcn_cidr_subnet_bp_node" {
  default     = "10.2.1.0/24"
  description = "CIDR Address range for OCI Networks BP Subnet"
}

variable "oci_vcn_cidr_subnet_relay1_node" {
  default     = "10.2.2.0/24"
  description = "CIDR Address range for OCI Networks Relay1 Subnet"
}

variable "oci_vcn_cidr_subnet_relay2_node" {
  default     = "10.2.3.0/24"
  description = "CIDR Address range for OCI Networks Relay2 Subnet"
}

variable "subnet_id_bp_node" {
  description = "The OCID of the subnet for the Block Producing Node VMs"
  type        = string
}

variable "subnet_id_relay1_node" {
  description = "The OCID of the subnet for the Relay1 Node VMs"
  type        = string
}

variable "subnet_id_relay2_node" {
  description = "The OCID of the subnet for the Relay2 Node VMs"
  type        = string
}

# variable "vcn_id" {
#   description = "The OCID of the VCN"
#   type        = string
# }


# Virtual Machine Configuration Variables

variable "instance_prefix" {
  description = "Name prefix for vm instances"
  default     = "preprod"
}

variable "image_id" {
  description = "The OCID of the Ubuntu image"
  type        = string
}

variable "availability_domain" {
  description = "The availability domain for the VMs"
  default     = "AD-2"
}

variable "vm_shape" {
  description = "The shape for the VMs"
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  description = "The number of OCPUs for the VMs"
  default     = 2
}

variable "memory_in_gbs" {
  description = "The amount of memory in GBs for the VMs"
  default     = 12
}

variable "block_volume_size_in_gbs" {
  description = "The size of the block volume in GBs"
  type        = map(number)
  default     = {
    "block_producing_node_vm" = 50
    "relay_node_vm_1"         = 100
    "relay_node_vm_2"         = 50
  }
}

variable "block_volume_vpus_per_gb" {
  description = "The vpus per gb"
  type        = map(number)
  default     = {
    "block_producing_node_vm" = 10
    "relay_node_vm_1"         = 10
    "relay_node_vm_2"         = 10
  }
}

variable "public_ip" {
  description = "Flag to assign a public IP"
  type        = map(bool)
  default     = {
    "block_producing_node_vm" = true
    "relay_node_vm_1"         = true
    "relay_node_vm_2"         = true
  }
}

variable "relay_ports_open_to_all" {
  description = "List of open to all ports for creating NSG rules for relays"
  type        = list(number)
  default     = [3001, 80, 443]
}

