terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.99.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "0826dc73-80c6-4500-b770-ad5f02f4898a"
}

# ============================
# Resource Group
# ============================
resource "azurerm_resource_group" "main" {
  name     = "grupo-recurso-jorge"
  location = "East US"
}

# ============================
# Virtual Network
# ============================
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet_lab1"
  address_space       = ["10.0.0.0/24"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# ============================
# Subnet
# ============================
resource "azurerm_subnet" "subnet" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

# ============================
# Network Security Groups 
# ============================
resource "azurerm_network_security_group" "nsg_linux" {
  name                = "nsg-linux"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}
resource "azurerm_network_security_rule" "ssh_linux" {
  name                        = "Allow-SSH"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_linux.name
}
resource "azurerm_network_security_rule" "icmp_linux" {
  name                        = "Allow-ICMP-Linux"
  priority                    = 1010
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Icmp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_linux.name
}
resource "azurerm_network_security_rule" "awx_web_linux" {
  name                        = "Allow-AWX-Web"
  priority                    = 1020
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_linux.name
}
resource "azurerm_network_security_rule" "zabbix_web_linux" {
  name                        = "Allow-Zabbix-Web"
  priority                    = 1030
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8081"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_linux.name
}
resource "azurerm_network_security_rule" "awx_nodeport" {
  name                        = "Allow-AWX-NodePort"
  priority                    = 1060
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "30000-32767"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_linux.name
}
resource "azurerm_network_security_rule" "https_ingress" {
  name                        = "Allow-HTTPS"
  priority                    = 1065
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_linux.name
}
resource "azurerm_network_security_rule" "http_apache_linux" {
  name                        = "Allow-HTTP"
  priority                    = 1040
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_linux.name
}




resource "azurerm_network_security_group" "nsg_windows" {
  name                = "nsg-windows"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}
resource "azurerm_network_security_rule" "icmp_windows" {
  name                        = "Allow-ICMP-Windows"
  priority                    = 1010
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Icmp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_windows.name
}
resource "azurerm_network_security_rule" "rdp_windows" {
  name                        = "Allow-RDP-Windows"
  priority                    = 1020
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_windows.name
}
resource "azurerm_network_security_rule" "winrm_http_windows" {
  name                        = "Allow-WinRM-HTTP"
  priority                    = 1030
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5985"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_windows.name
}

resource "azurerm_network_security_rule" "winrm_https_windows" {
  name                        = "Allow-WinRM-HTTPS"
  priority                    = 1040
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5986"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_windows.name
}
resource "azurerm_network_security_rule" "zabbix_agent_windows" {
  name                        = "Allow-Zabbix-Agent"
  priority                    = 1050
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "10050"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.nsg_windows.name
}



# ============================
# Public IPs
# ============================
resource "azurerm_public_ip" "public_ip_main" {
  name                = "public-ip-servidor"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "public_ip_windows1" {
  name                = "public-ip-windows1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
}

# ============================
# Network Interfaces
# ============================
resource "azurerm_network_interface" "nic_main" {
  name                = "nic-servidor"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip_main.id
  }
}

resource "azurerm_network_interface" "nic_windows1" {
  name                = "nic-windows1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip_windows1.id
  }
}

# ============================
# Asociaciones NSG a NICs
# ============================
resource "azurerm_network_interface_security_group_association" "linux_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic_main.id
  network_security_group_id = azurerm_network_security_group.nsg_linux.id
}

resource "azurerm_network_interface_security_group_association" "windows_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic_windows1.id
  network_security_group_id = azurerm_network_security_group.nsg_windows.id
}

# ============================
# Main Linux VM (AWX host)
# ============================
resource "azurerm_linux_virtual_machine" "main_server" {
  name                            = "servidorlinux"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = "Standard_D2as_v6" #++"Standard_D4as_v6"
  admin_username                  = "jorge"
  admin_password                  = "aaAmerica1.aa"
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic_main.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "perforce"
    offer     = "rockylinux9"
    sku       = "9-gen2"
    version   = "9.3.2023120403"
  }

  plan {
    name      = "9-gen2"
    product   = "rockylinux9"
    publisher = "perforce"
  }

  custom_data = base64encode(<<EOF
#!/bin/bash
(sudo dnf update -y > /var/log/update.log 2>&1 & echo $! > /tmp/update.pid) &
cat <<'EOT' >> /home/jorge/.bashrc
if [ -f /tmp/update.pid ]; then
  pid=$(cat /tmp/update.pid)
  if ps -p $pid > /dev/null 2>&1; then
    echo "⌛ Aún actualizando el sistema, por favor espera..."
    while ps -p $pid > /dev/null 2>&1; do sleep 5; done
    echo "✅ La actualización ha terminado."
    rm -f /tmp/update.pid
    echo "Mostrando el log de actualización:"
    less /var/log/update.log
  else
    rm -f /tmp/update.pid
 fi
fi
EOT
chown jorge:jorge /home/jorge/.bashrc
EOF
  )
}

# ============================
# Windows 10 VM (solo una)
# ============================
resource "azurerm_windows_virtual_machine" "windows_vm1" {
  name                = "windows10-vm1"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2s"
  admin_username      = "jorge"
  admin_password      = "aaAmerica1.aa"
  network_interface_ids = [
    azurerm_network_interface.nic_windows1.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-10"
    sku       = "win10-21h2-pro"
    version   = "latest"
  }
}
