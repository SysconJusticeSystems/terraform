resource "azurerm_resource_group" "hub-bounce-dev" {
    name = "hub-bounce-dev"
    location = "ukwest"
}

resource "azurerm_public_ip" "hub-bounce-dev-ip" {
  name                         = "hub-bounce-dev-ip"
  location                     = "ukwest"
  resource_group_name          = "${azurerm_resource_group.hub-bounce-dev.name}"
  public_ip_address_allocation = "static"
}

resource "azurerm_network_security_group" "hub-bounce-dev-nsg" {
  name                = "hub-bounce-dev-nsg"
  location            = "ukwest"
  resource_group_name = "${azurerm_resource_group.hub-bounce-dev.name}"

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
  resource_group_name  = "${azurerm_resource_group.hub-bounce-dev.name}"
  virtual_network_name = "${azurerm_virtual_network.hub-bounce-dev-vnet.name}"
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_virtual_network" "hub-bounce-dev-vnet" {
  name                = "hub-bounce-dev-vnet"
  resource_group_name = "${azurerm_resource_group.hub-bounce-dev.name}"
  address_space       = ["10.0.2.0/24"]
  location            = "ukwest"
}


resource "azurerm_network_interface" "hub-bounce-dev-ni" {
  name                      = "hub-bounce-dev-ni"
  location                  = "ukwest"
  resource_group_name       = "${azurerm_resource_group.hub-bounce-dev.name}"
  network_security_group_id = "${azurerm_network_security_group.hub-bounce-dev-nsg.id}"

  ip_configuration {
    name                          = "hub-bounce-dev-ni-ip"
    subnet_id                     = "${azurerm_subnet.default.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.hub-bounce-dev-ip.id}"
  }
}

resource "azurerm_virtual_machine" "hub-bounce-dev-vm" {
  name                  = "hub-bounce-dev-vm"
  location              = "ukwest"
  resource_group_name   = "${azurerm_resource_group.hub-bounce-dev.name}"
  network_interface_ids = ["${azurerm_network_interface.hub-bounce-dev-ni.id}"]
  vm_size               = "Basic_A3"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "hub-bounce-dev-vm-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name              = "hub-bounce-dev-temp"
    caching           = "None"
    create_option     = "Attach"
    managed_disk_type = "Standard_LRS"
    lun               = 0
    disk_size_gb      = "150"
  }

  os_profile {
    computer_name  = "hub-bounce-dev"
    admin_username = "provisioning"
    admin_password = "ThisIsDisabled111!"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/provisioning/.ssh/authorized_keys"
      key_data = "${file("${path.module}/sshkey.pub")}"
    }
  }
}
