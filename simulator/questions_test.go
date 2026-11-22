package main

import (
	"fmt"
	"regexp"
	"strings"
	"testing"
)

func TestLoadMock01(t *testing.T) {
	repo := findRepo(".")
	exam, err := loadExam(repo, "cka/mock-01")
	if err != nil {
		t.Fatal(err)
	}
	if exam.Title != "CKA Mock 1" || len(exam.Questions) != 19 {
		t.Fatalf("got %q with %d questions, want CKA Mock 1 with 19", exam.Title, len(exam.Questions))
	}
	total := 0
	for i, q := range exam.Questions {
		total += q.Weight
		if q.N != i+1 || q.Title == "" || q.Body == "" || q.Domain == "" || q.Weight == 0 {
			t.Errorf("Q%d incomplete: %+v", q.N, q)
		}
		if strings.Contains(q.Body, "```\n") && strings.HasPrefix(q.Body, "```") {
			t.Errorf("Q%d body not taken from ANSWER-KEY", q.N)
		}
		if destructive := q.N == 18 || q.N == 19; destructive != (q.Warning != "") {
			t.Errorf("Q%d warning = %q", q.N, q.Warning)
		}
	}
	if total != 100 {
		t.Errorf("weights sum to %d, want 100", total)
	}
	if q := exam.Questions[3]; !strings.Contains(q.Body, "`node01`") {
		t.Errorf("Q4 should name node01: %q", q.Body)
	}
}

func TestListMocksAndScript(t *testing.T) {
	repo := findRepo(".")
	sets := listMocks(repo)
	if len(sets) < 1 || sets[0] != "cka/mock-01" {
		t.Fatalf("listMocks = %v", sets)
	}
	exams := map[string]*Exam{}
	for _, m := range sets {
		e, err := loadExam(repo, m)
		if err != nil {
			t.Fatal(err)
		}
		exams[m] = e
	}
	cmds := func(steps []step) (out []string) {
		for _, s := range steps {
			where := s.host
			if s.local {
				where = "local"
			}
			out = append(out, where+": "+s.cmd)
		}
		return out
	}

	// one lab host (a set without hosts.txt)
	l := &labRunner{ssh: "root@controlplane", exams: exams}
	if steps, confirm, err := l.plan("cka/mock-01", "setup", 18); err != nil || !confirm ||
		strings.Join(cmds(steps), "|") != "controlplane: scripts/run-question.sh -m 'cka/mock-01' 18" {
		t.Errorf("setup Q18: %q %v %v", cmds(steps), confirm, err)
	}
	if steps, _, err := l.plan("cka/mock-01", "cleanup-all", 0); err != nil ||
		strings.Join(cmds(steps), "|") != "controlplane: scripts/cleanup-question.sh -m 'cka/mock-01' all" {
		t.Errorf("cleanup-all: %q %v", cmds(steps), err)
	}
	for _, bad := range []struct {
		mock, action string
		n            int
	}{{"cka/mock-01; rm -rf /", "score", 0}, {"cka/mock-01", "setup", 20}, {"cka/mock-01", "rm", 1}, {"cka/mock-99", "setup", 1}} {
		if _, _, err := l.plan(bad.mock, bad.action, bad.n); err == nil {
			t.Errorf("plan(%q, %q, %d) should fail", bad.mock, bad.action, bad.n)
		}
	}

	// exam hosts
	h := &labRunner{ssh: "root@{host}", hostctl: "hostctl", exams: exams}
	want := map[string][]string{
		"setup 8":     {"local: hostctl use 'cka/mock-01' 'cka8841'", "cka8841: scripts/run-question.sh -m 'cka/mock-01' 8"},
		"cleanup 8":   {"local: hostctl use 'cka/mock-01' 'cka8841'", "cka8841: scripts/cleanup-question.sh -m 'cka/mock-01' 8"},
		"cleanup 18":  {"local: hostctl use 'cka/mock-01' 'cka4709'", "local: hostctl reset 'cka4709'"},
		"validate 19": {"local: hostctl use 'cka/mock-01' 'cka1932'", "cka1932: scripts/validate-question.sh -m 'cka/mock-01' 19"},
		"use 4":       {"local: hostctl use 'cka/mock-01' 'cka2556'"},
	}
	for k, w := range want {
		a, ns, _ := strings.Cut(k, " ")
		n := 0
		fmt.Sscan(ns, &n)
		if steps, _, err := h.plan("cka/mock-01", a, n); err != nil || strings.Join(cmds(steps), "|") != strings.Join(w, "|") {
			t.Errorf("%s: got %q, want %q (%v)", k, cmds(steps), w, err)
		}
	}
	steps, _, _ := h.plan("cka/mock-01", "setup-all", 0)
	got := strings.Join(cmds(steps), "\n")
	// destructive questions have hosts of their own: set up with the rest, answering "y"
	if !strings.Contains(got, "cka4709: scripts/run-question.sh -m 'cka/mock-01' 18") || strings.Count(got, "hostctl use") != 5 ||
		strings.Count(got, "run-question.sh") != 19 || !steps[len(steps)-1].yes || steps[1].yes {
		t.Errorf("setup-all:\n%s", got)
	}
	steps, _, _ = h.plan("cka/mock-01", "score", 0)
	if n := strings.Count(strings.Join(cmds(steps), "\n"), "validate-question.sh"); n != 19 {
		t.Errorf("score runs %d graders, want 19", n)
	}
	if q := h.question("cka/mock-01", 17); q.Host != "cka6173" || !q.HostReset {
		t.Errorf("Q17 host: %+v", q)
	}
	if q := h.question("cka/mock-01", 3); q.Host != "cka8841" || q.HostReset {
		t.Errorf("Q3 host: %+v", q)
	}
	steps, _, _ = h.plan("cka/mock-01", "reset-all", 0)
	if got := strings.Join(cmds(steps), "|"); got != "local: hostctl reset 'cka2556'|local: hostctl reset 'cka8841'|local: hostctl reset 'cka6173'|local: hostctl reset 'cka4709'|local: hostctl reset 'cka1932'" {
		t.Errorf("reset-all: %q", got)
	}
	if nl, _, _ := l.plan("cka/mock-01", "use", 4); len(nl) != 0 {
		t.Errorf("use without hosts should do nothing: %q", cmds(nl))
	}
}

