#!/bin/bash

IP=
CURRENT_DIR=$PWD

# install basic packages
sudo yum update -y
sudo yum install -y epel-release
sudo yum install -y net-tools nfs-utils wget pciutils git

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

cat <<EOF | sudo tee -a /etc/modules-load.d/istio-iptables.conf
br_netfilter
nf_nat
xt_REDIRECT
xt_owner
iptable_nat
iptable_mangle
iptable_filter
EOF

sudo sysctl --system

# ssh configuration
ssh-keygen -t rsa
ssh-copy-id -i ~/.ssh/id_rsa ${USER}@${IP}

# install python3
sudo yum install -y python3.11 python3.11-pip
python3 -m pip install --upgrade pip
python3 -m pip install selinux
sudo python3 -m pip install selinux

# k8s installation via kubespray
cd
git clone -b release-2.22 https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
pip3 install -r requirements.txt

echo "export PATH=${HOME}/.local/bin:${PATH}" | sudo tee ${HOME}/.bashrc > /dev/null
echo "export PATH=/usr/local/bin:${PATH}" | sudo tee -a /root/.bashrc > /dev/null
export PATH=${HOME}/.local/bin:${PATH}
source ${HOME}/.bashrc

cp -rfp inventory/sample inventory/mycluster
declare -a IPS=(${IP})
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

# comment ansible code of changing selinux policy
sed -i "14,24s/^/#/g" roles/kubernetes/preinstall/tasks/0080-system-configurations.yml

# change kube_proxy_mode to iptables
sed -i "s/kube_proxy_mode: ipvs/kube_proxy_mode: iptables/g" roles/kubespray-defaults/defaults/main.yaml
sed -i "s/kube_proxy_mode: ipvs/kube_proxy_mode: iptables/g" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

sed -i "s/# calico_iptables_backend: "Auto"/calico_iptables_backend: "Auto"/g" inventory/sample/group_vars/k8s_cluster/k8s-net-calico.yml

# enable dashboard / disable dashboard login / change dashboard service as nodeport
sed -i "s/# dashboard_enabled: false/dashboard_enabled: true/g" inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i "s/dashboard_skip_login: false/dashboard_skip_login: true/g" roles/kubernetes-apps/ansible/defaults/main.yml
sed -i'' -r -e "/targetPort: 8443/a\  type: NodePort" roles/kubernetes-apps/ansible/templates/dashboard.yml.j2

# enable helm
sed -i "s/helm_enabled: false/helm_enabled: true/g" inventory/mycluster/group_vars/k8s_cluster/addons.yml

# disable nodelocaldns
sed -i "s/enable_nodelocaldns: true/enable_nodelocaldns: false/g" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

ansible-playbook -i inventory/mycluster/hosts.yaml  --become --become-user=root cluster.yml -K
sleep 30
cd ~

# enable kubectl & kubeadm auto-completion
echo "source <(kubectl completion bash)" >> ${HOME}/.bashrc
echo "source <(kubeadm completion bash)" >> ${HOME}/.bashrc
echo "source <(kubectl completion bash)" | sudo tee -a /root/.bashrc
echo "source <(kubeadm completion bash)" | sudo tee -a /root/.bashrc
source ${HOME}/.bashrc

# enable kubectl in admin account and root
mkdir -p ${HOME}/.kube
sudo cp -i /etc/kubernetes/admin.conf ${HOME}/.kube/config
sudo chown ${USER}:${USER} ${HOME}/.kube/config

# create sa and clusterrolebinding of dashboard to get cluster-admin token
kubectl apply -f ${CURRENT_DIR}/sa.yaml
kubectl apply -f ${CURRENT_DIR}/clusterrolebinding.yaml

# download nerdctl zip file
cd ${HOME}
wget https://github.com/containerd/nerdctl/releases/download/v1.6.2/nerdctl-full-1.6.2-linux-amd64.tar.gz

# install nerdctl
sudo tar Cxzvvf /usr nerdctl-full-1.6.2-linux-amd64.tar.gz

# install gpu-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
  && helm repo update

helm install --wait --generate-name \
     -n gpu-operator --create-namespace \
     nvidia/gpu-operator
