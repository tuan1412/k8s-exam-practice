package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Question is one exam task as shown in the question panel.
type Question struct {
	N        int      `json:"n"`
	Folder   string   `json:"folder"`
	Title    string   `json:"title"`
	Weight   int      `json:"weight"`
	Domain   string   `json:"domain"`
	Body     string   `json:"body"` // light markdown: `code`, **bold**, *italic*, - lists, ``` fences
	LabNotes []string `json:"labNotes"`
	Warning  string   `json:"warning,omitempty"` // content of the DESTRUCTIVE file, if any
	Host     string   `json:"host,omitempty"`    // exam host from hosts.txt ("ssh <host>")
	// HostReset: the question has a host of its own, Reset restores the host's snapshot
	HostReset   bool `json:"hostReset,omitempty"`
	Destructive bool `json:"-"` // DESTRUCTIVE file: run-question.sh asks for confirmation
}

// Exam is what the UI needs to render a mock exam.
type Exam struct {
	Title       string `json:"title"`
	Mock        string `json:"mock"`
	DurationMin int    `json:"durationMin"`
	PassMark    int    `json:"passMark"`
	LabDir      string `json:"labDir"` // repo path as seen from inside the terminal
	// DocsInDesktop: doc links open in the desktop's Firefox (POST /api/open-doc)
	DocsInDesktop bool       `json:"docsInDesktop"`
	Questions     []Question `json:"questions"`
	Hosts         []string   `json:"hosts,omitempty"` // from hosts.txt
}

var (
	reHeading  = regexp.MustCompile(`^### Q(\d+) · (.+)$`)
	reFolder   = regexp.MustCompile(`^Question-(\d+)-`)
	reHeredoc  = regexp.MustCompile(`<<'?QUESTION'?\s*$`)
	reMockName = regexp.MustCompile(`mock-(\d+)$`)
)

// loadExam reads the question folders, scoring.tsv and ANSWER-KEY.md of one set.
func loadExam(repo, mock string) (*Exam, error) {
	dir := filepath.Join(repo, mock)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("question set %s: %w", dir, err)
	}
	scoring := readScoring(filepath.Join(dir, "scoring.tsv"))
	key := readAnswerKey(filepath.Join(dir, "ANSWER-KEY.md"))

	var qs []Question
	for _, e := range entries {
		m := reFolder.FindStringSubmatch(e.Name())
		if !e.IsDir() || m == nil {
			continue
		}
		n, _ := strconv.Atoi(m[1])
		qdir := filepath.Join(dir, e.Name())
		title, plain, notes := readQuestionsBash(filepath.Join(qdir, "Questions.bash"))
		q := Question{N: n, Folder: e.Name(), Title: title, LabNotes: notes}
		if s, ok := scoring[e.Name()]; ok {
			q.Weight, q.Domain = s.weight, s.domain
		}
		if k, ok := key[n]; ok {
			q.Title, q.Body = k.title, k.body
		} else {
			q.Body = "```\n" + plain + "\n```"
		}
		if q.Title == "" {
			q.Title = strings.ReplaceAll(strings.TrimPrefix(e.Name(), m[0]), "-", " ")
		}
		if b, err := os.ReadFile(filepath.Join(qdir, "DESTRUCTIVE")); err == nil {
			q.Warning, q.Destructive = strings.TrimSpace(string(b)), true
		}
		qs = append(qs, q)
	}
	if len(qs) == 0 {
		return nil, fmt.Errorf("no Question-* folders in %s", dir)
	}
	sort.Slice(qs, func(i, j int) bool { return qs[i].N < qs[j].N })

	hosts, err := readHosts(filepath.Join(dir, "hosts.txt"))
	if err != nil {
		return nil, err
	}
	var hostNames []string
	for _, h := range hosts {
		hostNames = append(hostNames, h.name)
		for j := range qs {
			if h.questions[qs[j].N] { // a host of its own is reset from its snapshot
				qs[j].Host, qs[j].HostReset = h.name, len(h.questions) == 1
			}
		}
	}
	for _, q := range qs {
		if len(hosts) > 0 && q.Host == "" {
			return nil, fmt.Errorf("%s/hosts.txt: no host for Q%d", mock, q.N)
		}
	}

	title := strings.ToUpper(strings.SplitN(mock, "/", 2)[0])
	if m := reMockName.FindStringSubmatch(mock); m != nil {
		n, _ := strconv.Atoi(m[1])
		title += fmt.Sprintf(" Mock %d", n)
	}
	return &Exam{Title: title, Mock: mock, DurationMin: 120, PassMark: 66, Questions: qs, Hosts: hostNames}, nil
}

type hostEntry struct {
	name      string
	questions map[int]bool
}

var reHost = regexp.MustCompile(`^[a-z][a-z0-9-]{0,30}$`)

