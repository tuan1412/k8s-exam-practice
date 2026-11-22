package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
)

// labRunner runs the repo's lab scripts on the exam hosts (over ssh) and streams
// their output back to the UI.
//
// Without hosts (ssh target without "{host}", or a set without hosts.txt) every
// question runs on one lab host. With hosts, ssh is a template like "root@{host}",
// each question runs on its host from hosts.txt, and hostctl (simulator/incus/exam-hosts.sh)
// starts hosts and restores the snapshot of a question's own host on Reset.
type labRunner struct {
	ssh, dir string
	repo     string
	hostctl  string           // command prefix, e.g. "sudo -n /usr/local/sbin/exam-hostctl"; "" = none
	exams    map[string]*Exam // by question set, e.g. "cka/mock-01"
	busy     chan struct{}    // one lab action at a time; the next one waits
}

// step is one command of a lab action: a lab script on a host, or a hostctl call here.
type step struct {
	host  string // lab host the script runs on; "" with local = hostctl on this machine
	local bool
	cmd   string
	q     int  // score: the question this validate step grades
	yes   bool // answer run-question.sh's confirmation of a destructive question
}

func (l *labRunner) question(mock string, n int) *Question {
	e := l.exams[mock]
	if e == nil {
		return nil
	}
	for i := range e.Questions {
		if e.Questions[i].N == n {
			return &e.Questions[i]
		}
	}
	return nil
}

