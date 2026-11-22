# Exam simulator (local, multipass)

A practice environment that looks and feels like the remote exam desktop, running entirely on your machine:

- **Left:** the tasks, a 120-minute timer, question navigation and flags. As in the exam, click a highlighted value to copy it (no pop-up), then paste it in the desktop terminal with <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>V</kbd>; the rest of the task text cannot be copied. The *Suggested docs* links open in a new tab of the desktop's Firefox.
- **Copying inside the desktop** works like a normal Linux desktop: selecting text copies nothing, use <kbd>Ctrl</kbd>+<kbd>C</kbd> in Firefox and <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>C</kbd> in the terminal (Xvnc runs with `-SendPrimary=0`).
- **Right:** a real Linux desktop (XFCE) streamed with noVNC. It has `xfce4-terminal`, `vim`, and Firefox restricted to the docs the exam allows (kubernetes.io, helm.sh, gateway-api.sigs.k8s.io). You get the real terminal shortcuts, the real copy/paste behaviour and the real habit of running `ssh controlplane` first.
- **⌨ Shortcuts:** a cheat sheet plus a drill that asks for 15 random shortcuts and times you.
- **Lab buttons:** *Set up*, *Check* and *Reset* for each question, and *End exam*, which grades everything and shows the score. They run the repo scripts over ssh on the question's host.
- **One host per task, like the exam:** each task starts with *Solve this question on: `ssh cka2556`*. A host is a small kubeadm cluster of its own. The ordinary questions of an exam are spread over two shared hosts, mixed so that going through the tasks in order keeps you switching: `exit`, then `ssh` to the next host. The questions that break a cluster (a node upgrade, a broken kube-apiserver, a removed CNI, a tainted only worker) get a host each, so they never block the others. *Reset* on such a question restores its host from a snapshot in about 20 seconds.

```
your browser ──► desktop VM :8080  exam-sim (Go) ─┬─ noVNC ⇄ Xvnc :1 (XFCE, terminal, Firefox)
                                                   └─ ssh root@<host> → scripts/*.sh
                 Incus system containers on the same VM, one kubeadm cluster per host:
                 cka2556 (controlplane) + cka2556-node01 (node01) · cka8841 · cka4709 · …
```

`cka/mock-*/hosts.txt` maps questions to hosts. Inside every cluster the nodes keep the names the tasks use (`controlplane`, `node01`), Calico is the CNI and `local-path` the default StorageClass.

## Requirements

