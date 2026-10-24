locals {
  common_tags = merge(var.tags, {
    Project   = "InfraPulse-Azure"
    ManagedBy = "Terraform"
  })
}

resource "azurerm_resource_group" "infrapulse" {
  name     = "${var.project_name}-rg"
  location = var.azure_region
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "infrapulse" {
  name                = "${var.project_name}-vnet"
  address_space       = ["10.42.0.0/16"]
  location            = azurerm_resource_group.infrapulse.location
  resource_group_name = azurerm_resource_group.infrapulse.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "public" {
  name                 = "${var.project_name}-subnet"
  resource_group_name  = azurerm_resource_group.infrapulse.name
  virtual_network_name = azurerm_virtual_network.infrapulse.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_network_security_group" "infrapulse" {
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.infrapulse.location
  resource_group_name = azurerm_resource_group.infrapulse.name
  tags                = local.common_tags
}

resource "azurerm_network_security_rule" "http_in" {
  name                        = "Allow-Infrapulse-HTTP-8080"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefixes     = var.http_source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.infrapulse.name
  network_security_group_name = azurerm_network_security_group.infrapulse.name
  description                 = "Allow the demo endpoint only from the caller's configured CIDRs."
}

resource "azurerm_network_security_rule" "https_out" {
  name                        = "Allow-HTTPS-Out"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.infrapulse.name
  network_security_group_name = azurerm_network_security_group.infrapulse.name
  description                 = "HTTPS for cloud-init package downloads and VM agent control traffic."
}

resource "azurerm_network_security_rule" "http_out" {
  name                        = "Allow-HTTP-Out"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.infrapulse.name
  network_security_group_name = azurerm_network_security_group.infrapulse.name
  description                 = "HTTP for Ubuntu package mirrors used during bootstrap."
}

resource "azurerm_network_security_rule" "deny_internet_out" {
  name                        = "Deny-Other-Internet-Out"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.infrapulse.name
  network_security_group_name = azurerm_network_security_group.infrapulse.name
  description                 = "Limit general internet egress to the HTTP/HTTPS rules above."
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.infrapulse.id
}

resource "azurerm_public_ip" "infrapulse" {
  name                = "${var.project_name}-pip"
  location            = azurerm_resource_group.infrapulse.location
  resource_group_name = azurerm_resource_group.infrapulse.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "infrapulse" {
  name                = "${var.project_name}-nic"
  location            = azurerm_resource_group.infrapulse.location
  resource_group_name = azurerm_resource_group.infrapulse.name
  tags                = local.common_tags
  # checkov:skip=CKV_AZURE_119:An external HTTP endpoint is required; inbound NSG access is limited to the configured client CIDRs.

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.infrapulse.id
  }
}

resource "azurerm_linux_virtual_machine" "infrapulse" {
  name                            = "${var.project_name}-vm"
  computer_name                   = "infrapulse"
  location                        = azurerm_resource_group.infrapulse.location
  resource_group_name             = azurerm_resource_group.infrapulse.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.infrapulse.id]
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  # checkov:skip=CKV_AZURE_50:No custom VM extensions are declared; administrative scripts use the image's Azure VM agent Run Command channel.
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    app_content            = base64encode(file("${path.module}/../app/server.py"))
    service_content        = base64encode(file("${path.module}/../systemd/infrapulse.service"))
    health_service_content = base64encode(file("${path.module}/../systemd/infrapulse-health.service"))
    health_timer_content   = base64encode(file("${path.module}/../systemd/infrapulse-health.timer"))
    healthcheck_content    = base64encode(file("${path.module}/../scripts/healthcheck.sh"))
  }))

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "${var.project_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gib
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = local.common_tags

  depends_on = [azurerm_subnet_network_security_group_association.public]
}
