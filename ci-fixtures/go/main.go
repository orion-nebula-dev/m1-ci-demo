package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"runtime"
)

func sum(a, b int) int { return a + b }

func health(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/health" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "m1-ci-go-fixture", "os": runtime.GOOS, "arch": runtime.GOARCH})
}

func main() {
	selfTest := flag.Bool("self-test", false, "check the built executable")
	listen := flag.String("listen", ":8080", "HTTP listen address")
	flag.Parse()
	if *selfTest {
		if sum(20, 22) != 42 {
			os.Exit(1)
		}
		json.NewEncoder(os.Stdout).Encode(map[string]string{"status": "pass", "os": runtime.GOOS, "arch": runtime.GOARCH})
		return
	}
	fmt.Fprintln(os.Stderr, "listening", *listen)
	if err := http.ListenAndServe(*listen, http.HandlerFunc(health)); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
