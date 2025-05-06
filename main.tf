provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "main" {
  name     = "rg-demo"
  location = "East US"
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "vm" {
  name                 = "subnet-vm"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/27"]
}

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_group" "bastion" {
  name                = "nsg-bastion"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_public_ip" "main" {
  name                = "pip-demo"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

resource "azurerm_nat_gateway" "main" {
  name                = "natgw-demo"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.main.id
}

resource "azurerm_subnet_nat_gateway_association" "main" {
  subnet_id      = azurerm_subnet.vm.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_network_interface" "main" {
  name                = "nic-demo"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_managed_disk" "os" {
  name                 = "osdisk-demo"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 30
}

resource "azurerm_managed_disk" "data1" {
  name                 = "datadisk1-demo"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 4
}

resource "azurerm_managed_disk" "data2" {
  name                 = "datadisk2-demo"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 4
}

resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-demo"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.main.id]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = azurerm_managed_disk.os.name
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
  admin_password = "P@ssword1234!" # Change in production
}

resource "azurerm_virtual_machine_data_disk_attachment" "data1" {
  managed_disk_id    = azurerm_managed_disk.data1.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = 0
  caching            = "ReadWrite"
}

resource "azurerm_virtual_machine_data_disk_attachment" "data2" {
  managed_disk_id    = azurerm_managed_disk.data2.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = 1
  caching            = "ReadWrite"
}

resource "azurerm_bastion_host" "main" {
  name                = "bastion-demo"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.main.id
  }
}

resource "azurerm_storage_account" "logs" {
  name                     = "logstorage${random_id.unique.hex}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "random_id" "unique" {
  byte_length = 4
}

resource "azurerm_storage_management_policy" "logs_policy" {
  storage_account_id = azurerm_storage_account.logs.id

  rule {
    name    = "retention-policy"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        delete_after_days_since_modification_greater_than          = 365
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "vm_logs" {
  name               = "diag-vm"
  target_resource_id = azurerm_linux_virtual_machine.main.id
  storage_account_id = azurerm_storage_account.logs.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_dns_zone" "main" {
  name                = "example.com"
  resource_group_name = azurerm_resource_group.main.name
}
