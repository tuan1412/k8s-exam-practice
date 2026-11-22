# E2E tests for the labs

Tests for the **lab scripts themselves** (setup / validate / cleanup), not practice material. `solutions/` contains the answers.

For each question `tests/run-e2e.sh` checks:

1. Right after setup → `validate.bash` must **FAIL** and score **0** checks (no free points). Checks that already hold after setup ("don't break X") use `guard`/`guard_eq`: they only count once a task check passes.
2. A **common wrong answer** (`wrong/<question>.sh`) → must **FAIL** (the trap is caught).
3. Fresh setup + **correct answer** (`solutions/<question>.sh`) → must fully **PASS**.

On an exam host of the simulator (`simulator/lab.sh ssh <host>`, then `cd /root/k8s-exam-practice`), as root:

```bash
tests/run-e2e.sh 15                         # one question of mock 1
```

```bash
tests/run-e2e.sh -m cka/mock-01 13          # one question of mock 1
```

```bash
INCLUDE_DESTRUCTIVE=1 tests/run-e2e.sh 8    # destructive — on its own host, Reset it afterwards
```

A question has to run on its host from `cka/mock-*/hosts.txt`. From the VM, `sudo exam-hostctl e2e cka/mock-01 15` picks the host itself (`exam-hostctl e2e cka/mock-01` runs every question, each on its host).

Logs: `/tmp/k8s-exam-practice-e2e/<question>.log` (`LOG_DIR=` to change). `KEEP=1` keeps resources afterwards.

## In CI

`.github/workflows/simulator.yml` has one e2e job per exam: it builds the host of the question named by the `# e2e: <n>` line of the exam's `hosts.txt` (building it already checks that the environment comes up: kubeadm, Calico, CoreDNS, every node Ready) and runs the three steps above for that one question. Mock 1 tests Q13 (NodePort). A new exam gets its job automatically (`simulator/incus/exam-hosts.sh e2e-plan`); without an `e2e:` line its first question with a solution script is tested. Run the workflow by hand with *all questions* to e2e-test every question, one job per host.

## Wrong answers covered

| Q | Wrong answer |
|---|---|
| Q1 | `get-contexts` without `-oname`, `config view` without `--raw` |
| Q2 | `crlDistributionPoints` not added to the YAML |
| Q3 | `delete pod` instead of scaling |
| Q4 | Deployment name instead of Pod names |
| Q5 | ConfigMap left in the cluster, live not patched |
| Q6 | PVC without `storageClassName: ""` grabbed by the default StorageClass |
| Q7 | alias `k`, no `--containers` |
| Q9 | no `serviceAccountName`, no token → 403 |
| Q10 | hand-written Role with `apiGroups: [""]` for jobs/cronjobs |
| Q11 | no controlplane toleration |
| Q12 | `preferred` instead of `required` |
| Q13 | `- headers:` (OR) instead of same element as `path` (AND) |
| Q14 | Not Before, `renew apiserver` |
| Q15 | one merged egress rule for cache/queue |
| Q16 | `cluster.local` replaced instead of extended |
| Q17 | pod sandbox ID, log without `2>&1` |
| Q18 | Not Before of the peer certificate |
| Q19 | rules written after the Service was deleted |

### Mock 1

| Q | Wrong answer |
|---|---|
| Q1 | PVC with `storageClassName: ""` never binds the PV |
| Q2 | `--skip-crds` instead of `crds.install=false` |
| Q3 | sidecar without the shared volume |
| Q4 | resources on the main container only |
| Q5 | `kubectl autoscale` without the downscale window |
| Q6 | `explain certificate.spec` instead of `.spec.subject` |
| Q7 | value one more instead of one less |
| Q8 | `sysctl -w` only, nothing persisted |
| Q9 | HTTP listener instead of HTTPS |
| Q10 | Service port 80, Ingress path `/` |
| Q11 | policy-y (opens an IP range) |
| Q12 | old default StorageClass kept |
| Q13 | `expose` without named port / nodePort 30080 |
| Q14 | ConfigMap changed without restarting the Pods |
| Q15 | `kubectl set resources` instead of `patch` |
| Q16 | limits raised together with the requests |
| Q17 | wrong toleration value |
| Q19 | Flannel (no NetworkPolicy) |
