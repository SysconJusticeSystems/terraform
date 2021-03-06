# The purpose of this terraform runbook is to stand up the following resources:
#   1) Management Zone Resource Group
#   2) Management vnet
#   3) management Subnet
#   4) ssh jump box
#   5) CI server (vm only - managed disks)
#   6) Application Gateway with SSL certificate deployed - Wont actually do this natively - need to call the rm template which is a bit non-ideal
#   7) DNS Entry for CI server (This will actually point at the cname of the applicatoin gateway).
#   8) basic NSGs
#
#
# The details above have been determined by evaluating the configuration in place for previous IAAS based projects where the 
# application resource group and the management infrastructure resoure groups are distinct. 
# Based on this it was felt that we could provide this template as a basis for your own management zone, setting up the basic structure
# which can be customized as required.
#
# Prior to this you will need to generate an appropriate ssl certificate/use an available wildcard certificate if this is in existence
#


terraform {
    required_version = ">= 0.9.2"
    backend "azure" {
        resource_group_name = "webops"
        storage_account_name = "nomsstudiowebops"
        container_name = "terraform"
        key = "mgmt-test.terraform.tfstate"
        arm_subscription_id = "c27cfedb-f5e9-45e6-9642-0fad1a5c94e7"
        arm_tenant_id = "747381f4-e81f-4a43-bf68-ced6a1e14edf"
    }
}

variable "deploysshprivkey" {
    type = "string"
    default = ""
}
variable "deploysshpubkey" {
    type = "string"
    default = ""
}
variable "jumpadminsshpubkey" {
  type = "string"
  default = ""
}
variable "ci-admin" {
  type = "string"
  default = "deploy"
}
variable "jump-admin" {
  type = "string"
  default = "deploy"
}
variable "env-name" {
    type = "string"
    default = "changeme"
}
variable "rg-name" {
    type = "string"
    default = "changeme"
}
variable "keyvault-cert-name" {
    type = "string"
    default = "certDOTname"
}
variable "mgmt-vnet-space" {
    type = "string"
    default = "10.0.0.0/16"
}
variable "mgmt-subnet" {
    type = "string"
    default = "10.0.0.0/24"
}
variable "appgw-subnet" {
    type = "string"
    default = "10.0.1.0/24"
}
variable "ci-server-name" {
    type = "string"
    default = "changeme"
}
variable "ci-server-priv-ip" {
    type = "string"
    default = "10.0.0.10"
}
variable "jmp-server-name" {
    type = "string"
    default = "changeme"
}
variable "bastion-subnet" {
    type = "string"
    default = "10.0.3.0/24"
}
variable "jmp-server-priv-ip" {
    type = "string"
    default = "10.0.3.20"
}
variable "sslcertificate" {
    type = "string"
    default = "certificate value for the jenkins web site"
}
variable "sslcertificatepassword" {
    type = "string"
    default = "the password for the certificate above"
}
variable "tags" {
    type = "map"
    default {
        Service = "changeme"
        Environment = "changeme"
    }
}

resource "random_id" "ci-admin-password" {
    byte_length = 16
}
resource "random_id" "jmp-admin-password" {
    byte_length = 16
}

#The default location in this template is ukwest. Please check that this is the expected location for your service.

resource "azurerm_resource_group" "mgmt" {
    name = "${var.rg-name}"
    location = "ukwest"
    tags = "${var.tags}"
}

#you may not require the virtual network to be specified if you already have this provisioned.

resource "azurerm_virtual_network" "mgmt-vnet" {
  name                = "mgmt-vnet"
  address_space       = ["${var.mgmt-vnet-space}"]
  location            = "ukwest"
  resource_group_name = "${azurerm_resource_group.mgmt.name}"
}

resource "azurerm_subnet" "mgmt-subnet" {
  name                 = "mgmt-subnet"
  resource_group_name  = "${azurerm_resource_group.mgmt.name}"
  virtual_network_name = "${azurerm_virtual_network.mgmt-vnet.name}"
  address_prefix       = "${var.mgmt-subnet}"
}

resource "azurerm_subnet" "bastion-subnet" {
  name                 = "mgmt-subnet"
  resource_group_name  = "${azurerm_resource_group.mgmt.name}"
  virtual_network_name = "${azurerm_virtual_network.mgmt-vnet.name}"
  address_prefix       = "${var.bastion-subnet}"
}

resource "azurerm_subnet" "appgw-subnet" {
  name                 = "appgw-subnet"
  resource_group_name  = "${azurerm_resource_group.mgmt.name}"
  virtual_network_name = "${azurerm_virtual_network.mgmt-vnet.name}"
  address_prefix       = "${var.appgw-subnet}"
}

resource "azurerm_network_interface" "ci-nic" {
  name                = "ci-nic"
  location            = "ukwest"
  resource_group_name = "${azurerm_resource_group.mgmt.name}"

  ip_configuration {
    name                          = "ci-nic-config"
    subnet_id                     = "${azurerm_subnet.mgmt-subnet.id}"
    private_ip_address_allocation = "static"
    private_ip_address            = "${var.ci-server-priv-ip}"
  }
}

resource "azurerm_managed_disk" "ci-data-disk" {
  name                 = "ci-data-disk"
  location             = "ukwest"
  resource_group_name  = "${azurerm_resource_group.mgmt.name}"
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "1023"
}