func TestWriteScore(t *testing.T) {
	e := &Exam{Mock: "cka/mock-x", PassMark: 66, Questions: []Question{
		{N: 1, Folder: "Question-01-A", Weight: 60}, {N: 2, Folder: "Question-02-B", Weight: 40}}}
	var b strings.Builder
	writeScore(&b, e, map[int]string{1: "3/3", 2: ""})
	if !strings.Contains(b.String(), "TOTAL") || !strings.Contains(b.String(), "60.0/100") ||
		!strings.Contains(b.String(), "FAIL (need >= 66)") || !strings.Contains(b.String(), "error") {
		t.Errorf("score table:\n%s", b.String())
	}
	if r := lastResult("\x1b[1mRESULT 2/5 checks\nRESULT 4/5 checks passed"); r != "4/5" {
		t.Errorf("lastResult = %q", r)
	}
}

func TestDocURL(t *testing.T) {
	for raw, want := range map[string]bool{
		"https://kubernetes.io/docs/concepts/storage/persistent-volumes/":                true,
		"https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport": true,
		"https://helm.sh/docs/": true,
		"https://gateway-api.sigs.k8s.io/reference/api-types/gateway/": true,
		"https://v1-33.docs.kubernetes.io/docs/home/":                  true,
		"https://docs.tigera.io/calico/latest/": true,
		"https://kubernetes.io.evil.com/":                              false,
		"https://evilkubernetes.io/":                                   false,
		"file:///etc/passwd":                                           false,
		"-P evil":                                                      false,
		"https://user@kubernetes.io/":                                  false,
		"https://kubernetes.io:8443/":                                  false,
	} {
		if _, ok := docURL(raw); ok != want {
			t.Errorf("docURL(%q) = %v, want %v", raw, ok, want)
		}
	}
}

// Every doc link in the tasks must open in the desktop's Firefox, which only allows the exam's docs sites.
func TestDocLinksAllowed(t *testing.T) {
	repo := findRepo(".")
	link := regexp.MustCompile(`\]\((https?://[^)\s]+)\)`)
	for _, m := range listMocks(repo) {
		exam, err := loadExam(repo, m)
		if err != nil {
			t.Fatal(err)
		}
		for _, q := range exam.Questions {
			urls := link.FindAllStringSubmatch(q.Body, -1)
			if len(urls) == 0 {
				t.Errorf("%s Q%d has no doc link", m, q.N)
			}
			for _, u := range urls {
				if _, ok := docURL(u[1]); !ok {
					t.Errorf("%s Q%d: %s is not an allowed docs site", m, q.N, u[1])
				}
			}
		}
	}
}
