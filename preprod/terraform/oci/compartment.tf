# compartment.tf

resource "oci_identity_compartment" "adact_preprod" {
  compartment_id = var.tenancy_ocid
  name           = "adact-preprod"
  description    = "Compartment for the ADACT preproduction environment"
}

output "adact_preprod_compartment_id" {
  description = "The OCID of the adact-preprod compartment"
  value       = oci_identity_compartment.adact_preprod.id
}

output "adact_preprod_compartment_name" {
  description = "The name of the adact-preprod compartment"
  value       = oci_identity_compartment.adact_preprod.name
}
