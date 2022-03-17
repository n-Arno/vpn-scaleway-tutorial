resource "scaleway_vpc_private_network" "pn" {
}

resource "scaleway_instance_ip" "public_ip" {
}

resource "scaleway_instance_security_group" "sec_grp_ext" {
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"

  inbound_rule {
    action = "accept"
    protocol = "TCP"
    port   = "22"
  }

  inbound_rule {
    action   = "accept"
    protocol = "UDP"
    port     = "52435"
  }
}

resource "scaleway_instance_security_group" "sec_grp_int" {
  inbound_default_policy  = "accept"
  outbound_default_policy = "accept"
}

resource "scaleway_instance_server" "vpn_gw" {
  type  = "DEV1-S"
  image = "ubuntu_focal"
  ip_id = scaleway_instance_ip.public_ip.id
  security_group_id = scaleway_instance_security_group.sec_grp_ext.id

  provisioner "remote-exec" {
    connection {
      host        = scaleway_instance_ip.public_ip.address
      type        = "ssh"
      user        = "root"
      private_key = file("~/.ssh/id_rsa")
    }

    inline = ["apt-get install ifupdown -y 1>/dev/null 2>&1"]
  }


  provisioner "file" {
    connection {
      host        = scaleway_instance_ip.public_ip.address
      type        = "ssh"
      user        = "root"
      private_key = file("~/.ssh/id_rsa")
    }

    destination = "/etc/network/interfaces"
    content     =<<EOF
    auto lo
    iface lo inet loopback
    
    auto ens2
    iface ens2 inet dhcp
    
    auto ens5
    iface ens5 inet static
      address ${var.net_prefix}.1
      netmask 255.255.255.0
    EOF    
  }
}

resource "scaleway_instance_private_nic" "vpn_nic" {
  server_id          = scaleway_instance_server.vpn_gw.id
  private_network_id = scaleway_vpc_private_network.pn.id
}

resource "scaleway_instance_server" "test" {
  type  = "DEV1-S"
  image = "ubuntu_focal"
  security_group_id = scaleway_instance_security_group.sec_grp_int.id
}

resource "scaleway_instance_private_nic" "test_nic" {
  server_id          = scaleway_instance_server.test.id
  private_network_id = scaleway_vpc_private_network.pn.id
}
