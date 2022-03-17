Configuring site to site VPN tunnel using wireguard
===================================================

Intended infrastructure
-----------------------

This tutorial is intended to connect a Scaleway VPC to an other subnet, either on-premise or in an other CSP. The installation steps are intended for ubuntu servers but can be adapted for other linux distributions.

To demonstrate the configuration, this network configuration is assumed:

```
===========[Scaleway VPC]==========                  ============[On Premise]============
           192.168.0.0/24                                       192.168.1.0/24
========[private network 1]===========               ==========[private subnet]==========
[test instance]      [vpn gw instance]--[public ip]  <-----[vpn client]        [test server]
x.x.x.x              192.168.0.1                           192.168.1.1         192.168.1.2
```

Demonstration Terraform Manifest
--------------------------------

The included Terraform manifest will create both Scaleway and On Premise site as VPC to help follow the tutorial. 

To use it follow these steps:

```
export SCW_ACCESS_KEY=<Scaleway API access key>
export SCW_SECRET_KEY=<Scaleway API secret key>
export SCW_DEFAULT_PROJECT_ID=<Associated project ID>
make # This will init, plan and apply terraform manifest
```

This manifest assume you have generated an rsa ssh key with no password and added it to your Scaleway console. This is not the way to do it in production.

If using the Terraform manifest, you will need to activate the static IP on the private network interface (ignore errors):

```
ifdown ens5 && ifup ens5
```

Configuration steps
-------------------

On both the vpn gw instance and vpn client, activate ip forwarding, install Wireguard and generate keys:

```
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
apt-get install wireguard -y
cd /etc/wireguard
umask 077
wg genkey | tee privatekey | wg pubkey > publickey
```

On the vpn gw instance configure Wireguard as a server (we will use 172.16.0.1 and 172.16.0.2 as server and client IPs for the VPN tunnel):

```
cat /etc/wireguard/wg0.conf
[Interface]
PrivateKey = <server private key>
Address = 172.16.0.1/32
ListenPort = 52435

[Peer]
PublicKey = <client public key>
AllowedIPs = 172.16.0.2/32,192.168.1.0/24
```

On the vpn client server configure Wireguard as a client:

```
cat /etc/wireguard/wg0.conf
[Interface]
PrivateKey = <client private key>
Address = 172.16.0.2/32
ListenPort = 52435

[Peer]
PublicKey = <server public key>
Endpoint = <server public ip>:52435
AllowedIPs = 172.16.0.1/32,192.168.0.0/24
PersistentKeepalive = 25
```

On both vpn gw instance and vpn client, start the VPN:

```
systemctl enable --now wg-quick@wg0
```

Route propagation and testing
-----------------------------

To finish the configuration, a static route must be distributed in each subnet to use the server or client as a gw to the other subnet. On the VPC side, we are going to use a DHCP server with the option 121.

On the vpn gw instance, install dnsmasq, ignore errors due to systemd-resolved being up:

```
apt-get install dnsmasq -y
```

Configure and start dnsmasq as a DHCP server only, listening for queries on the private network nic:

```
cat /etc/dnsmasq.conf
interface=ens5
port=0 # disable DNS
dhcp-range=192.168.0.2,192.168.0.254,255.255.255.0,12h
dhcp-option=3,192.168.0.1
dhcp-option=121,192.168.1.0/24,192.168.0.1
log-facility=/var/log/dnsmasq.log
log-async
log-queries
log-dhcp
```

```
systemctl enable --now dnsmasq
```

On the test server, add the static route manually:

```
ip route add 192.168.0.0/24 via 192.168.1.1
```

If using the Terraform manifest, you can configure dnsmasq as above for the other subnet (instead of adding route manually):

```
cat /etc/dnsmasq.conf
interface=ens5
port=0 # disable DNS
dhcp-range=192.168.1.2,192.168.1.254,255.255.255.0,12h
dhcp-option=3,192.168.1.1
dhcp-option=121,192.168.0.0/24,192.168.1.1
log-facility=/var/log/dnsmasq.log
log-async
log-queries
log-dhcp
```

On the vpn gw instance, find the IP distributed to the test instance (result may differ of course):

```
grep DHCPACK /var/log/dnsmasq.log
Mar 16 08:39:07 dnsmasq-dhcp[6802]: 3628479477 DHCPACK(ens5) 192.168.0.120 02:00:00:00:f7:8b tf-srv-quizzical-chebyshev
```

On the test server, test the connection to the test instance:

```
ping 192.168.0.120
PING 192.168.0.120 (192.168.0.120) 56(84) bytes of data.
64 bytes from 192.168.0.120: icmp_seq=1 ttl=62 time=3.98 ms
64 bytes from 192.168.0.120: icmp_seq=2 ttl=62 time=6.27 ms
64 bytes from 192.168.0.120: icmp_seq=3 ttl=62 time=3.70 ms
```

Firewalling considerations
--------------------------

Wireguard, like some other VPN, is using UDP traffic. Both the server and the client should open a port for UDP traffic (in this tutorial case, the arbitrary value of 52435 was used).

Using statefull firewall may not be enough since some of them drop UDP traffic. If you used the Terraform manifest, the security group is accepting UDP 52435 traffic.
