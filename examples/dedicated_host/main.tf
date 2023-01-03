resource "random_id" "id" {
  byte_length = 2
}

resource "azurerm_resource_group" "rg" {
  count = var.create_resource_group ? 1 : 0

  location = var.location
  name     = coalesce(var.resource_group_name, "tf-vmmod-dedicated-host-${random_id.id.hex}")
}

locals {
  resource_group = {
    name     = try(azurerm_resource_group.rg[0].name, var.resource_group_name)
    location = var.location
  }
}

module "vnet" {
  source  = "Azure/vnet/azurerm"
  version = "4.0.0"

  resource_group_name = local.resource_group.name
  use_for_each        = true
  vnet_location       = local.resource_group.location
  address_space       = ["192.168.0.0/24"]
  vnet_name           = "vnet-vm-${random_id.id.hex}"
  subnet_names        = ["subnet-virtual-machine"]
  subnet_prefixes     = ["192.168.0.0/28"]
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "azurerm_dedicated_host_group" "example" {
  name                        = "example-dedicated-host-group"
  resource_group_name         = local.resource_group.name
  location                    = local.resource_group.location
  platform_fault_domain_count = 2
  automatic_placement_enabled = true
}

module "dedicate_host_group" {
  source = "../.."

  location                   = local.resource_group.location
  image_os                   = "linux"
  resource_group_name        = local.resource_group.name
  allow_extension_operations = false
  boot_diagnostics           = false
  dedicated_host_group_id    = azurerm_dedicated_host_group.example.id
  new_network_interface      = {
    ip_forwarding_enabled = false
    ip_configurations     = [
      {
        primary = true
      }
    ]
  }
  admin_ssh_keys = [
    {
      public_key = tls_private_key.ssh.public_key_openssh
      username   = "azureuser"
    }
  ]
  name    = "dhg-${random_id.id.hex}"
  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  os_simple = "UbuntuServer"
  size      = var.size
  subnet_id = module.vnet.vnet_subnets[0]

  depends_on = [azurerm_dedicated_host.example]
}

resource "azurerm_dedicated_host" "example" {
  name                    = "dh-${random_id.id.hex}"
  location                = local.resource_group.location
  dedicated_host_group_id = azurerm_dedicated_host_group.example.id
  sku_name                = var.dedicated_host_sku
  platform_fault_domain   = 1
}

module "dedicate_host" {
  source = "../.."

  location                   = local.resource_group.location
  image_os                   = "linux"
  resource_group_name        = local.resource_group.name
  allow_extension_operations = false
  boot_diagnostics           = false
  dedicated_host_id          = azurerm_dedicated_host.example.id
  new_network_interface      = {
    ip_forwarding_enabled = false
    ip_configurations     = [
      {
        primary = true
      }
    ]
  }
  admin_ssh_keys = [
    {
      public_key = tls_private_key.ssh.public_key_openssh
      username   = "azureuser"
    }
  ]
  name    = "dh-${random_id.id.hex}"
  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  os_simple = "UbuntuServer"
  size      = var.size
  subnet_id = module.vnet.vnet_subnets[0]
}