# Create your own VNet with 2 subnets
# Use the same CIDR blocks as you used when we created the 2-subnet VNet manually
# Create the app VM's NSG to allow ports 22, 80 and 3000
# Create the DB VM's NSG to allow:
#   SSH
#   Mongo DB from public-subnet CIDR block
#   Deny everything else
# Create the app-instance and db-instance in the VNet created by Terraform, and to use the NSGs created by Terraform

 terraform {

  # Use azurem blob storage as backend for terraform state files
  backend "azurerm" {
      resource_group_name  = "tech264"
      storage_account_name = "tech264karistfstate"
      container_name       = "tfstate"
      key                  = "terraform.tfstate"
  }

 }
 
# Define provider
provider "azurerm" {
  features {}
  
  # Authenticate through Azure CLI
  use_cli                         = true
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}


# Virtual Network

resource "azurerm_virtual_network" "my_vnet" {

  name                = "tech264-karis-tf-2-subnet-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name

  tags = {
    Owner = "Karis"
    Name  = "tech264-karis-tf-2-subnet-vnet"
  }

}

# Public subnet

resource "azurerm_subnet" "public_subnet" {
  name                 = "public-subnet"
  resource_group_name  = var.resource_group_name
  address_prefixes     = ["10.0.2.0/24"]

  # Link subnet to VNet
  virtual_network_name = azurerm_virtual_network.my_vnet.name

}

# Private subnet

resource "azurerm_subnet" "private_subnet" {
  name                              = "private-subnet"
  resource_group_name               = var.resource_group_name
  address_prefixes                  = ["10.0.3.0/24"]
  
  # Link subnet to VNet
  virtual_network_name              = azurerm_virtual_network.my_vnet.name
  # Enable private network
  private_endpoint_network_policies = "Enabled"
}


## NSG ##

# App Network Segurity Group
# - allow: SSH (22), HTTP (80), NodeJS port (3000) from any

resource "azurerm_network_security_group" "app_vm_nsg" {

  name                = "tech264-karis-tf-app-vm-nsg"
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name


  # Allow SSH rule
  security_rule {
    name                       = "Allow_SSH"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"


  }

  # Allow HTTP rule
  security_rule {
    name                       = "Allow_HTTP"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"

  }

  # Allow Port 3000 rule
  security_rule {
    name                       = "Allow_port_3000"
    priority                   = 330
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"

  }

  tags = {

    Owner = "Karis"
  }
}


# DB Network Segurity Group

resource "azurerm_network_security_group" "db_vm_nsg" {

  name                = "tech264-karis-tf-db-vm-nsg"
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name


  # Allow SSH rule
  security_rule {
    name                       = "Allow_SSH"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"

  }

  # Allow MongoDB rule
  security_rule {
    name                       = "Allow_MondoDB"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "27017"
    source_address_prefix      = azurerm_subnet.public_subnet.address_prefixes[0]
    destination_address_prefix = "*"

  }

  # Deny everything rule
  security_rule {
    name                       = "Deny_everything"
    priority                   = 500
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"

  }

  tags = {
    Owner = "Karis"
  }
}



# DB

# NIC

resource "azurerm_network_interface" "db_nic" {
  name                = "tech264-karis-tf-db-nic"
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private_subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    Owner = "Karis"
  }
}

# NIC - NSG association
resource "azurerm_network_interface_security_group_association" "db_nic_2_nsg" {
  network_interface_id      = azurerm_network_interface.db_nic.id
  network_security_group_id = azurerm_network_security_group.db_vm_nsg.id
}

# DB Virtual Machine

resource "azurerm_linux_virtual_machine" "db_vm" {
  name                = "tech264-karis-tf-db-vm"
  resource_group_name = var.resource_group_name
  location            = var.resource_group_location
  size                = var.vm_instance_size
  admin_username      = var.vm_username


  network_interface_ids = [
    azurerm_network_interface.db_nic.id,
  ]

  admin_ssh_key {
    username   = var.vm_username
    public_key = var.vm_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_disk_type
  }

  source_image_id = var.vm_db_image_id

  tags = {
    Owner = "Karis"
  }
}

# APP 

# Public IP
resource "azurerm_public_ip" "app_public_ip" {
  name                = "tech264-karis-app-public-ip"
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
}

# NIC
resource "azurerm_network_interface" "app_nic" {
  name                = "tech264-karis-tf-app-nic"
  location            = var.resource_group_location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app_public_ip.id
  }

  tags = {
    Owner = "Karis"
  }
}

# NIC - NSG association

resource "azurerm_network_interface_security_group_association" "app_nic_2_nsg" {
  network_interface_id      = azurerm_network_interface.app_nic.id
  network_security_group_id = azurerm_network_security_group.app_vm_nsg.id
}


# APP Virtual Machine

resource "azurerm_linux_virtual_machine" "app_vm" {
  name                = "tech264-karis-tf-app-vm"
  resource_group_name = var.resource_group_name
  location            = var.resource_group_location
  size                = var.vm_instance_size
  admin_username      = var.vm_username

  # Dependency from db
  depends_on = [azurerm_linux_virtual_machine.db_vm]

  network_interface_ids = [
    azurerm_network_interface.app_nic.id,
  ]

  admin_ssh_key {
    username   = var.vm_username
    public_key = var.vm_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_disk_type
  }

  source_image_id = var.vm_app_image_id

  tags = {
    Owner = "Karis"
  }

  user_data = base64encode(templatefile("./scripts/app-vm-image-provision.tftpl",
    { DB_PRIVATE_IP = azurerm_network_interface.db_nic.private_ip_address }
  ))

}

