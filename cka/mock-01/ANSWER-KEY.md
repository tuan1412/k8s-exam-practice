# CKA Practice Exam — Mock 1 (Kubernetes 1.37)
## 19 questions · solutions: commands + minimal YAML + traps
### Runnable labs for each question are in the sibling `Question-*` folders (run `scripts/run-question.sh -m cka/mock-01 <n>` from the repo root).

> All questions are solved on one cluster: work on the controlplane as root (`sudo -i`). Questions that need a worker node tell you to `ssh` into it.

---

### Q1 · MariaDB Persistent Volume

> A user accidentally deleted the MariaDB Deployment in the `mariadb` namespace. The Deployment was configured with persistent storage. Your responsibility is to re-establish the Deployment while ensuring data is preserved by reusing the available PersistentVolume.
>
> A PersistentVolume already exists and is retained for reuse. Only one PV exists.
>
> - Create a PersistentVolumeClaim named `mariadb` in the `mariadb` namespace with the spec: access mode `ReadWriteOnce`, storage `250Mi`
> - Edit the MariaDB Deployment file located at `~/mariadb-deploy.yaml` to use the PVC created in the previous step
> - Apply the updated Deployment file to the cluster
> - Ensure the MariaDB Deployment is running and stable
>
> *Suggested docs: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)*

```bash
k get pv                                  # mariadb-pv  250Mi  RWO  Retain  Available  local-path
k get pv mariadb-pv -oyaml | grep -E 'storageClassName|hostPath' -A1
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  storageClassName: local-path     # = the PV's class
  volumeName: mariadb-pv           # optional: pins the claim to that PV
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
```

```bash
vim ~/mariadb-deploy.yaml                 # claimName: mariadb
k apply -f ~/mariadb-deploy.yaml
k -n mariadb get pvc,pod                  # Bound to mariadb-pv, Running
```

**Traps:** a PVC binds only to a PV with the **same** `storageClassName` — omitting it works while the PV's class is the default, `storageClassName: ""` never matches a PV that has a class; with a `WaitForFirstConsumer` class the PVC stays `Pending` until the Pod exists, that's normal; the Pod must use the **new** PVC (`claimName: mariadb`), otherwise the data in the PV is not reused.

---

### Q2 · Argo CD Helm template

