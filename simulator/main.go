// Command exam-sim serves the exam simulator UI: the task panel on the left and
// the remote Linux desktop (noVNC -> Xvnc) on the right. It runs on the "desktop"
// VM created by simulator/lab.sh, see simulator/README.md.
package main

import (
	"crypto/rand"
	"crypto/subtle"
	"embed"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
)

//go:embed web
var webFS embed.FS

const cookieName = "examsim"

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "listen address")
	repo := flag.String("repo", "", "repo root (default: search upwards from the current directory)")
	mock := flag.String("mock", "cka/mock-01", "question set selected by default (all sets of the repo are offered)")
	novnc := flag.String("novnc", "/usr/share/novnc", "noVNC directory (must contain core/rfb.js)")
	vnc := flag.String("vnc", "127.0.0.1:5901", "VNC server (Xvnc) address")
	labSSH := flag.String("lab-ssh", "root@controlplane", "ssh target that runs the lab scripts ('' = run locally)")
	labDir := flag.String("lab-dir", "/root/k8s-exam-practice", "repo path on the lab host")
	hostctl := flag.String("hostctl", "", "command that manages the exam hosts (simulator/incus/exam-hosts.sh), with -lab-ssh 'root@{host}'")
	display := flag.String("display", "", "X display of the desktop (e.g. :1): doc links open in its Firefox; empty = in the user's browser")
	browser := flag.String("browser", "firefox", "browser started on -display for doc links")
	tokenFile := flag.String("token-file", "", "file with the access token (created if missing); empty = no auth")
	duration := flag.Int("duration", 120, "exam time in minutes")
	dump := flag.Bool("dump", false, "print the question set as JSON and exit")
	flag.Parse()

	if *repo == "" {
		*repo = findRepo(".")
	}
	sets := listMocks(*repo)
	if len(sets) == 0 {
		log.Fatalf("no question sets (*/mock-*) in %q", *repo)
	}
	exams := map[string]*Exam{}
	for _, m := range sets {
		e, err := loadExam(*repo, m)
		if err != nil {
			log.Fatal(err)
		}
		e.DurationMin = *duration
		e.LabDir = *labDir
		if !strings.Contains(*labSSH, "{host}") {
			e.Hosts = nil // one lab host for every question
			for i := range e.Questions {
				e.Questions[i].Host, e.Questions[i].HostReset = "", false
			}
		}
		for i := range e.Questions {
			if q := &e.Questions[i]; q.HostReset {
				q.Warning = "" // it cannot break the other questions
				q.LabNotes = append([]string{"This question has a host of its own: whatever happens there does not affect the others. Reset restores the host from a snapshot."}, q.LabNotes...)
			}
		}
		e.DocsInDesktop = *display != ""
		exams[m] = e
	}
	if exams[*mock] == nil {
		log.Printf("question set %q not found, using %s", *mock, sets[0])
		*mock = sets[0]
	}
	if *dump {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(exams[*mock])
		return
	}

	token := ""
	var err error
	if *tokenFile != "" {
		if token, err = loadOrCreateToken(*tokenFile); err != nil {
			log.Fatal(err)
		}
	}

	lab := &labRunner{ssh: *labSSH, dir: *labDir, repo: *repo, hostctl: *hostctl, exams: exams, busy: make(chan struct{}, 1)}
	static, _ := fs.Sub(webFS, "web")

	// the exam list, in repo order, with the default first-time choice
	type examInfo struct {
		Mock      string `json:"mock"`
		Title     string `json:"title"`
		Questions int    `json:"questions"`
		Points    int    `json:"points"`
		Default   bool   `json:"default,omitempty"`
	}
	var list []examInfo
	for _, m := range sets {
		pts := 0
		for _, q := range exams[m].Questions {
			pts += q.Weight
		}
		list = append(list, examInfo{m, exams[m].Title, len(exams[m].Questions), pts, m == *mock})
	}

	mux := http.NewServeMux()
	mux.Handle("GET /", http.FileServer(http.FS(static)))
	mux.Handle("GET /novnc/", http.StripPrefix("/novnc/", http.FileServer(http.Dir(*novnc))))
	mux.HandleFunc("GET /api/exams", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(list)
	})
	mux.HandleFunc("GET /api/exam", func(w http.ResponseWriter, r *http.Request) {
		m := r.URL.Query().Get("mock")
		if m == "" {
			m = *mock
		}
		e := exams[m]
		if e == nil {
			http.Error(w, "unknown question set", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(e)
	})
	mux.HandleFunc("GET /api/solution", lab.solution)
	mux.HandleFunc("POST /api/lab", lab.run)
	if *display != "" {
		mux.HandleFunc("POST /api/open-doc", (&docOpener{display: *display, browser: *browser}).open)
	}
	mux.HandleFunc("GET /websockify", vncProxy(*vnc))

	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatal(err)
	}
	url := "http://" + ln.Addr().String() + "/"
	if token != "" {
		url += "login?t=" + token
	}
	fmt.Printf("exam-sim: question sets %s in %s\nOpen: %s\n", strings.Join(sets, ", "), *repo, url)
	log.Fatal(http.Serve(ln, auth(token, mux)))
}

// auth accepts /login?t=<token> once, then requires the cookie it sets.
func auth(token string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if token == "" {
			next.ServeHTTP(w, r)
			return
		}
		if r.URL.Path == "/login" {
			if subtle.ConstantTimeCompare([]byte(r.URL.Query().Get("t")), []byte(token)) != 1 {
				http.Error(w, "wrong token", http.StatusForbidden)
				return
			}
			http.SetCookie(w, &http.Cookie{Name: cookieName, Value: token, Path: "/", HttpOnly: true,
				SameSite: http.SameSiteStrictMode, MaxAge: 30 * 24 * 3600})
			http.Redirect(w, r, "/", http.StatusFound)
			return
		}
		c, err := r.Cookie(cookieName)
		if err != nil || subtle.ConstantTimeCompare([]byte(c.Value), []byte(token)) != 1 {
			http.Error(w, "Open the login link printed by 'simulator/lab.sh url'.", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func loadOrCreateToken(path string) (string, error) {
	if b, err := os.ReadFile(path); err == nil && len(strings.TrimSpace(string(b))) >= 16 {
		return strings.TrimSpace(string(b)), nil
	}
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	t := hex.EncodeToString(b)
	return t, os.WriteFile(path, []byte(t+"\n"), 0o600)
}
