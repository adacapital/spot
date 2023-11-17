# provider "oci" {
#   region = var.tenancy_region
#   # Credentials are assumed to be set via environment variables
# }

########################################### BP NODE ###########################################
data "template_file" "init_bp" {
  template = file("cloud-init-bp.yaml.tpl")

  vars = {
    bp_node_ssh_public_key = trimspace(file("/home/thomas/.oci/pem-adact-preprod-bp.pub"))
    relay1_ssh_public_key = trimspace(file("/home/thomas/.oci/pem-adact-preprod-relay1.pub"))
    relay2_ssh_public_key = trimspace(file("/home/thomas/.oci/pem-adact-preprod-relay2.pub"))
    relay1_ssh_private_key = indent(6, trimspace(file("/home/thomas/.oci/pem-adact-preprod-relay1")))
    relay2_ssh_private_key = indent(6, trimspace(file("/home/thomas/.oci/pem-adact-preprod-relay2")))
    bashrc_file = indent(7, file(".bashrc.tpl"))
  }
}

# Block Producing Node VM
resource "oci_core_instance" "block_producing_node_vm" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains.1.name
  display_name        = "BP Node"
  shape               = var.vm_shape

  shape_config {
    ocpus  = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.adact_preprod_bp_subnet.id
    display_name     = "bp_node_vnic"
    assign_public_ip = var.public_ip["block_producing_node_vm"]
    hostname_label   = format("${var.instance_prefix}-bp")
    nsg_ids          = [oci_core_network_security_group.nsg_bp_node.id]
  }

  source_details {
    source_type = "image"
    source_id   = var.image_id
  }

  metadata = {
    ssh_authorized_keys = file("/home/thomas/.oci/pem-adact-preprod-bp.pub")
    user_data           = base64encode(data.template_file.init_bp.rendered)
  }
}

# Block Volume for Producing Node
resource "oci_core_volume" "block_producing_node_volume" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains.1.name
  display_name        = "Block Producing Node Volume"
  size_in_gbs         = var.block_volume_size_in_gbs["block_producing_node_vm"]
  vpus_per_gb         = var.block_volume_vpus_per_gb["block_producing_node_vm"]
}

# Attach Block Volume to Block Producing Node
resource "oci_core_volume_attachment" "block_producing_node_volume_attachment" {
  instance_id = oci_core_instance.block_producing_node_vm.id
  volume_id   = oci_core_volume.block_producing_node_volume.id
  attachment_type = "paravirtualized"  # or "iscsi", depending on your preference
}

# Networking Security Group for Bastion Access
resource "oci_core_network_security_group" "nsg_bp_node" {
  compartment_id = var.compartment_ocid
#   vcn_id         = var.adact_preprod_ampere_vcn.id
  vcn_id         = oci_core_vcn.adact_preprod_vcn.id
  display_name   = "NSG BP Node"
}

# Egress Security Rule
resource "oci_core_network_security_group_security_rule" "nsg_bp_egress_rule" {
  network_security_group_id = oci_core_network_security_group.nsg_bp_node.id

  direction     = "EGRESS"
  protocol      = "6"
  destination   = "0.0.0.0/0"
  stateless     = false
}

# Ingress Security Rule for SSH from relay_node_vm_1 and relay_node_vm_2 internal IPs
resource "oci_core_network_security_group_security_rule" "nsg_bp_ingress_ssh_rule" {
    count = length(local.bp_node_ssh_source_ips)

  network_security_group_id = oci_core_network_security_group.nsg_bp_node.id

  direction     = "INGRESS"
  protocol      = "6"
  source        = element(local.bp_node_ssh_source_ips, count.index)
  stateless = false

    tcp_options {
    destination_port_range {
        min = 22
        max = 22
    }
    }

    depends_on = [oci_core_instance.relay_node_vm_1, oci_core_instance.relay_node_vm_2]
}

# Ingress Security Rule for port 3000 from relay_node_vm_1 and relay_node_vm_2 internal IPs
resource "oci_core_network_security_group_security_rule" "nsg_bp_ingress_port_3000_rule" {
    count = length(local.bp_node_ssh_source_ips)

  network_security_group_id = oci_core_network_security_group.nsg_bp_node.id

  direction     = "INGRESS"
  protocol      = "6"
  source        = element(local.bp_node_ssh_source_ips, count.index)
  stateless = false

    tcp_options {
    destination_port_range {
        min = 3000
        max = 3000
    }
    }

    depends_on = [oci_core_instance.relay_node_vm_1, oci_core_instance.relay_node_vm_2]
}


