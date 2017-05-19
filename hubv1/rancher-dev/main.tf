terraform {
    required_version = ">= 0.9.5"
    backend "azure" {
        resource_group_name = "webops"
        storage_account_name = "nomsstudiowebops"
        container_name = "terraform"
        key = "hubv1-rancher-dev.terraform.tfstate"
        arm_subscription_id = "c27cfedb-f5e9-45e6-9642-0fad1a5c94e7"
        arm_tenant_id = "747381f4-e81f-4a43-bf68-ced6a1e14edf"
    }
}

variable "name" {
    type = "string"
    default = "hubv1-rancher-dev"
}
variable "tags" {
    type = "map"
    default {
        Service = "Digital Hub v1"
        Environment = "rancher-dev"
    }
}

resource "azurerm_resource_group" "group" {
    name = "${var.name}"
    location = "ukwest"
    tags = "${var.tags}"
}

resource "azurerm_virtual_network" "net" {
    name = "${var.name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    location = "${azurerm_resource_group.group.location}"
    address_space = ["192.168.117.0/24"]
    tags = "${var.tags}"
}

resource "azurerm_subnet" "sub" {
    name = "${var.name}-main"
    resource_group_name = "${azurerm_resource_group.group.name}"
    virtual_network_name = "${azurerm_virtual_network.net.name}"
    address_prefix = "192.168.117.0/28"
}

resource "azurerm_public_ip" "public" {
    name = "${var.name}"
    resource_group_name = "${azurerm_resource_group.group.name}"
    location = "${azurerm_resource_group.group.location}"
    public_ip_address_allocation = "dynamic"
    tags = "${var.tags}"
}

resource "azurerm_network_interface" "nic" {
    name = "${var.name}-nic0"
    resource_group_name = "${azurerm_resource_group.group.name}"
    location = "${azurerm_resource_group.group.location}"

    ip_configuration {
        name = "main"
        subnet_id = "${azurerm_subnet.sub.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id = "${azurerm_public_ip.public.id}"
    }
}

resource "azurerm_virtual_machine" "vm" {
    name = "${var.name}-vm0"
    resource_group_name = "${azurerm_resource_group.group.name}"
    location = "${azurerm_resource_group.group.location}"
    network_interface_ids = ["${azurerm_network_interface.nic.id}"]
    vm_size = "Standard_A1"

    storage_image_reference {
        publisher = "Canonical"
        offer = "UbuntuServer"
        sku = "16.04-LTS"
        version = "latest"
    }

    storage_os_disk {
        name = "${var.name}-disk0"
        managed_disk_type = "Standard_LRS"
        create_option = "FromImage"
    }
    delete_os_disk_on_termination = true

    os_profile {
        computer_name = "${var.name}-vm0"
        admin_username = "webops"
        admin_password = "ThisIsDisabled127386213!!!"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path = "/home/webops/.ssh/authorized_keys"
            key_data = "${file("${path.module}/sshkey.pub")}"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo apt-get install unattended-updates",
            "echo we could do so much more"
        ]
        connection {
            type = "ssh"
            user = "webops"
            host = "${azurerm_public_ip.public.ip_address}"
        }
    }
}
