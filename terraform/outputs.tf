output "resource_group_name" {
  description = "Resource group containing the InfraPulse Azure deployment."
  value       = azurerm_resource_group.infrapulse.name
}

output "vm_name" {
  description = "Azure Linux VM name."
  value       = azurerm_linux_virtual_machine.infrapulse.name
}

output "public_ip" {
  description = "Public IPv4 address for the HTTP endpoint."
  value       = azurerm_public_ip.infrapulse.ip_address
}

output "health_url" {
  description = "Public health endpoint; access is limited by http_source_cidrs."
  value       = "http://${azurerm_public_ip.infrapulse.ip_address}:8080/health"
}

output "run_command_hint" {
  description = "Azure CLI command for administrative scripts without inbound SSH."
  value       = "az vm run-command invoke --resource-group ${azurerm_resource_group.infrapulse.name} --name ${azurerm_linux_virtual_machine.infrapulse.name} --command-id RunShellScript --scripts 'systemctl status infrapulse'"
}
