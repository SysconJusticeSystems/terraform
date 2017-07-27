resource "azurerm_resource_group" "hub-bounce-prod" {
    name = "hub-bounce-prod"
    location = "uksouth"
}

resource "azurerm_public_ip" "hub-bounce-prod-ip" {
  name                         = "hub-bounce-prod-ip"
  location                     = "uksouth"
  resource_group_name          = "${azurerm_resource_group.hub-bounce-prod.name}"
  public_ip_address_allocation = "static"
}

resource "azurerm_network_security_group" "hub-bounce-prod-nsg" {
  name                = "hub-bounce-prod-nsg"
  location            = "uksouth"
  resource_group_name = "${azurerm_resource_group.hub-bounce-prod.name}"

  security_rule {
    name                       = "default-allow-ssh"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "TCP"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = "${azurerm_resource_group.hub-bounce-prod.name}"
  virtual_network_name = "${azurerm_virtual_network.hub-bounce-prod-vnet.name}"
  address_prefix       = "10.0.1.0/24"
}

resource "azurerm_virtual_network" "hub-bounce-prod-vnet" {
  name                = "hub-bounce-prod-vnet"
  resource_group_name = "${azurerm_resource_group.hub-bounce-prod.name}"
  address_space       = ["10.0.1.0/24"]
  location            = "uksouth"
}

resource "azurerm_network_interface" "hub-bounce-prod-ni" {
  name                = "hub-bounce-prod-ni"
  location            = "uksouth"
  resource_group_name = "${azurerm_resource_group.hub-bounce-prod.name}"

  ip_configuration {
    name                          = "hub-bounce-prod-ni-ip"
    subnet_id                     = "${azurerm_subnet.default.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.hub-bounce-prod-ip.id}"
  }
}

resource "azurerm_virtual_machine" "hub-bounce-prod-vm" {
  name                  = "hub-bounce-prod-vm"
  location              = "uksouth"
  resource_group_name   = "${azurerm_resource_group.hub-bounce-prod.name}"
  network_interface_ids = ["${azurerm_network_interface.hub-bounce-prod-ni.id}"]
  vm_size               = "Basic_A0"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "hub-bounce-prod-vm-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "hub-bounce-prod"
    admin_username = "lazzurs"
    admin_password = "ThisIsDisabled111!"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/lazzurs/.ssh/authorized_keys"
      key_data = "ssh-rsa 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"
    }
  }
}
