#!/bin/bash

IP=
CURRENT_DIR=$PWD

# install basic packages
yum update -y
yum install -y net-tools nfs-utils wget pciutils mkpasswd

# disable ufw
systemctl stop firewalld
systemctl disable firewalld

#------------- Set SELinux in permissive mode (effectively disabling it)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

cat <<EOF | sudo tee -a /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# ssh configuration
ssh-keygen -t rsa
ssh-copy-id -i ~/.ssh/id_rsa ${USER}@${IP}

# k8s installation via kubespray
cd ~
git clone -b release-2.22 https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
pip install -r requirements.txt

echo "export PATH=${HOME}/.local/bin:${PATH}" | sudo tee ${HOME}/.bashrc > /dev/null
export PATH=${HOME}/.local/bin:${PATH}
source ${HOME}/.bashrc

cp -rfp inventory/sample inventory/mycluster
declare -a IPS=(${IP})
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

# enable dashboard / disable dashboard login / change dashboard service as nodeport
sed -i "s/# dashboard_enabled: false/dashboard_enabled: true/g" inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i "s/dashboard_skip_login: false/dashboard_skip_login: true/g" roles/kubernetes-apps/ansible/defaults/main.yml
sed -i'' -r -e "/targetPort: 8443/a\  type: NodePort" roles/kubernetes-apps/ansible/templates/dashboard.yml.j2

# enable helm
sed -i "s/helm_enabled: false/helm_enabled: true/g" inventory/mycluster/group_vars/k8s_cluster/addons.yml

# disable nodelocaldns
sed -i "s/enable_nodelocaldns: true/enable_nodelocaldns: false/g" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# enable kubectl & kubeadm auto-completion
echo "source <(kubectl completion bash)" >> ${HOME}/.bashrc
echo "source <(kubeadm completion bash)" >> ${HOME}/.bashrc
echo "source <(kubectl completion bash)" | sudo tee -a /root/.bashrc
echo "source <(kubeadm completion bash)" | sudo tee -a /root/.bashrc
source ${HOME}/.bashrc

ansible-playbook -i inventory/mycluster/hosts.yaml  --become --become-user=root cluster.yml -K
sleep 30
cd ~

# enable kubectl in admin account and root
mkdir -p ${HOME}/.kube
cp -i /etc/kubernetes/admin.conf ${HOME}/.kube/config
chown ${USER}:${USER} ${HOME}/.kube/config

# create sa and clusterrolebinding of dashboard to get cluster-admin token
kubectl apply -f ${CURRENT_DIR}/sa.yaml
kubectl apply -f ${CURRENT_DIR}/clusterrolebinding.yaml

# install gpu-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
  && helm repo update

helm install --wait --generate-name \
     -n gpu-operator --create-namespace \
     nvidia/gpu-operator