resource "azurerm_virtual_machine" "ci" {
  name                  = "${var.ci-server-name}"
  location              = "ukwest"
  resource_group_name   = "${azurerm_resource_group.mgmt.name}"
  network_interface_ids = ["${azurerm_network_interface.ci-nic.id}"]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.ci-server-name}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name            = "${azurerm_managed_disk.ci-data-disk.name}"
    managed_disk_id = "${azurerm_managed_disk.ci-data-disk.id}"
    create_option   = "Attach"
    lun             = 1
    disk_size_gb    = "${azurerm_managed_disk.ci-data-disk.disk_size_gb}"
  }

  os_profile {
    computer_name  = "${var.ci-server-name}"
    admin_username = "${var.ci-admin}"
    admin_password = "${random_id.ci-admin-password.b64}"
    custom_data = "${base64encode( file( "../jenkins-cloudinit.txt" ) )}"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/${var.ci-admin}/.ssh/authorized_keys"
      key_data = "${var.deploysshpubkey}"
    }
  }

  tags {
        service = "${var.tags["Service"]}"
        environment = "${var.tags["Environment"]}"
        role = "other"
  }
}

resource "azurerm_public_ip" "jump" {
  name                         = "jmpPublicIp1"
  location                     = "ukwest"
  resource_group_name          = "${azurerm_resource_group.mgmt.name}"
  public_ip_address_allocation = "static"

  tags {
        service = "${var.tags["Service"]}"
        environment = "${var.tags["Environment"]}"
  }
}

resource "azurerm_network_interface" "jump-nic" {
  name                = "jump-nic"
  location            = "ukwest"
  resource_group_name = "${azurerm_resource_group.mgmt.name}"

  ip_configuration {
    name                          = "jump-nic-config"
    subnet_id                     = "${azurerm_subnet.bastion-subnet.id}"
    private_ip_address_allocation = "static"
    private_ip_address            = "${var.jmp-server-priv-ip}"
  }
}

resource "azurerm_virtual_machine" "jump" {
  name                  = "${var.jmp-server-name}"
  location              = "ukwest"
  resource_group_name   = "${azurerm_resource_group.mgmt.name}"
  network_interface_ids = ["${azurerm_network_interface.jump-nic.id}"]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.jmp-server-name}-${var.tags["Service"]}-os"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.jmp-server-name}"
    admin_username = "${var.jump-admin}"
    admin_password = "${random_id.jmp-admin-password.b64}"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/${var.jump-admin}/.ssh/authorized_keys"
      key_data = "${var.jumpadminsshpubkey}"
    }
  }

  tags {
        service = "${var.tags["Service"]}"
        environment = "${var.tags["Environment"]}"
        role = "other"
  }
}

resource "azurerm_template_deployment" "management-appgw" {
  name = "appgwdeployment"
  resource_group_name = "${azurerm_resource_group.mgmt.name}"
  deployment_mode = "Incremental"
  template_body = "${file("../mgmt-appgw.template.json")}"

  parameters {
      subnetPrefix = "${azurerm_virtual_network.mgmt-vnet.address_space}"
      applicationGatewaySize = "WAF_Medium"
      capacity = "2"
      backendIpAddress1 = "${azurerm_network_interface.ci-nic.private_ip_address}"
      wafEnabled = true
      wafRuleSetType = "OWASP"
      wafRuleSetVersion = "3.0"
      wafMode = "Prevention"
      appGWName = "${var.tags["Service"]}-mgmt-AppGW"
      appGWPubIpName = "${var.tags["Service"]}-mgmt-AppGW-Pub-IP"
      virtualNetworkName = "${azurerm_virtual_network.mgmt-vnet.name}"
      subnetName = "${azurerm_subnet.appgw-subnet.name}"
      appGatewaySubnet = "${azurerm_subnet.appgw-subnet.address_prefix}"
      sslcertificate = "${var.sslcertificate}"
      sslcertificatepassword = "${var.sslcertificatepassword}"
      keyVaultCertName = "${var.keyvault-cert-name}"
      service = "${var.tags["Service"]}"
      environment = "${var.tags["Environment"]}"
      role = "other"
  }
}

output "appgwcname" {
  value = "${azurerm_template_deployment.management-appgw.outputs["appgwcname"]}"
}

resource "azurerm_network_security_group" "mgmt" {
  name                = "mgmtsecuritygroup"
  location            = "ukwest"
  resource_group_name = "${azurerm_resource_group.mgmt.name}"

  security_rule {
    name                       = "ssh-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "${azurerm_network_interface.jump-nic.private_ip_address}"
  }
  security_rule {
    name                       = "ssh-management-zone-jmp"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${azurerm_network_interface.jump-nic.private_ip_address}"
    destination_address_prefix = "${azurerm_subnet.mgmt-subnet.address_prefix}"
  }
  security_rule {
    name                       = "ssh-management-zone-ci"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${azurerm_network_interface.ci-nic.private_ip_address}"
    destination_address_prefix = "${azurerm_subnet.mgmt-subnet.address_prefix}"
  }
  security_rule {
    name                       = "ssh-bastion-zone-ci"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${azurerm_network_interface.ci-nic.private_ip_address}"
    destination_address_prefix = "${azurerm_subnet.bastion-subnet.address_prefix}"
  }
  security_rule {
    name                       = "https-inbound"
    priority                   = 500
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "${azurerm_subnet.appgw-subnet.address_prefix}"
  }
  security_rule {
    name                       = "appgw-to-ci"
    priority                   = 600
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "${azurerm_subnet.appgw-subnet.address_prefix}"
    destination_address_prefix = "${azurerm_subnet.mgmt-subnet.address_prefix}"
  }
  security_rule {
    name                       = "default-deny"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_dns_cname_record" "cname" {
    name = "ci"
    zone_name = "${var.tags["Service"]}.hmpps.dsd.io"
    resource_group_name = "changeme"
    ttl = "300"
    record = "${azurerm_template_deployment.management-appgw.outputs["appgwcname"]}"
    tags = "${var.tags}"
}
