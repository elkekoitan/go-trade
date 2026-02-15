// Package main is the entry point for the HAYALET trading daemon.
package main

import (
	"flag"
	"fmt"
	"os"

	"go-trade/internal/app"
	"go-trade/internal/config"
)

func main() {
	configPath := flag.String("config", "config/config.yaml", "path to configuration file")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load config: %v\n", err)
		os.Exit(1)
	}

	a := app.New(cfg)
	if err := a.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "fatal: %v\n", err)
		os.Exit(1)
	}
}