- [multipass](https://multipass.run/install) on Linux, macOS or Windows. On Windows, run the script from Git Bash or WSL.
- One VM of **8 GB RAM and 4 CPUs** (`MEM`, `CPUS`), about 60 GB of disk (sparse, actual use is around 15 GB). To save memory only the shared hosts of the exam you are on and one other host run at a time; a stopped host keeps its state and starts again (about 20 seconds) as soon as you open one of its questions. With more memory, `EXAM_KEEP_RUNNING=all simulator/lab.sh up` keeps every host running.
- Internet access from the VM: apt, pkgs.k8s.io, images.linuxcontainers.org, GitHub raw, the Mozilla apt repo, and the Go module proxy.

## Start

```bash
simulator/lab.sh up
```

This takes about 15–20 minutes the first time: the desktop, then a `k8s-base` container with everything pre-installed, then each host is cloned from it (under a minute per host) and snapshotted. It prints a link like `http://<vm-ip>:8080/login?t=…`. Open it in **Chrome or Edge**, which support the keyboard lock described below; Firefox also works. Then:

1. In the start dialog, **choose the exam** (today only CKA Mock 1; every `cka/mock-*` folder shows up here), keep *Set up all labs first* checked and press **Start exam**. The timer starts once setup has finished. Each exam has its own hosts, timer and flags; click the exam name in the top bar to switch.
2. Click **⛶ Fullscreen**. In Chrome/Edge this locks the keyboard, so <kbd>Ctrl</kbd>+<kbd>W</kbd>, <kbd>Ctrl</kbd>+<kbd>T</kbd>, <kbd>Ctrl</kbd>+<kbd>N</kbd> and <kbd>Alt</kbd>+<kbd>Tab</kbd> go to the desktop instead of your browser. Hold <kbd>Esc</kbd> to leave fullscreen.
3. On the desktop, open the terminal and run the `ssh <host>` shown above the task. You are now root on that host's controlplane, set up like the exam's ssh hosts: `kubectl` with the `k` alias and Bash completion, `yq`, `jq`, `curl`, `wget`, `man`, `tmux`, and a `~/.vimrc` with `tabstop=2 expandtab shiftwidth=2`. From there `ssh node01` reaches the worker. Leave with `exit` before the next task. As in the exam, the desktop terminal itself (the `base` system) has none of these tools: solve every task after `ssh`.

Other commands:

```bash
simulator/lab.sh url            # print the link again
```

```bash
simulator/lab.sh status         # the VM and the exam hosts
```

```bash
simulator/lab.sh reset cka2556  # restore a host from its snapshot (all labs on it are gone)
```

```bash
simulator/lab.sh ssh cka2556    # root shell on a host's controlplane, from your machine
```

```bash
simulator/lab.sh stop           # pause the VM; 'start' resumes and prints the link
```

```bash
simulator/lab.sh down           # delete the VM (also the controlplane/node01 VMs of older versions)
```

Variables: `K8S_MINOR=v1.33` pins the Kubernetes minor (the default is the current stable). `MEM`, `CPUS` and `DISK` size the VM.

## How the hosts work

`simulator/incus/exam-hosts.sh` (installed on the VM as `exam-hostctl`) does the work:

- Each node is a privileged Incus system container with systemd, containerd, kubeadm and sshd, so node-level tasks (`crictl`, `systemctl restart kubelet`, static Pod manifests, `apt` upgrades, `kubeadm join`, sysctl) behave like on a VM. The containers share the VM's kernel: the VM loads the kernel modules the clusters need, and sysctls that only exist once per kernel (like `nf_conntrack_max`) cannot be set from a host.
- Every node is cloned from `k8s-base`, which already has the packages and the images, and gets a fixed address on `incusbr0`, so a host survives stops and restores. Its CPU and memory are limited (`CPUS=2`, `CP_MEM=2560MiB`, `NODE_MEM=2GiB`), and `kubectl describe node` shows these limits as the node's capacity.
- `exam-hostctl e2e cka/mock-01` runs `tests/run-e2e.sh` for every question on its host; `exam-hostctl e2e cka/mock-01 cka8841` only the questions of one host, `exam-hostctl e2e cka/mock-01 13` one question. CI has one job per exam: it builds the host of the question named by the `# e2e: <n>` line of `hosts.txt` (`exam-hostctl build <mock> <host>`), which checks that the environment comes up, and e2e-tests that one question. `E2E_ALL=1 exam-hostctl e2e-plan` (the workflow run by hand with *all questions*) gives one job per host with every question.

## Notes

- Copying from the desktop to your own machine works when the page is served over https or from localhost. Over plain http on the VM IP the browser blocks it, so copy inside the desktop instead.
- Logs from `lab.sh up` are written to `simulator/.state/*.log`. On the VM: `journalctl --user -u exam-sim` (as `candidate`), `sudo exam-hostctl status`.

## Developing the UI

```bash
cd simulator && go test ./... && go run . -dump | head
```

```bash
go run . -addr 127.0.0.1:8099 -lab-ssh "" -lab-dir "$PWD/.."   # needs an Xvnc on :1 and noVNC in /usr/share/novnc
```

`main.go` is the HTTP server and token login, `vnc.go` is the WebSocket⇄VNC bridge (it replaces websockify), `lab.go` runs the lab scripts on the question's host (`-lab-ssh 'root@{host}'`, `-hostctl`), `questions.go` loads the question sets (every `*/mock-*` folder; `-mock` only picks the default), and `web/` holds the UI. `provision/*.sh` and `incus/exam-hosts.sh` are run by `lab.sh` inside the VM.
