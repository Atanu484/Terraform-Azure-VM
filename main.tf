terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.97.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "atanu-rg" {
  name     = "atanu-resources"
  location = "East Us"
  tags = {
    environment = "dev"
  }
}

// Create a virtual network
resource "azurerm_virtual_network" "atanu-vn" {
  name                = "atanu-network"
  resource_group_name = azurerm_resource_group.atanu-rg.name
  location            = azurerm_resource_group.atanu-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

// Create a subnet
resource "azurerm_subnet" "atanu-subnet" {
  name                 = "atanu-subnet"
  resource_group_name  = azurerm_resource_group.atanu-rg.name
  virtual_network_name = azurerm_virtual_network.atanu-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

// Create a network security group
resource "azurerm_network_security_group" "atanu-sg" {
  name                = "atanu-sg"
  location            = azurerm_resource_group.atanu-rg.location
  resource_group_name = azurerm_resource_group.atanu-rg.name

  tags = {
    environment = "dev"
  }
}

// Create a network security rule
resource "azurerm_network_security_rule" "atanu-dev-rule" {
  name                        = "mtc-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.atanu-rg.name
  network_security_group_name = azurerm_network_security_group.atanu-sg.name
}

// Associate the network security group with the subnet
resource "azurerm_subnet_network_security_group_association" "mtc-sga" {
  subnet_id                 = azurerm_subnet.atanu-subnet.id
  network_security_group_id = azurerm_network_security_group.atanu-sg.id
}

// Create a network interface
resource "azurerm_public_ip" "atanu-ip" {
  name                = "atanu-ip"
  resource_group_name = azurerm_resource_group.atanu-rg.name
  location            = azurerm_resource_group.atanu-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

// Create a network interface
resource "azurerm_network_interface" "atanu-nic" {
  name                = "atanu-nic"
  location            = azurerm_resource_group.atanu-rg.location
  resource_group_name = azurerm_resource_group.atanu-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.atanu-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.atanu-ip.id
  }

  tags = {
    environment = "dev"
  }
}

// Create a virtual machine
resource "azurerm_linux_virtual_machine" "atanu-vm" {
  name                  = "atanu-vm"
  resource_group_name   = azurerm_resource_group.atanu-rg.name
  location              = azurerm_resource_group.atanu-rg.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.atanu-nic.id]

  custom_data = filebase64("customdata.tpl")

  //
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/mtcazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
      command = templatefile("${var.host_os}-ssh-script.tpl", {
          hostname = self.public_ip_address,
          user = "adminuser",
          identityfile = "~/.ssh/mtcazurekey"
      })
      interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }
}

// Create a load balancer
data "azurerm_public_ip" "mtc-ip-data" {
    name = azurerm_public_ip.atanu-ip.name
    resource_group_name = azurerm_resource_group.atanu-rg.name
}

output "public_ip_address" {
    value = "${azurerm_linux_virtual_machine.atanu-vm.name}: ${data.azurerm_public_ip.mtc-ip-data.ip_address}"
}