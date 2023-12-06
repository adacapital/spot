# Network 
# Create a core virtual network for the tenancy
resource "oci_core_vcn" "adact_preprod_vcn" {
  cidr_block     = var.oci_vcn_cidr_block
  compartment_id = var.tenancy_ocid
  display_name   = "ADACT-Preprod-AmpereVCN"
  dns_label      = "preprod"
}

# Within that Core network create a subnet for bp node
resource "oci_core_subnet" "adact_preprod_bp_subnet" {
  cidr_block        = var.oci_vcn_cidr_subnet_bp_node
  display_name      = "ADACT-Preprod-BP-AmpereVCN"
  dns_label         = "bp"
#   security_list_ids = [oci_core_security_list.ampere_security_list.id]
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.adact_preprod_vcn.id
  route_table_id    = oci_core_route_table.adact_preprod_route_table.id # default when bp has public ip
  # route_table_id    = oci_core_route_table.adact_preprod_bp_route_table.id  # Updated to use the new route table
  dhcp_options_id   = oci_core_vcn.adact_preprod_vcn.default_dhcp_options_id
}

# Within that Core network create a subnet for relay1 node
resource "oci_core_subnet" "adact_preprod_relay1_subnet" {
  cidr_block        = var.oci_vcn_cidr_subnet_relay1_node
  display_name      = "ADACT-Preprod-Relay1-AmpereVCN"
  dns_label         = "relay1"
#   security_list_ids = [oci_core_security_list.ampere_security_list.id]
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.adact_preprod_vcn.id
  route_table_id    = oci_core_route_table.adact_preprod_route_table.id
  dhcp_options_id   = oci_core_vcn.adact_preprod_vcn.default_dhcp_options_id
}

# Within that Core network create a subnet for relay2 node
resource "oci_core_subnet" "adact_preprod_relay2_subnet" {
  cidr_block        = var.oci_vcn_cidr_subnet_relay2_node
  display_name      = "ADACT-Preprod-Relay2-AmpereVCN"
  dns_label         = "relay2"
#   security_list_ids = [oci_core_security_list.ampere_security_list.id]
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.adact_preprod_vcn.id
  route_table_id    = oci_core_route_table.adact_preprod_route_table.id
  dhcp_options_id   = oci_core_vcn.adact_preprod_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "adact_preprod_internet_gateway" {
  compartment_id = var.tenancy_ocid
  display_name   = "ADACT-Preprod-InternetGateway"
  vcn_id         = oci_core_vcn.adact_preprod_vcn.id
}

resource "oci_core_route_table" "adact_preprod_route_table" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adact_preprod_vcn.id
  display_name   = "ADACT-Preprod-RouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.adact_preprod_internet_gateway.id
  }
}

resource "oci_core_route_table" "adact_preprod_bp_route_table" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adact_preprod_vcn.id
  display_name   = "ADACT-Preprod-BP-RouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.adact_preprod_nat_gateway.id
  }
}


resource "oci_core_nat_gateway" "adact_preprod_nat_gateway" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adact_preprod_vcn.id
  display_name   = "ADACT-Preprod-NATGateway"
}