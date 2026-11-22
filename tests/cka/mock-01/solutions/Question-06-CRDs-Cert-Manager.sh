kubectl get crd | grep cert-manager.io > /root/resources.yaml
kubectl explain certificate.spec.subject > /root/subject.yaml
