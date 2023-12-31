# Summary
### OS : Rocky 8
### CRI : containerd v1.7.1
### k8s : 1.26.9 deployed by kubespray release-2.22
### CNI : calico
### Kubeflow version : 1.8
### kustomize version : 5.0.3
### storageclass : nfs-provisioner
### etc : gpu-operator
#
# How to use this repository
### * you don't need to execute setup_server repository in advance.
### 0. prepare at least one nfs server
### 1. run bootstrap.sh without sudo in a master node
### 2. run add_node.sh without sudo in every worker and other master nodes.
### 3. run setup_nfs_provisioner.sh without sudo in a master node
### 4. run setup_kubeflow.sh without sudo
### 5. access kubeflow with "HTTPS"
#
# kubeflow 화면 잘림 현상 : 크롬 대신 MS edge 브라우저를 사용해보세요.
#
# how to uninstall gpu-operator
### 1. helm delete -n gpu-operator $(helm list -n gpu-operator | grep gpu-operator | awk '{print $1}')
#
# how to delete kubeflow
### 1. change directory to manifests
### 2. kustomize build example | kubectl delete -f -
### 3. delete all namespaces related with kubeflow(kubeflow, kubeflow-user-example-com, knative-serving, knative-eventing, istio-system, cert-manager)
### 4. delete all data in nfs server
#
# 이외에도 추가적인 내용은 kubespray_ubuntu 레포지토리 참고할 것
