# compartment.tf

resource "oci_identity_compartment" "adact_mainnet" {
  compartment_id = var.tenancy_ocid
  name           = "adact-mainnet"
  description    = "Compartment for the ADACT mainnet environment"
}

output "adact_mainnet_compartment_id" {
  description = "The OCID of the adact-mainnet compartment"
  value       = oci_identity_compartment.adact_mainnet.id
}

output "adact_mainnet_compartment_name" {
  description = "The name of the adact-mainnet compartment"
  value       = oci_identity_compartment.adact_mainnet.name
}
