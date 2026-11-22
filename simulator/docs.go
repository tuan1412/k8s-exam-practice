package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
)

// docHosts are the documentation sites the exam allows; the desktop's Firefox only
// opens these too (WebsiteFilter in provision/desktop.sh).
var docHosts = []string{"kubernetes.io", "helm.sh", "gateway-api.sigs.k8s.io", "docs.tigera.io"}

// docURL returns the URL when it points to an allowed docs site.
func docURL(raw string) (string, bool) {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") || u.User != nil || u.Port() != "" {
		return "", false
	}
	h := strings.ToLower(u.Hostname())
	for _, d := range docHosts {
		if h == d || strings.HasSuffix(h, "."+d) {
			return u.String(), true
		}
	}
	return "", false
}

// docOpener opens doc links from the task pane in a new tab of the desktop's Firefox,
// like the links in the exam's task panel.
type docOpener struct {
	display string // X display of the desktop, e.g. ":1"
	browser string // browser command
}

func (d *docOpener) open(w http.ResponseWriter, r *http.Request) {
	var req struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	u, ok := docURL(req.URL)
	if !ok {
		http.Error(w, "only the allowed documentation sites can be opened", http.StatusBadRequest)
		return
	}
	cmd := exec.Command(d.browser, "--new-tab", u)
	cmd.Env = append(os.Environ(), "DISPLAY="+d.display)
	if err := cmd.Start(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	// "firefox --new-tab" hands the URL to the running browser and exits, or becomes the browser
	go func() {
		if err := cmd.Wait(); err != nil {
			log.Printf("open doc %s: %v", u, err)
		}
	}()
	w.WriteHeader(http.StatusNoContent)
}
