# k8s-exam-practice

Hands-on practice labs for Kubernetes certification exams. Each question ships a setup script, the task, a solution and an **auto-grader**. Layout inspired by [markdjones82/CKA-PREP-2025-v2](https://github.com/markdjones82/CKA-PREP-2025-v2).

| Exam | Set | Status |
|---|---|---|
| CKA | [`cka/mock-01`](cka/mock-01) — 19 questions from CKA-PREP-2025-v2 | ✅ |
| CKAD / CKS | — | planned |

## Start the lab

The labs run in the exam simulator: one VM on your machine (multipass) with a Linux desktop (XFCE, xfce4-terminal, Firefox with docs only) shown in the browser next to the tasks, with a timer, flags, auto-grading and a keyboard-shortcut drill. Like the exam, each task names the host to `ssh` to: every host is a small kubeadm cluster of its own (Incus system containers on the VM), and the questions that break a cluster have one each, restored from a snapshot in seconds.

```bash
git clone https://github.com/tuan1412/k8s-exam-practice.git && cd k8s-exam-practice
```

```bash
simulator/lab.sh up
```

It prints a link to open in the browser; pick the exam, press *Start exam*, then `ssh <host>` on the desktop for each task. Requirements, commands and how the hosts work: [`simulator/README.md`](simulator/README.md).

## Layout

```
simulator/              the exam simulator (lab.sh, desktop, exam hosts)
scripts/                what the simulator runs on a question's host
  run-question.sh       set up a lab and print the task  (one question or 'all')
  validate-question.sh  grade                            ('all' -> score /100)
  cleanup-question.sh   remove resources to retry
  list-questions.sh     list questions with points
cka/mock-01/
  ANSWER-KEY.md         full solutions + traps
  scoring.tsv           points per question
  hosts.txt             which exam host each question runs on
  Question-01-MariaDB-Persistent-Volume/
    LabSetUp.bash       creates the scenario
    Questions.bash      the task
    SolutionNotes.bash  solution + traps (don't peek!)
    validate.bash       PASS/FAIL checks
    cleanup.bash        removes the question's resources
tests/                  e2e tests of the labs themselves
```

## Notes on the labs

- Each host has 1 controlplane and at most 1 worker (`node01`). Graders adapt to the worker count.
- Calico is the CNI (it enforces NetworkPolicy) and `local-path` the default StorageClass.
- Some setups need internet (helm charts, CRDs, images not pre-pulled).

## Testing the labs

`tests/run-e2e.sh` checks per question: setup → grade (must FAIL) → common wrong answer (must FAIL) → correct answer (must PASS). CI builds the environment and tests one question per exam. See [`tests/README.md`](tests/README.md).

## Adding a set

Create `cka/mock-xx/` with `Question-NN-Name/` folders holding the 5 files above, plus `scoring.tsv` (`folder<TAB>points<TAB>domain`) and `hosts.txt` (`host<TAB>workers<TAB>questions`, plus a `# e2e: <n>` line for the question CI tests). Add a `DESTRUCTIVE` file (containing the warning) to questions that break the cluster and give them a host of their own. Add `tests/<set>/solutions/<folder>.sh` and `wrong/<folder>.sh`. In `validate.bash`:

```bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
check    "description" <command that exits 0 when correct>
check_eq "description" "<actual>" "<expected>"
finish
```

## License

For personal, non-commercial self-study only: see [LICENSE](LICENSE). The mock 1 questions are rebuilt from [markdjones82/CKA-PREP-2025-v2](https://github.com/markdjones82/CKA-PREP-2025-v2) ([NOTICE.md](NOTICE.md)). Not affiliated with the Linux Foundation, the CNCF or PSI; these are practice questions, not real exam questions.