func shq(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

func (l *labRunner) hostsMode(mock string) bool {
	return strings.Contains(l.ssh, "{host}") && len(l.exams[mock].Hosts) > 0
}

// hostOf returns the host a question runs on ("controlplane" without hosts).
func (l *labRunner) hostOf(mock string, q *Question) string {
	if l.hostsMode(mock) {
		return q.Host
	}
	return "controlplane"
}

// use makes sure a host runs before its scripts do (hostctl stops other hosts to save memory).
func (l *labRunner) use(mock, host string) []step {
	if !l.hostsMode(mock) || l.hostctl == "" {
		return nil
	}
	return []step{{local: true, cmd: l.hostctl + " use " + shq(mock) + " " + shq(host)}}
}

// plan maps a UI action to fixed commands; nothing from the request reaches the shell
// except a known question set and a validated question number. confirm: the question is
// destructive and the UI already asked.
func (l *labRunner) plan(mock, action string, n int) (steps []step, confirm bool, err error) {
	e := l.exams[mock]
	if e == nil {
		return nil, false, fmt.Errorf("unknown question set %q", mock)
	}
	m := "-m " + shq(mock)
	run := func(script string, q *Question) step {
		return step{host: l.hostOf(mock, q), cmd: "scripts/" + script + " " + m + " " + strconv.Itoa(q.N), q: q.N,
			yes: script == "run-question.sh" && q.Destructive}
	}
	switch action {
	case "reset-all": // restart from scratch: every host of the exam back to its fresh snapshot
		if !l.hostsMode(mock) || l.hostctl == "" {
			return []step{{host: "controlplane", cmd: "scripts/cleanup-question.sh " + m + " all"}}, false, nil
		}
		for _, h := range e.Hosts {
			steps = append(steps, step{local: true, cmd: l.hostctl + " reset " + shq(h)})
		}
		return steps, false, nil
	case "setup-all", "cleanup-all", "score":
		if !l.hostsMode(mock) {
			script := map[string]string{"setup-all": "run-question.sh", "cleanup-all": "cleanup-question.sh", "score": "validate-question.sh"}[action]
			return []step{{host: "controlplane", cmd: "scripts/" + script + " " + m + " all"}}, false, nil
		}
		for _, h := range e.Hosts { // host by host, so each one is started once
			var hs []step
			for i := range e.Questions {
				q := &e.Questions[i]
				if q.Host != h {
					continue
				}
				switch {
				case action == "setup-all" && (!q.Destructive || q.HostReset): // on a shared host, destructive ones are set up alone
					hs = append(hs, run("run-question.sh", q))
				case action == "cleanup-all" && q.HostReset && l.hostctl != "":
					hs = append(hs, step{local: true, cmd: l.hostctl + " reset " + shq(h)})
				case action == "cleanup-all":
					hs = append(hs, run("cleanup-question.sh", q))
				case action == "score":
					hs = append(hs, run("validate-question.sh", q))
				}
			}
			if len(hs) > 0 {
				steps = append(append(steps, l.use(mock, h)...), hs...)
			}
		}
		return steps, false, nil
	}
	q := l.question(mock, n)
	if q == nil {
		return nil, false, fmt.Errorf("unknown question %d", n)
	}
	host := l.hostOf(mock, q)
	switch action {
	case "use": // the UI shows the question: its host must accept ssh
		return l.use(mock, host), false, nil
	case "setup":
		return append(l.use(mock, host), run("run-question.sh", q)), q.Destructive, nil
	case "validate":
		return append(l.use(mock, host), run("validate-question.sh", q)), false, nil
	case "cleanup":
		if q.HostReset && l.hostsMode(mock) && l.hostctl != "" {
			return append(l.use(mock, host), step{local: true, cmd: l.hostctl + " reset " + shq(host)}), false, nil
		}
		return append(l.use(mock, host), run("cleanup-question.sh", q)), false, nil
	}
	return nil, false, fmt.Errorf("unknown action %q", action)
}

func (l *labRunner) command(r *http.Request, s step) (*exec.Cmd, string) {
	if s.local {
		return exec.CommandContext(r.Context(), "bash", "-c", s.cmd+" 2>&1"), "$ " + s.cmd
	}
	full := "cd " + shq(l.dir) + " && " + s.cmd + " 2>&1"
	if l.ssh == "" {
		return exec.CommandContext(r.Context(), "bash", "-c", full), "$ " + s.cmd
	}
	target := strings.ReplaceAll(l.ssh, "{host}", s.host)
	cmd := exec.CommandContext(r.Context(), "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
		"-o", "StrictHostKeyChecking=accept-new", target, full)
	if strings.Contains(l.ssh, "{host}") {
		return cmd, s.host + " $ " + s.cmd
	}
	return cmd, "$ " + s.cmd
}

func (l *labRunner) run(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Action string `json:"action"`
		Q      int    `json:"q"`
		Mock   string `json:"mock"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	steps, confirm, err := l.plan(req.Mock, req.Action, req.Q)
	if l.hostsMode(req.Mock) {
		confirm = true // destructive questions have hosts of their own
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	// wait for the action before (often the background start of a question's host)
	select {
	case l.busy <- struct{}{}:
		defer func() { <-l.busy }()
	case <-r.Context().Done():
		return
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	fw := &flushWriter{w: w}
	score := req.Action == "score" && l.hostsMode(req.Mock)
	results := map[int]string{} // score: "passed/checks" per question
	for _, s := range steps {
		cmd, label := l.command(r, s)
		fmt.Fprintf(fw, "%s\n", label)
		if s.yes && confirm { // the UI asked, or the question has a host of its own
			cmd.Stdin = strings.NewReader("y\n")
		}
		var buf strings.Builder
		cmd.Stdout = io.MultiWriter(fw, &buf)
		cmd.Stderr = cmd.Stdout
		if err := cmd.Run(); err != nil {
			fmt.Fprintf(fw, "[exit: %v]\n", err)
			if r.Context().Err() != nil || (s.local && !score) {
				return // stopped by the user, or a host could not be started
			}
		}
		fmt.Fprintln(fw)
		if score && s.q > 0 {
			results[s.q] = lastResult(buf.String())
		}
	}
	if score {
		writeScore(fw, l.exams[req.Mock], results)
	}
}

var reResult = regexp.MustCompile(`RESULT (\d+)/(\d+)`)
var reANSI = regexp.MustCompile(`\x1b\[[0-9;]*m`)

func lastResult(out string) string {
	m := reResult.FindAllStringSubmatch(reANSI.ReplaceAllString(out, ""), -1)
	if len(m) == 0 {
		return ""
	}
	return m[len(m)-1][1] + "/" + m[len(m)-1][2]
}

// writeScore prints the table of scripts/validate-question.sh all for grades from several hosts.
func writeScore(w io.Writer, e *Exam, results map[int]string) {
	total, maxPts := 0.0, 0
	var rows strings.Builder
	for _, q := range e.Questions {
		res, got := results[q.N], 0.0
		var p, c int
		if _, err := fmt.Sscanf(res, "%d/%d", &p, &c); err == nil && c > 0 {
			got = float64(q.Weight) * float64(p) / float64(c)
		} else {
			res = "error"
		}
		total += got
		maxPts += q.Weight
		fmt.Fprintf(&rows, "%-45s %8s %6.1f/%d\n", q.Folder, res, got, q.Weight)
	}
	fmt.Fprintf(w, "\n== SCORE %s\n%-45s %8s %9s\n%s", filepath.Base(e.Mock), "Question", "checks", "points", rows.String())
	fmt.Fprintln(w, "-----------------------------------------------------------------")
	fmt.Fprintf(w, "%-45s %18s\n", "TOTAL", fmt.Sprintf("%.1f/%d", total, maxPts))
	if total >= float64(e.PassMark) {
		fmt.Fprintf(w, "PASS (real exam: %d%%)\n", e.PassMark)
	} else {
		fmt.Fprintf(w, "FAIL (need >= %d)\n", e.PassMark)
	}
}

func (l *labRunner) solution(w http.ResponseWriter, r *http.Request) {
	mock := r.URL.Query().Get("mock")
	n, _ := strconv.Atoi(r.URL.Query().Get("q"))
	q := l.question(mock, n)
	if q == nil {
		http.Error(w, "unknown question", http.StatusNotFound)
		return
	}
	b, err := os.ReadFile(filepath.Join(l.repo, mock, q.Folder, "SolutionNotes.bash"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write(b)
}

type flushWriter struct {
	mu sync.Mutex
	w  http.ResponseWriter
}

func (f *flushWriter) Write(p []byte) (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	n, err := f.w.Write(p)
	if fl, ok := f.w.(http.Flusher); ok {
		fl.Flush()
	}
	return n, err
}
