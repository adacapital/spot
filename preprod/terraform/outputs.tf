# #############################################################################
# # OUTPUTS
# #############################################################################
output "linux_vm_names" {
  value = [for x in azurerm_linux_virtual_machine.linux_vms : x.name]
}

output "linux_vm_private_ip_address" {
  value = { for x in azurerm_linux_virtual_machine.linux_vms : x.name => x.private_ip_address }
}

output "linux_vm_public_ip_address" {
  value = {for x in azurerm_linux_virtual_machine.linux_vms : x.name => x.public_ip_address}
}

output "load-balancer-pip" {
  value = {for k, x in local.lb_list : azurerm_lb.this[k].name => azurerm_public_ip.lbpip[k].ip_address}
}