> Install Argo CD in the cluster using Helm while ensuring the CRDs are not installed (as they are pre-installed):
>
> - Add the official Argo CD Helm repository with the name `argocd` (`https://argoproj.github.io/argo-helm`)
> - Create a namespace called `argocd`
> - Generate a Helm template from the Argo CD chart version `7.7.3` for the `argocd` namespace
> - Ensure that CRDs are not installed by configuring the chart accordingly
> - Save the generated YAML manifest to `/root/argo-helm.yaml`
>
> *Suggested docs: [Helm Docs](https://helm.sh/docs/)*

```bash
helm repo add argocd https://argoproj.github.io/argo-helm
helm repo update
k create ns argocd
helm search repo argocd/argo-cd --versions | grep 7.7.3
helm show values argocd/argo-cd --version 7.7.3 | grep -A3 '^crds:'     # install: true

helm template argocd argocd/argo-cd --version 7.7.3 -n argocd \
  --set crds.install=false > /root/argo-helm.yaml
grep -c 'kind: CustomResourceDefinition' /root/argo-helm.yaml          # 0
```

**Traps:** `--skip-crds` only skips a chart's `crds/` folder — argo-cd renders its CRDs from `templates/` behind the value `crds.install`, so `--skip-crds` alone still writes 3 CRDs into the file; forgetting `--version 7.7.3` renders the latest chart; `helm template` needs `-n argocd`, otherwise the manifest targets `default`.

---

### Q3 · Sidecar Container

> Update the existing `wordpress` Deployment in the `default` namespace, adding a sidecar container named `sidecar` using the `busybox:stable` image to the existing Pod.
>
> The new sidecar container has to run the following command:
>
> ```
> /bin/sh -c "tail -f /var/log/wordpress.log"
> ```
>
> Use a volume mounted at `/var/log` to make the log file `wordpress.log` available to the co-located container.
>
> *Suggested docs: [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)*

```yaml
# k edit deploy wordpress  -> spec.template.spec
      volumes:
      - name: logs
        emptyDir: {}
      containers:
      - name: wordpress             # existing: add the mount only
        ...
        volumeMounts:
        - name: logs
          mountPath: /var/log
      - name: sidecar
        image: busybox:stable
        command: ["/bin/sh", "-c", "tail -f /var/log/wordpress.log"]
        volumeMounts:
        - name: logs
          mountPath: /var/log
```

```bash
k rollout status deploy wordpress
k logs deploy/wordpress -c sidecar --tail=3      # WordPress is running...
```

**Traps:** **both** containers need the mount, otherwise the sidecar tails a file that doesn't exist in its filesystem (CrashLoopBackOff); `-c` takes the whole script as **one** argument; `volumes` sits next to `containers`, `volumeMounts` inside each container. A native sidecar (`initContainers` + `restartPolicy: Always`) is also accepted.

---

### Q4 · Resource Allocation

> You are managing a WordPress application running in the Kubernetes cluster: Deployment `wordpress` in namespace `wordpress`, whose 3 Pods run on node `node01`. Your task is to adjust the Pod resource requests and limits to ensure stable operation.
>
> - Scale down the `wordpress` Deployment to 0 replicas
> - Edit the Deployment and divide the node's resources evenly across all 3 Pods
> - Assign fair and equal CPU and memory to each Pod
> - Add sufficient overhead to avoid node instability
> - Ensure both the init containers and the main containers use exactly the same resource requests and limits
> - After making the changes, scale the Deployment back to 3 replicas
>
> *Suggested docs: [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)*

```bash
k -n wordpress scale deploy wordpress --replicas 0
k describe node node01 | grep -A6 -E '^Allocatable|^Allocated resources'
# Allocatable: cpu 2, memory 1912Mi · already requested by other Pods: cpu 450m, memory 240Mi
# free: 1550m / 1672Mi  ->  leave ~10-15% overhead, /3  ->  450m / 480Mi per Pod
k -n wordpress edit deploy wordpress
```

```yaml
# the SAME block in initContainers[init-setup] and containers[wordpress]
        resources:
          requests:
            cpu: 450m
            memory: 480Mi
          limits:
            cpu: 450m
            memory: 480Mi
```

```bash
k -n wordpress scale deploy wordpress --replicas 3
k -n wordpress get pod -owide            # 3/3 Running on node01
```

**Traps:** init containers run **before** the app container, so a Pod's effective request is `max(init, sum(app))` — identical values don't double it; dividing the whole Allocatable by 3 ignores the Pods already on the node → the 3rd Pod stays `Pending` (Insufficient cpu/memory); forgetting the init container; a tiny memory limit gets apache `OOMKilled`.

---

### Q5 · HorizontalPodAutoscaler

> Create a new HorizontalPodAutoscaler (HPA) named `apache-server` in the `autoscale` namespace.
>
> - The HPA must target the existing Deployment called `apache-deployment` in the `autoscale` namespace
> - Set the HPA to target 50% CPU usage per Pod
> - Configure the HPA to have a minimum of 1 Pod and a maximum of 4 Pods
> - Set the downscale stabilization window to 30 seconds
>
> *Suggested docs: [HorizontalPodAutoscaler Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/) · [Horizontal Pod Autoscaling](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/)*

```bash
k -n autoscale autoscale deploy apache-deployment --name apache-server \
  --cpu-percent=50 --min=1 --max=4 --dry-run=client -oyaml > 5_hpa.yaml
vim 5_hpa.yaml          # add behavior, see below
k apply -f 5_hpa.yaml
k -n autoscale get hpa
```

```yaml
spec:
  ...
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
```

**Traps:** `kubectl autoscale` has no flag for `behavior` — generate YAML and add it; `behavior` exists only in `autoscaling/v2`; **down**scale = `scaleDown`, not `scaleUp`.

---

### Q6 · CRDs

> Verify the cert-manager application which has been deployed in the cluster.
>
> - Create a list of all cert-manager Custom Resource Definitions (CRDs) and save it to `/root/resources.yaml`
> - Using kubectl, extract the documentation for the `subject` specification field of the Certificate Custom Resource and save it to `/root/subject.yaml`
>
> You may use any output format that kubectl supports.
>
> *Suggested docs: [Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) · [kubectl explain](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_explain/)*

```bash
k get crd | grep cert-manager.io > /root/resources.yaml     # 6 CRDs
k explain certificate.spec.subject > /root/subject.yaml
head /root/subject.yaml       # FIELD: subject <Object> ... countries, organizationalUnits, serialNumber
```

**Traps:** `k get crd` alone lists **every** CRD (Calico, Gateway API...) — filter; `explain certificate.spec` only shows `subject` as one line — go one level deeper (`.spec.subject`); `explain` works for CRDs because they publish an OpenAPI schema.

---

### Q7 · PriorityClass

> You're working in a Kubernetes cluster with an existing Deployment named `busybox-logger` running in the `priority` namespace. The cluster already has at least one user-defined PriorityClass.
>
> - Create a new PriorityClass named `high-priority` for user workloads. The value of this class should be exactly one less than the highest existing user-defined PriorityClass
> - Patch the existing Deployment `busybox-logger` in the `priority` namespace to use the newly created `high-priority` class
>
> *Suggested docs: [kubectl create priorityclass](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_priorityclass/) · [Update API Objects in Place Using kubectl patch](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/)*

```bash
k get pc                      # system-* are 2000000000+, not user-defined -> highest user one: 1000
k create pc high-priority --value=999 --description="high priority"
k -n priority patch deploy busybox-logger \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
k -n priority get pod -o custom-columns=NAME:.metadata.name,PC:.spec.priorityClassName,PRIO:.spec.priority
```

**Traps:** look at **all** classes, not just the first one; one **less** = 999; `priorityClassName` goes into the Pod template (`spec.template.spec`); don't set `globalDefault`.

---

### Q8 · cri-dockerd and sysctl

> Set up cri-dockerd on the controlplane node:
>
> - Install the Debian package `~/cri-dockerd.deb` using `dpkg`
> - Enable and start the `cri-docker` service
>
> Configure these system parameters and make sure they persist across reboots:
>
> - Set `net.bridge.bridge-nf-call-iptables` to `1`
> - Set `net.ipv6.conf.all.forwarding` to `1`
> - Set `net.ipv4.ip_forward` to `1`
> - Set `net.ipv4.tcp_keepalive_time` to `600`
>
> *Suggested docs: [Container Runtimes (Install and configure prerequisites)](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#install-and-configure-prerequisites)*

```bash
dpkg -i ~/cri-dockerd.deb
systemctl enable --now cri-docker.service
systemctl status cri-docker --no-pager

cat <<'EOF' > /etc/sysctl.d/99-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.ip_forward = 1
net.ipv4.tcp_keepalive_time = 600
EOF
sysctl --system
sysctl net.ipv6.conf.all.forwarding net.ipv4.tcp_keepalive_time
```

**Traps:** `sysctl -w` alone is lost at reboot, a file in `/etc/sysctl.d` alone isn't applied until `sysctl --system` — you need both; `bridge-nf-call-iptables` only exists once `br_netfilter` is loaded; the docs page *Container Runtimes* has the copy-paste block for the sysctl file.

---

### Q9 · Migrate Ingress to Gateway API

> You have an existing web application deployed in the `default` namespace using an Ingress resource named `web`. You must migrate the existing Ingress configuration to the new Kubernetes Gateway API, maintaining the existing HTTPS access configuration.
>
> - Create a Gateway resource named `web-gateway` with hostname `gateway.web.k8s.local` that maintains the existing TLS and listener configuration from the existing Ingress resource named `web`
> - Create an HTTPRoute resource named `web-route` with hostname `gateway.web.k8s.local` that maintains the existing routing rules from the current Ingress resource named `web`
>
> ℹ️ A GatewayClass named `nginx-class` is already installed in the cluster
>
> *Suggested docs: [Gateway API (gateway-api.sigs.k8s.io)](https://gateway-api.sigs.k8s.io/) · [Gateway](https://gateway-api.sigs.k8s.io/reference/api-types/gateway/) · [HTTPRoute](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/)*

```bash
k describe ingress web        # TLS: web-tls for gateway.web.k8s.local · / (Prefix) -> web-service:80
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
spec:
  gatewayClassName: nginx-class
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: gateway.web.k8s.local
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: web-tls
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
spec:
  parentRefs:
  - name: web-gateway
  hostnames:
  - gateway.web.k8s.local
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-service
      port: 80
```

**Traps:** the Ingress terminates TLS → listener `HTTPS` on `443` with `tls.certificateRefs` → `web-tls`, not an `HTTP` listener on 80; the route attaches through `parentRefs`; Ingress `pathType: Prefix` = `PathPrefix`.

---

### Q10 · Ingress

> - Expose the existing Deployment `echo` in the `echo-sound` namespace with a Service called `echo-service` using Service port `8080`, type `NodePort`
> - Create a new Ingress resource named `echo` in the `echo-sound` namespace for `http://example.org/echo`, sending the traffic to `echo-service`
>
> The availability of the Service `echo-service` can be checked using the following command:
>
> ```
> curl NODEIP:NODEPORT/echo
> ```
>
> *Suggested docs: [Service](https://kubernetes.io/docs/concepts/services-networking/service/) · [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)*

```bash
k -n echo-sound expose deploy echo --name echo-service --type NodePort --port 8080 --target-port 8080
k -n echo-sound get svc echo-service                  # 8080:3xxxx/TCP
curl node01:3xxxx/echo?msg=hi                         # hi

k -n echo-sound create ingress echo --rule="example.org/echo=echo-service:8080"
k -n echo-sound get ingress echo
```

**Traps:** the Ingress backend uses the **Service** port (8080), not the NodePort; host is `example.org` (no `http://`), path `/echo` (not `/`); `create ingress` makes `pathType: Exact` — `Prefix` is fine too.

---

### Q11 · NetworkPolicy

> There are two Deployments, `frontend-deployment` and `backend-deployment`. The frontend runs in the `frontend` namespace, the backend in the `backend` namespace (exposed by Service `backend-service`).
>
> - Look at the NetworkPolicy YAML files in `/root/network-policies`
> - Decide which of the policies provides the functionality to allow interaction between the frontend and the backend Deployments in the least permissive way, and deploy that YAML
>
> Do not create, modify or deploy any other NetworkPolicy.
>
> *Suggested docs: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)*

```bash
cd /root/network-policies && cat network-policy-*.yaml
# policy-x  podSelector {} + ingress [{}]               -> allows everything
# policy-y  ns frontend OR ipBlock 172.16.0.0/16        -> also opens a whole IP range
# policy-z  ns frontend OR pods app=frontend, TCP 80    -> least permissive
k get pod -A --show-labels | grep -E 'frontend|backend'
k apply -f network-policy-3.yaml
k -n frontend exec deploy/frontend-deployment -- curl -s -m 5 backend-service.backend
```

**Traps:** `- {}` in `ingress` means "allow all"; an `ipBlock` adds sources, it never restricts; deploy exactly **one** file — policies are OR-ed, a second open one cancels the restriction.

---

### Q12 · Default StorageClass

> - Create a new StorageClass named `local-storage` with the provisioner `rancher.io/local-path`. Set the VolumeBindingMode to `WaitForFirstConsumer`. Do not make the StorageClass default
> - Patch the StorageClass to make it the default StorageClass
> - Ensure `local-storage` is the only default StorageClass
>
> Do not modify any existing Deployments or PersistentVolumeClaims.
>
> *Suggested docs: [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) · [Change the default StorageClass](https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/)*

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
```

```bash
k patch sc local-storage -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
k patch sc local-path    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
k get sc                 # only local-storage is (default)
```

**Traps:** the annotation value is a **string** (`"true"`); two defaults are allowed by the API (the newest wins) but the task wants exactly one; `provisioner`/`volumeBindingMode` are immutable — delete and recreate if wrong.

---

### Q13 · NodePort Service

> There is a Deployment named `nodeport-deployment` in the `relative` namespace.
>
> - Configure the Deployment so it can be exposed on port `80`, name `http`, protocol `TCP`
> - Create a new Service named `nodeport-service` exposing the container port `80`, protocol `TCP`, NodePort `30080`
> - Configure the new Service to also expose the individual Pods using NodePort
>
> *Suggested docs: [Service (type NodePort)](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) · [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)*

```yaml
# k -n relative edit deploy nodeport-deployment -> containers[0]
        ports:
        - name: http
          containerPort: 80
          protocol: TCP
```

```bash
k -n relative expose deploy nodeport-deployment --name nodeport-service --type NodePort \
  --port 80 --target-port http --dry-run=client -oyaml > 16.yaml
vim 16.yaml                   # ports[0].nodePort: 30080
k apply -f 16.yaml
curl -s -o /dev/null -w '%{http_code}\n' node01:30080       # 200
```

**Traps:** `expose` has no `--node-port` flag — edit the YAML; NodePorts must be in 30000-32767; the selector must match the Pod labels (`app=nodeport-deployment`).

---

### Q14 · TLS Configuration

> There is an existing Deployment in the `nginx-static` namespace. The Deployment uses a ConfigMap that supports TLSv1.2 and TLSv1.3, as well as a Secret for TLS. There is a Service called `nginx-static` in the `nginx-static` namespace that is currently exposing the Deployment.
>
> - Configure the ConfigMap to only support TLSv1.3
> - Add the IP address of the Service to `/etc/hosts` and name it `ckaquestion.k8s.local`
> - Verify everything is working using the following commands:
>
> This should fail (TLS 1.2 is no longer accepted):
>
> ```
> curl -vk --tls-max 1.2 https://ckaquestion.k8s.local
> ```
>
> This should work:
>
> ```
> curl -vk --tlsv1.3 https://ckaquestion.k8s.local
> ```
>
> *Suggested docs: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) · [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)*

```bash
k -n nginx-static edit cm nginx-config            # ssl_protocols TLSv1.3;
k -n nginx-static get svc nginx-static            # CLUSTER-IP
echo "10.x.x.x ckaquestion.k8s.local" >> /etc/hosts
k -n nginx-static rollout restart deploy nginx-static
curl -vk --tls-max 1.2 https://ckaquestion.k8s.local     # tlsv1 alert protocol version
curl -vk --tlsv1.3 https://ckaquestion.k8s.local         # Hello TLS
```

**Traps:** the config is mounted with `subPath`, which never receives ConfigMap updates — without `rollout restart` TLSv1.2 keeps working; put the **Service** ClusterIP in `/etc/hosts`, not a Pod IP.

---

### Q15 · kubectl patch

> A Deployment named `resource-app` exists in the `patch-ns` namespace. Its resource limits (CPU `200m`, memory `256Mi`) are too low for the expected workload.
>
> Using ONLY `kubectl patch` (not `kubectl edit`, `kubectl set` or `kubectl apply`):
>
> - Update the CPU limit of the `nginx` container to `500m`
> - Update the memory limit of the `nginx` container to `512Mi`
>
> Do not change the CPU or memory requests. The Deployment must remain available with 2 replicas.
>
> *Suggested docs: [Update API Objects in Place Using kubectl patch](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/)*

```bash
k -n patch-ns patch deploy resource-app -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'
k -n patch-ns get deploy resource-app -ojsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```

**Traps:** the default (strategic) patch merges containers **by name**, so requests and image stay; `--type=merge` replaces the whole `containers` list; JSON needs single quotes around it in bash. The grader checks `metadata.managedFields`: `kubectl patch` writes as manager `kubectl-patch`, `edit`/`set`/`apply` as other managers.

---

### Q16 · Resource Requests v2

> A WordPress Deployment named `wordpress` in namespace `relative-fawn` has 3 replicas, all running on node `node01`.
>
> - Edit the WordPress Deployment so that each Pod's resource requests equally divide the node's available resources among the 3 replicas
> - Limits do not need to be changed
> - All 3 replicas must be Running afterwards
>
> *Suggested docs: [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)*

```bash
k describe node node01 | grep -A6 -E '^Allocatable|^Allocated resources'
# available = Allocatable - requests of the OTHER Pods (Allocated - 3 x 100m/100Mi)
# per Pod  = available / 3 - overhead, never above the limits (300m / 500Mi)
k -n relative-fawn scale deploy wordpress --replicas 0
k -n relative-fawn set resources deploy wordpress -c wordpress --requests=cpu=250m,memory=350Mi
k -n relative-fawn scale deploy wordpress --replicas 3
k -n relative-fawn get pod          # 3/3 Running
```

**Traps:** requests above the limits are rejected; the rolling update needs room for one surge Pod, so scale to 0 first when the node is tight; don't change the limits.

---

### Q17 · Taints and Tolerations

> - Add a taint to node `node01` so that no normal Pods can be scheduled on this node: key `PERMISSION`, value `granted`, effect `NoSchedule`
> - Schedule a Pod named `nginx` with image `nginx` in the `default` namespace on node `node01`, adding the correct toleration to its spec so it can be deployed
>
> *Suggested docs: [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)*

```bash
k taint node node01 PERMISSION=granted:NoSchedule
k run nginx --image=nginx --dry-run=client -oyaml > 10.yaml
vim 10.yaml
```

```yaml
spec:
  nodeName: node01            # optional here: node01 is the only schedulable node
  tolerations:
  - key: PERMISSION
    operator: Equal
    value: granted
    effect: NoSchedule
  containers:
  - name: nginx
    image: nginx
```

**Traps:** key and value are case-sensitive; a toleration only **allows** the tainted node, it doesn't attract the Pod (add `nodeName`/`nodeSelector` on clusters with more workers); `kubectl taint ... PERMISSION-` removes it again.

---

### Q18 · Fix kube-apiserver

> After a cluster migration, the controlplane kube-apiserver is not coming up. Before the migration, etcd was external and in HA; after the migration, the kube-apiserver was pointed to the etcd peer port `2380`.
>
> - Fix it, so that kube-apiserver works and kubectl can talk to the cluster again
>
> *Suggested docs: [Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) · [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)*

```bash
k get nodes                                            # refused / timeout
crictl ps -a --name kube-apiserver                     # Exited, restarting
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail
grep -- --etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml   # https://127.0.0.1:2380
vim /etc/kubernetes/manifests/kube-apiserver.yaml     # :2380 -> :2379
watch crictl ps --name kube-apiserver                  # kubelet recreates the static Pod (~30-60s)
k get nodes
```

**Traps:** `2379` = etcd **client** port (what the apiserver needs), `2380` = **peer** port (etcd ↔ etcd); kubectl is useless while debugging — use `crictl` and `/var/log/pods`; never leave a backup copy inside `/etc/kubernetes/manifests` (kubelet runs every file there).

---

### Q19 · CNI and NetworkPolicy

> Install and configure a Container Network Interface (CNI) of your choice that meets the specified requirements. Choose one of the following options:
>
> - Flannel (`v0.26.1`) using the manifest `kube-flannel.yml` (`https://github.com/flannel-io/flannel/releases/download/v0.26.1/kube-flannel.yml`)
> - Calico (`v3.28.2`) using the manifest `tigera-operator.yaml` (`https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml`)
>
> The CNI you choose must:
>
> - Let Pods communicate with each other
> - Support NetworkPolicy enforcement
> - Install from manifest
>
> *Suggested docs: [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/) · [Install Calico (operator, on-premises)](https://docs.tigera.io/calico/3.28/getting-started/kubernetes/self-managed-onprem/onpremises)*

```bash
k get nodes                                                           # NotReady (no CNI)
k -n kube-system get cm kubeadm-config -oyaml | grep podSubnet        # 10.244.0.0/16
k create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml
wget https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml
vim custom-resources.yaml            # ipPools[0].cidr: 192.168.0.0/16 -> 10.244.0.0/16
k create -f custom-resources.yaml
k get tigerastatus                   # calico Available
k get nodes                          # Ready
k -n kube-system rollout restart deploy coredns
```

**Traps:** Flannel is simpler but does **not** enforce NetworkPolicy, so only Calico fits; the default CIDR in `custom-resources.yaml` must be changed to the cluster's `podSubnet`; use `kubectl create` for `tigera-operator.yaml` (`apply` fails on its large CRDs: annotation too long).

---

## Self-scoring — Mock 1

| Domain | Questions | Score |
|---|---|---|
| Cluster Architecture, Installation & Config | Q2 (5) · Q6 (4) · Q19 (7) · Q8 (6) | /22 |
| Workloads & Scheduling | Q3 (5) · Q4 (5) · Q5 (5) · Q7 (4) · Q17 (4) · Q15 (4) · Q16 (5) | /32 |
| Services & Networking | Q9 (7) · Q10 (5) · Q11 (5) · Q13 (5) | /22 |
| Storage | Q1 (6) · Q12 (4) | /10 |
| Troubleshooting | Q18 (8) · Q14 (6) | /14 |
| **Real pass mark ≥66** | | /100 |

**Highest-stakes questions:** Q18 (cluster down until fixed) · Q19 (Calico CIDR) · Q9 (HTTPS listener) · Q14 (restart after the ConfigMap change) · Q4/Q16 (overhead).
