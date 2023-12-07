# Network 
# Create a core virtual network for the tenancy
resource "oci_core_vcn" "adact_mainnet_vcn" {
  cidr_block     = var.oci_vcn_cidr_block
  compartment_id = var.tenancy_ocid
  display_name   = "ADACT-Mainnet-AmpereVCN"
  dns_label      = "mainnet"
}

resource "oci_core_security_list" "default_security_list" {
  # Placeholder for the security list - details will be filled in after import
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adact_mainnet_vcn.id
  display_name = "Default Security List for ADACT-Mainnet-AmpereVCN"
  # id = "ocid1.securitylist.oc1.uk-london-1.aaaaaaaaqva25i6woc2nd47idnxwb6utlcqhxesjszeulijvxe2f4mkjfdsq"

  egress_security_rules {
      description = ""
      destination = "0.0.0.0/0"
      destination_type ="CIDR_BLOCK"
      protocol = "all"
      stateless = false
  }

  ingress_security_rules {
    description = ""
    icmp_options {
        code = -1
        type = 3
      }
    protocol = "1"
    source =  "10.2.0.0/16"
    source_type = "CIDR_BLOCK"
    stateless = false
  }

    ingress_security_rules {
      description = ""
      icmp_options {
          code = 4
          type = 3
        }
      protocol = "1"
      source =  "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
      stateless = false
  }

  ingress_security_rules {
      description = ""
      tcp_options { 
        min = 22
        max = 22
      }
      protocol = "6"
      source =  "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
      stateless = false
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless = false
    tcp_options {
      min = 3001
      max = 3001
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }
}


# Within that Core network create a subnet for bp node
resource "oci_core_subnet" "adact_mainnet_bp_subnet" {
  cidr_block        = var.oci_vcn_cidr_subnet_bp_node
  display_name      = "ADACT-Mainnet-BP-AmpereVCN"
  dns_label         = "bp"
#   security_list_ids = [oci_core_security_list.ampere_security_list.id]
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.adact_mainnet_vcn.id
  route_table_id    = oci_core_route_table.adact_mainnet_route_table.id # default when bp has public ip
  # route_table_id    = oci_core_route_table.adact_mainnet_bp_route_table.id  # Updated to use the new route table
  dhcp_options_id   = oci_core_vcn.adact_mainnet_vcn.default_dhcp_options_id
}

# Within that Core network create a subnet for relay1 node
resource "oci_core_subnet" "adact_mainnet_relay1_subnet" {
  cidr_block        = var.oci_vcn_cidr_subnet_relay1_node
  display_name      = "ADACT-Mainnet-Relay1-AmpereVCN"
  dns_label         = "relay1"
#   security_list_ids = [oci_core_security_list.ampere_security_list.id]
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.adact_mainnet_vcn.id
  route_table_id    = oci_core_route_table.adact_mainnet_route_table.id
  dhcp_options_id   = oci_core_vcn.adact_mainnet_vcn.default_dhcp_options_id
}

# Within that Core network create a subnet for relay2 node
resource "oci_core_subnet" "adact_mainnet_relay2_subnet" {
  cidr_block        = var.oci_vcn_cidr_subnet_relay2_node
  display_name      = "ADACT-Mainnet-Relay2-AmpereVCN"
  dns_label         = "relay2"
#   security_list_ids = [oci_core_security_list.ampere_security_list.id]
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.adact_mainnet_vcn.id
  route_table_id    = oci_core_route_table.adact_mainnet_route_table.id
  dhcp_options_id   = oci_core_vcn.adact_mainnet_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "adact_mainnet_internet_gateway" {
  compartment_id = var.tenancy_ocid
  display_name   = "ADACT-Mainnet-InternetGateway"
  vcn_id         = oci_core_vcn.adact_mainnet_vcn.id
}

resource "oci_core_route_table" "adact_mainnet_route_table" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adact_mainnet_vcn.id
  display_name   = "ADACT-Mainnet-RouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.adact_mainnet_internet_gateway.id
  }
}

resource "oci_core_route_table" "adact_mainnet_bp_route_table" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adact_mainnet_vcn.id
  display_name   = "ADACT-Mainnet-BP-RouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.adact_mainnet_nat_gateway.id
  }
}


resource "oci_core_nat_gateway" "adact_mainnet_nat_gateway" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.adact_mainnet_vcn.id
  display_name   = "ADACT-Mainnet-NATGateway"
}