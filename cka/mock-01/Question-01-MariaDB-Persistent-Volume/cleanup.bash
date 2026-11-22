#!/bin/bash
kubectl delete ns mariadb --ignore-not-found
kubectl delete pv mariadb-pv --ignore-not-found
rm -f /root/mariadb-deploy.yaml
