variable "ssh-whitelist" {
	type        = list(string)
	description = "Whitelist IP(s) for SSH access to the nodes. Helpful at the start but strongly recommended for removal later."
	default 	= ["*"]
}
variable "mon-whitelist" {
	type        = list(string)
	description = "Whitelist IP(s) for monitoring agents access to nodes via Prometheus metrics data."
	default 	= ["*"]
}
variable "pool-location-bp" {
	type        = string
	description = "Stake Pool location from verified location list (az account list-locations -o table --query \"sort_by([], &regionalDisplayName)\")"
	default 	= "uksouth"
}
variable "pool-location-relay1" {
	type        = string
	description = "Stake Pool location from verified location list (az account list-locations -o table --query \"sort_by([], &regionalDisplayName)\")"
	default 	= "uksouth"
}
variable "pool-location-relay2" {
	type        = string
	description = "Stake Pool location from verified location list (az account list-locations -o table --query \"sort_by([], &regionalDisplayName)\")"
	default 	= "centralus"
}
variable "resource-prefix" {
	type        = string
	description = "Prefix to apply to all Stake Pool resources"
	default 	= "spo-testnet-m"
}
variable "vm-username" {
	type        = string
	description = "VM username for all nodes"
	default		= "newriverhead"
}
variable "corevm-size" {
	type        = string
	description = "Stake Pool core node VM size (az vm list-sizes --location $pool-location -o table)"
	default 	= "Standard_D2as_v4"
}
variable "corevm-nic-accelerated-networking" {
	type        = string
	description = "Enable accelerated networking for core node NIC. Ensure it is supported by VM size."
	default		= "false"
}
variable "corevm-comp-name" {
	type        = string
	description = "Stake Pool core node VM computer name"
	default 	= "corevm"
}
variable "core-node-port" {
	type        = string
	description = "Port to run the core node on"
	default		= "3000" 
}
variable "tag-environment" {
	type        = string
	description = "Environment tag assigned to all resources"
	default = "test"
}
