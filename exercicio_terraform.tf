variable "prefix" {
  default = "exerc_terraform_azure_MySQL"
}

terraform {
  required_version = ">= 0.14.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.56"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = false
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-resources"
  location = "eastus"
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "publicip" {
  name                = "myPublicIP"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "myterraformnsg" {
  name                = "myNetworkSecurityGroup"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.main.name

    security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
}

resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id
}

resource "azurerm_virtual_machine" "main" {
  name                  = "${var.prefix}-vm"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = [azurerm_network_interface.main.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}

resource "null_resource" "upload_db" {
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = "testadmin"
      password = "Password1234!"
      host     = "${azurerm_public_ip.publicip.ip_address}"
    }
    source      = "mysql"
    destination = "/home/testadmin"
  }
  depends_on = [azurerm_virtual_machine.main, azurerm_public_ip.publicip]
}

resource "null_resource" "deploy_db2" {
  triggers = {
    order = null_resource.upload_db.id
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "testadmin"
      password = "Password1234!"
      host     = "${azurerm_public_ip.publicip.ip_address}"
    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y mysql-server-5.7",
      "sudo mysql < /home/testadmin/mysql/config/user.sql",
      "sudo cp -f /home/testadmin/mysql/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo service mysql restart",
    ]
  }
  depends_on = [azurerm_virtual_machine.main, azurerm_public_ip.publicip]
}

output "IP" {
    value = "${azurerm_public_ip.publicip.ip_address}"
}






