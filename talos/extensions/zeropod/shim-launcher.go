package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

const root = "/var/lib/zeropod"

func main() {
	name := filepath.Join(root, "bin", "containerd-shim-zeropod-v2.real")
	path := filepath.Join(root, "bin") + ":" + os.Getenv("PATH")
	env := os.Environ()
	for i, entry := range env {
		if strings.HasPrefix(entry, "PATH=") {
			env = append(env[:i], env[i+1:]...)
			break
		}
	}
	env = append(env,
		"PATH="+path,
		"CRIU_CONFIG_FILE="+filepath.Join(root, "etc", "criu-default.conf"),
	)
	if err := syscall.Exec(name, os.Args, env); err != nil {
		fmt.Fprintln(os.Stderr, "zeropod shim exec:", err)
		os.Exit(127)
	}
}
