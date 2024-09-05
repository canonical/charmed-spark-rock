microk8s status --wait-ready
microk8s config | tee ~/.kube/config
sudo microk8s enable dns
sudo microk8s enable rbac
sudo microk8s enable minio
