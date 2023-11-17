# Source from https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains

# Tenancy is the root or parent to all compartments.
# For this tutorial, use the value of <tenancy-ocid> for the compartment OCID.

data "oci_identity_availability_domains" "ads" {
  compartment_id = "ocid1.tenancy.oc1..aaaaaaaavgedcn22ir2lujumv6r7grjndwyxxgl5y2schttopb3jnh3ve6eq"
}

# Output Availability Domain Results
output "OCI_Availability_Domains" {
  sensitive = false
  value     = data.oci_identity_availability_domains.ads.availability_domains
}