########################################### RELAY 1 NODE ###########################################
data "template_file" "init_relay1" {
  template = file("cloud-init-relay.yaml.tpl")

  vars = {
    relay_ssh_public_key = trimspace(file("/home/thomas/.oci/pem-adact-preprod-relay1.pub"))
    bp_node_ssh_public_key = trimspace(file("/home/thomas/.oci/pem-adact-preprod-bp.pub"))
    bp_node_ssh_private_key = indent(6, trimspace(file("/home/thomas/.oci/pem-adact-preprod-bp")))
    bashrc_file = indent(7, file(".bashrc.tpl"))
  }
}

# Relay Node VM #1
resource "oci_core_instance" "relay_node_vm_1" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains.1.name
  shape               = var.vm_shape
  shape_config {
    ocpus  = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }
  display_name        = "Relay Node VM #1"

  create_vnic_details {
    subnet_id        = oci_core_subnet.adact_preprod_relay1_subnet.id
    display_name     = "vnic_relay1_node"
    assign_public_ip = var.public_ip["relay_node_vm_1"]
    hostname_label   = format("${var.instance_prefix}-relay1")
    nsg_ids          = [oci_core_network_security_group.nsg_relay1_node.id]
  }
  source_details {
    source_type = "image"
    source_id    = var.image_id
  }
  metadata = {
    ssh_authorized_keys = file("/home/thomas/.oci/pem-adact-preprod-relay1.pub")
    user_data           = base64encode(data.template_file.init_relay1.rendered)
  }
}

# Block Volume for Relay Node VM #1
resource "oci_core_volume" "relay_node_vm_1_volume" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains.1.name
  display_name        = "Relay Node VM #1 Volume"
  size_in_gbs         = var.block_volume_size_in_gbs["relay_node_vm_1"]
  vpus_per_gb         = var.block_volume_vpus_per_gb["relay_node_vm_1"]
}

# Attach Block Volume to Relay Node VM #1
resource "oci_core_volume_attachment" "relay_node_vm_1_volume_attachment" {
  instance_id = oci_core_instance.relay_node_vm_1.id
  volume_id   = oci_core_volume.relay_node_vm_1_volume.id
  attachment_type = "paravirtualized"  # or "iscsi", depending on your preference
}

# Networking Security Group for Bastion Access
resource "oci_core_network_security_group" "nsg_relay1_node" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.adact_preprod_vcn.id
  display_name   = "NSG Relay1 Node"
}

# Egress Security Rule
resource "oci_core_network_security_group_security_rule" "nsg_relay1_egress_rule" {
  network_security_group_id = oci_core_network_security_group.nsg_relay1_node.id

  direction     = "EGRESS"
  protocol      = "6"
  destination   = "0.0.0.0/0"
  stateless     = false
}

# Ingress Security Rule for SSH from a predefined list of IPs
resource "oci_core_network_security_group_security_rule" "nsg_relay1_ingress_ssh_rule" {
  network_security_group_id = oci_core_network_security_group.nsg_relay1_node.id

  direction     = "INGRESS"
  protocol      = "6"
  source        = "81.109.249.75/32" # Add your predefined IPs here
  stateless = false

    tcp_options {
    destination_port_range {
        min = 22
        max = 22
    }
    }
}

# Ingress Security Rule for relay_ports from any source
resource "oci_core_network_security_group_security_rule" "nsg_relay1_ingress_rule" {
  count = length(var.relay_ports_open_to_all)

  network_security_group_id = oci_core_network_security_group.nsg_relay1_node.id

  direction = "INGRESS"
  protocol  = "6"  # TCP
  source    = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      min = var.relay_ports_open_to_all[count.index]
      max = var.relay_ports_open_to_all[count.index]
    }
  }
}



