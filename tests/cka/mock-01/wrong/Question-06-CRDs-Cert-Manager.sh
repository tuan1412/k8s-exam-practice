# whole spec instead of spec.subject
kubectl get crd | grep cert-manager > /root/resources.yaml
kubectl explain certificate.spec > /root/subject.yaml
