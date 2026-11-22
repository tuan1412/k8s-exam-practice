# Q6 — Solution
kubectl get crd | grep cert-manager.io > /root/resources.yaml
# (or: kubectl get crd -oname | grep cert-manager.io > /root/resources.yaml)
cat /root/resources.yaml          # 6 CRDs: certificaterequests, certificates, challenges, clusterissuers, issuers, orders

kubectl explain certificate.spec.subject > /root/subject.yaml
head /root/subject.yaml           # FIELD: subject <Object> ... countries, organizationalUnits, serialNumber...

# Traps: "kubectl get crd" alone lists every CRD in the cluster (Calico, Gateway API...): filter it;
#        explain certificate.spec only describes subject in one line — go one level deeper (.spec.subject).
