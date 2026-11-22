# CKA Mock 1

All 19 questions of [markdjones82/CKA-PREP-2025-v2 (custom-main)](https://github.com/markdjones82/CKA-PREP-2025-v2/tree/custom-main), rebuilt for this repo: exam-style task text, auto-graders that give no free points, cleanup that restores the cluster, and e2e tests. Full solutions with traps: [`ANSWER-KEY.md`](ANSWER-KEY.md).

| # | Question | Pts | Domain | Lab notes |
|---|---|---|---|---|
| Q1 | MariaDB: PVC on a retained PV | 6 | Storage | Q12 changes the default StorageClass |
| Q2 | Argo CD `helm template` without CRDs | 5 | Cluster Architecture | needs internet (helm repo) |
| Q3 | Sidecar container | 5 | Workloads | |
| Q4 | Resource requests/limits for 3 Pods | 5 | Workloads | Pods pinned to the worker |
| Q5 | HPA with downscale window | 5 | Workloads | installs metrics-server |
| Q6 | cert-manager CRDs + `kubectl explain` | 4 | Cluster Architecture | installs cert-manager CRDs |
| Q7 | PriorityClass | 4 | Workloads | |
| Q8 | cri-dockerd + sysctl | 6 | Cluster Architecture | Docker Engine installed by the setup (no iptables rules): cri-docker stays running |
| Q9 | Ingress → Gateway API (HTTPS) | 7 | Services & Networking | GatewayClass without controller |
| Q10 | NodePort Service + Ingress | 5 | Services & Networking | no Ingress controller |
| Q11 | Least-permissive NetworkPolicy | 5 | Services & Networking | CNI must enforce NP |
| Q12 | Default StorageClass | 4 | Storage | cleanup restores the old default |
| Q13 | NodePort 30080 | 5 | Services & Networking | NodePort 30080 |
| Q14 | nginx TLSv1.3 only + /etc/hosts | 6 | Troubleshooting | |
| Q15 | Change limits with `kubectl patch` only | 4 | Workloads | graded by field manager |
| Q16 | Resource requests v2 | 5 | Workloads | same worker as Q4 |
| Q17 | Taints and tolerations | 4 | Workloads | taint blocks the only worker: do it last or Reset |
| Q18 | kube-apiserver → etcd port | 8 | Troubleshooting | ⚠ breaks kubectl until fixed |
| Q19 | Install a CNI (Calico operator) | 7 | Cluster Architecture | ⚠ removes the cluster's CNI |

Run it in the [exam simulator](../../simulator/README.md): pick *CKA Mock 1* in the start dialog. Each task names the host to `ssh` to (`hosts.txt`). The questions that can break a cluster are at the end on purpose and have hosts of their own: Q17 (taint on the only worker), Q18 (kube-apiserver), Q19 (CNI); *Reset* on them restores the host from its snapshot.
