#!/bin/bash

# install basic packages
sudo yum update -y
sudo yum install -y net-tools nfs-utils wget pciutils mkpasswd

# disable ufw
sudo systemctl stop firewalld
sudo systemctl disable firewalld

#------------- Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

cat <<EOF | sudo tee -a /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system
