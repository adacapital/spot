# locals {
#   bp_node_ssh_source_ips = [oci_core_instance.relay_node_vm_1.private_ip, oci_core_instance.relay_node_vm_2.private_ip]
# }

locals {
  bp_node_ssh_source_ips = [format("%s/32", oci_core_instance.relay_node_vm_1.private_ip), format("%s/32", oci_core_instance.relay_node_vm_2.private_ip)]
  bp_node_ssh_source_ips_ssh = [format("%s/32", oci_core_instance.relay_node_vm_1.private_ip), format("%s/32", oci_core_instance.relay_node_vm_2.private_ip), "81.109.249.75/32"]
}