// readHosts parses hosts.txt ("<host> <workers> <questions>", e.g. "cka2556 1 2 4 10-12").
// A missing file means no hosts: every question runs on the single lab host.
func readHosts(path string) ([]hostEntry, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	var out []hostEntry
	for i, line := range strings.Split(string(b), "\n") {
		f := strings.Fields(line)
		if len(f) == 0 || strings.HasPrefix(f[0], "#") {
			continue
		}
		if len(f) < 3 || !reHost.MatchString(f[0]) {
			return nil, fmt.Errorf("%s:%d: want <host> <workers> <questions>", path, i+1)
		}
		h := hostEntry{name: f[0], questions: map[int]bool{}}
		for _, r := range f[2:] {
			lo, hi, ok := strings.Cut(r, "-")
			a, err1 := strconv.Atoi(lo)
			z, err2 := a, error(nil)
			if ok {
				z, err2 = strconv.Atoi(hi)
			}
			if err1 != nil || err2 != nil || z < a {
				return nil, fmt.Errorf("%s:%d: bad question range %q", path, i+1, r)
			}
			for n := a; n <= z; n++ {
				h.questions[n] = true
			}
		}
		out = append(out, h)
	}
	return out, nil
}

type score struct {
	weight int
	domain string
}

func readScoring(path string) map[string]score {
	out := map[string]score{}
	f, err := os.Open(path)
	if err != nil {
		return out
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		p := strings.Split(sc.Text(), "\t")
		if len(p) < 2 {
			continue
		}
		w, _ := strconv.Atoi(strings.TrimSpace(p[1]))
		s := score{weight: w}
		if len(p) > 2 {
			s.domain = strings.TrimSpace(p[2])
		}
		out[strings.TrimSpace(p[0])] = s
	}
	return out
}

type keyEntry struct{ title, body string }

// readAnswerKey extracts, per question, the heading title and the quoted task text
// (the "> ..." block right after "### QN · Title").
func readAnswerKey(path string) map[int]keyEntry {
	out := map[int]keyEntry{}
	b, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	lines := strings.Split(string(b), "\n")
	for i := 0; i < len(lines); i++ {
		m := reHeading.FindStringSubmatch(strings.TrimRight(lines[i], " "))
		if m == nil {
			continue
		}
		n, _ := strconv.Atoi(m[1])
		j := i + 1
		for j < len(lines) && strings.TrimSpace(lines[j]) == "" {
			j++
		}
		var body []string
		for ; j < len(lines) && strings.HasPrefix(lines[j], ">"); j++ {
			l := strings.TrimPrefix(lines[j], ">")
			body = append(body, strings.TrimPrefix(l, " "))
		}
		if len(body) > 0 {
			out[n] = keyEntry{title: strings.TrimSpace(m[2]), body: strings.TrimSpace(strings.Join(body, "\n"))}
		}
		i = j - 1
	}
	return out
}

// readQuestionsBash returns the title line, the plain task text and the [Lab] notes
// from the heredoc in Questions.bash.
func readQuestionsBash(path string) (title, plain string, notes []string) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", "", nil
	}
	var text []string
	in := false
	for _, l := range strings.Split(string(b), "\n") {
		switch {
		case !in && reHeredoc.MatchString(l):
			in = true
		case in && strings.TrimSpace(l) == "QUESTION":
			in = false
		case in:
			text = append(text, l)
		}
	}
	for i, l := range text {
		l = strings.ReplaceAll(l, "${W}", "node01")
		text[i] = l
		if strings.HasPrefix(l, "[Lab]") {
			notes = append(notes, strings.TrimSpace(strings.TrimPrefix(l, "[Lab]")))
		}
	}
	if len(text) > 0 {
		if p := strings.SplitN(text[0], " · ", 2); len(p) == 2 {
			title = strings.TrimSpace(p[1])
		}
	}
	return title, strings.TrimSpace(strings.Join(text, "\n")), notes
}

// listMocks returns the question sets of the repo ("cka/mock-01", ...), sorted.
func listMocks(repo string) []string {
	dirs, _ := filepath.Glob(filepath.Join(repo, "*", "mock-*"))
	var out []string
	for _, d := range dirs {
		if qs, _ := filepath.Glob(filepath.Join(d, "Question-*")); len(qs) == 0 {
			continue
		}
		if rel, err := filepath.Rel(repo, d); err == nil {
			out = append(out, filepath.ToSlash(rel))
		}
	}
	sort.Strings(out)
	return out
}

// findRepo walks up from start looking for the folder that holds cka/.
func findRepo(start string) string {
	d, err := filepath.Abs(start)
	if err != nil {
		return ""
	}
	for {
		if st, err := os.Stat(filepath.Join(d, "cka")); err == nil && st.IsDir() {
			if _, err := os.Stat(filepath.Join(d, "scripts")); err == nil {
				return d
			}
		}
		p := filepath.Dir(d)
		if p == d {
			return ""
		}
		d = p
	}
}
