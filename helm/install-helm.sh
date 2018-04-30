#!/bin/bash

wget https://storage.googleapis.com/kubernetes-helm/helm-v2.7.2-linux-amd64.tar.gz
tar -xcvf helm-v2.7.2-linux-amd64.tar.gz
cp $PWD/linux-amd64/helm /usr/local/bin/

kubectl create sa tiller-deploy -n kube-system
kubectl create clusterrolebinding helm --clusterrole=cluster-admin --serviceaccount=kube-system:tiller-deploy
helm init --service-account=tiller-deploy
