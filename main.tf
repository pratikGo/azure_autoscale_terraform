terraform {
  required_version = ">=0.12"
  
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}
provider "azurerm" {
  features {}
}
locals {
  first_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+wWK73dCr+jgQOAxNsHAnNNNMEMWOHYEccp6wJm2gotpr9katuF/ZAdou5AaW1C61slRkHRkpRRX9FA9CYBiitZgvCCz+3nWNN7l/Up54Zps/pHWGZLHNJZRYyAB6j5yVLMVHIHriY49d/GZTZVNB8GoJv9Gakwc/fuEZYYl4YDFiGMBP///TzlI4jhiJzjKnEvqPFki5p2ZRJqcbCiF4pJrxUQR/RXqVFQdbRLZgYfJ8xGB878RENq3yQ39d8dVOkq4edbkzwcUmwwwkYVPIoDGsYLaRHnG+To7FvMeyO7xDVQkMKzopTQV8AuKpyvpqu0a9pWOMaiCyDytO7GGN you@me.com"
}

resource "azurerm_resource_group" "vmss" {
 name     = var.resource_group_name
 location = var.location
}

resource "azurerm_virtual_network" "vmss" {
 name                = "${var.resource_group_name}-vnet"
 address_space       = ["10.0.0.0/16"]
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name
}

resource "azurerm_subnet" "vmss" {
 name                 = "${var.resource_group_name}-subnet"
 resource_group_name  = azurerm_resource_group.vmss.name
 virtual_network_name = azurerm_virtual_network.vmss.name
 address_prefixes       = ["10.0.2.0/24"]
}
resource "azurerm_public_ip" "vmss" {
 name                         = "${var.resource_group_name}-publicip"
 location                     = var.location
 resource_group_name          = azurerm_resource_group.vmss.name
 allocation_method            = "Static"
}
resource "azurerm_lb" "vmss" {
 name                = "load-balancer"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name

 frontend_ip_configuration {
   name                 = "PublicIPAddress"
   public_ip_address_id = azurerm_public_ip.vmss.id
 }
}
resource "azurerm_lb_probe" "vmss" {
 resource_group_name = azurerm_resource_group.vmss.name
 loadbalancer_id     = azurerm_lb.vmss.id
 name                = "ssh-running-probe"
 port                = var.application_port
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
 loadbalancer_id     = azurerm_lb.vmss.id
 name                = "BackEndAddressPool"
}
resource "azurerm_lb_rule" "lbnatrule" {
   resource_group_name            = azurerm_resource_group.vmss.name
   loadbalancer_id                = azurerm_lb.vmss.id
   name                           = "http"
   protocol                       = "Tcp"
   frontend_port                  = var.application_port
   backend_port                   = var.application_port
   backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpepool.id]
   frontend_ip_configuration_name = "PublicIPAddress"
   probe_id                       = azurerm_lb_probe.vmss.id
}
resource "azurerm_lb_nat_pool" "vmss"{
  resource_group_name = azurerm_resource_group.vmss.name
  loadbalancer_id = azurerm_lb.vmss.id
  name = "natpool"
  frontend_ip_configuration_name =  "PublicIPAddress"
  frontend_port_start = 50000
  frontend_port_end = 50010
  backend_port = 22
  protocol = "Tcp"
}
resource "azurerm_network_security_group" "vmss"{
  name = "${var.resource_group_name}-nsg"
  location = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name
}
resource "azurerm_network_interface" "vmss" {
  name                =  "${var.resource_group_name}-nsg-nic"
  location            = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vmss.id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_network_interface_security_group_association" "vmss" {
  network_interface_id      = azurerm_network_interface.vmss.id
  network_security_group_id = azurerm_network_security_group.vmss.id
}
resource "azurerm_network_security_rule" "rule1" {
  name                        = "HTTP"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.vmss.name
  network_security_group_name = azurerm_network_security_group.vmss.name
}

resource "azurerm_network_security_rule" "rule2" {
  name                        = "TCP"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.vmss.name
  network_security_group_name = azurerm_network_security_group.vmss.name
}

resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                            = "scaleset"
  resource_group_name             = azurerm_resource_group.vmss.name
  location                        = azurerm_resource_group.vmss.location
  sku                             = "Standard_B1S"
  instances                       = 2
  admin_username                  = var.admin_user
  admin_ssh_key {
    username   = "azureuser"
    public_key = local.first_public_key
  }

  source_image_id = "/subscriptions/51312ad3-a484-480b-a217-075484b1dfd9/resourceGroups/VM-Image/providers/Microsoft.Compute/images/temporary-vm-image-20220712111815"
   os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
   name    = azurerm_network_interface.vmss.name
   primary = true

   ip_configuration {
     name                                   = "internal"
     subnet_id                              = azurerm_subnet.vmss.id
     load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
     load_balancer_inbound_nat_rules_ids = [azurerm_lb_nat_pool.vmss.id]
     primary = true
   }
 }
 depends_on = [azurerm_lb_probe.vmss]

 lifecycle {
    ignore_changes = [instances]
  }
}

resource "azurerm_monitor_autoscale_setting" "vmss" {
  name                = "autoscale-config"
  resource_group_name = azurerm_resource_group.vmss.name
  location            = azurerm_resource_group.vmss.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id

  profile {
    name = "AutoScale"

    capacity {
      default = 2
      minimum = 1
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "3"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 20
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT1M"
      }
    }
  }
}
