#!/bin/bash

sudo snap install microk8s --channel=1.29/edge --classic
sudo snap alias microk8s.kubectl kubectl
sudo usermod -a -G microk8s ${USER}
mkdir -p ~/.kube
sudo chown -f -R ${USER} ~/.kube