########################################### RELAY 2 NODE ###########################################
data "template_file" "init_relay2" {
  template = file("cloud-init-relay.yaml.tpl")

  vars = {
    relay_ssh_public_key = trimspace(file("/home/thomas/.oci/pem-adact-preprod-relay2.pub"))
    bp_node_ssh_public_key = trimspace(file("/home/thomas/.oci/pem-adact-preprod-bp.pub"))
    bp_node_ssh_private_key = indent(6, trimspace(file("/home/thomas/.oci/pem-adact-preprod-bp")))
    bashrc_file = indent(7, file(".bashrc.tpl"))
  }
}

# Relay Node VM #2
resource "oci_core_instance" "relay_node_vm_2" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains.1.name
  shape               = var.vm_shape
  shape_config {
    ocpus  = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }
  display_name        = "Relay Node VM #2"

  create_vnic_details {
    subnet_id        = oci_core_subnet.adact_preprod_relay2_subnet.id
    display_name     = "vnic_relay2_node"
    assign_public_ip = var.public_ip["relay_node_vm_2"]
    hostname_label   = format("${var.instance_prefix}-relay2")
    nsg_ids          = [oci_core_network_security_group.nsg_relay2_node.id]
  }
  source_details {
    source_type = "image"
    source_id    = var.image_id
  }
  metadata = {
    ssh_authorized_keys = file("/home/thomas/.oci/pem-adact-preprod-relay2.pub")
    user_data           = base64encode(data.template_file.init_relay2.rendered)
  }
}

# Block Volume for Relay Node VM #2
resource "oci_core_volume" "relay_node_vm_2_volume" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains.1.name
  display_name        = "Relay Node VM #2 Volume"
  size_in_gbs         = var.block_volume_size_in_gbs["relay_node_vm_2"]
  vpus_per_gb         = var.block_volume_vpus_per_gb["relay_node_vm_2"]
}

# Attach Block Volume to Relay Node VM #2
resource "oci_core_volume_attachment" "relay_node_vm_2_volume_attachment" {
  instance_id = oci_core_instance.relay_node_vm_2.id
  volume_id   = oci_core_volume.relay_node_vm_2_volume.id
  attachment_type = "paravirtualized"  # or "iscsi", depending on your preference
}

# Networking Security Group for Bastion Access
resource "oci_core_network_security_group" "nsg_relay2_node" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.adact_preprod_vcn.id
  display_name   = "NSG Relay2 Node"
}

# Egress Security Rule
resource "oci_core_network_security_group_security_rule" "nsg_relay2_egress_rule" {
  network_security_group_id = oci_core_network_security_group.nsg_relay2_node.id

  direction     = "EGRESS"
  protocol      = "6"
  destination   = "0.0.0.0/0"
  stateless     = false
}

# Ingress Security Rule for SSH from a predefined list of IPs
resource "oci_core_network_security_group_security_rule" "nsg_relay2_ingress_ssh_rule" {
  network_security_group_id = oci_core_network_security_group.nsg_relay2_node.id

  direction     = "INGRESS"
  protocol      = "6"
  source        = "81.109.249.75/32" # Add your predefined IPs here
  stateless = false

    tcp_options {
    destination_port_range {
        min = 22
        max = 22
    }
    }
}

# Ingress Security Rule for relay_ports from any source
resource "oci_core_network_security_group_security_rule" "nsg_relay2_ingress_rule" {
  count = length(var.relay_ports_open_to_all)

  network_security_group_id = oci_core_network_security_group.nsg_relay2_node.id

  direction = "INGRESS"
  protocol  = "6"  # TCP
  source    = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      min = var.relay_ports_open_to_all[count.index]
      max = var.relay_ports_open_to_all[count.index]
    }
  }
}


# Outputs
output "bp_node_vm_private_ip" {
  value = oci_core_instance.block_producing_node_vm.private_ip
}

# output "bp_node_vm_public_ip" {
#   value = oci_core_instance.block_producing_node_vm.public_ip
# }

output "relay1_node_vm_private_ip" {
  value = oci_core_instance.relay_node_vm_1.private_ip
}

output "relay2_node_vm_private_ip" {
  value = oci_core_instance.relay_node_vm_2.private_ip
}

output "relay1_node_vm_public_ip" {
  value = oci_core_instance.relay_node_vm_1.public_ip
}

output "relay2_node_vm_public_ip" {
  value = oci_core_instance.relay_node_vm_2.public_ip
}