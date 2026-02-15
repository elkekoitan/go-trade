// Package main is the entry point for the HAYALET trading daemon.
package main

import (
	"flag"
	"fmt"
	"os"

	"go-trade/internal/config"
	"go-trade/internal/logging"
)

func main() {
	configPath := flag.String("config", "config/config.yaml", "path to configuration file")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load config: %v\n", err)
		os.Exit(1)
	}

	log, err := logging.Build(cfg.App.LogLevel)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to initialize logger: %v\n", err)
		os.Exit(1)
	}
	defer log.Sync()

	log.Info("HAYALET trading daemon starting",
		// zap.String("env", cfg.App.Env),
		// zap.String("apiAddress", cfg.API.ListenAddress),
	)

	// TODO: Initialize bridge, engine, API server, and run main loop
	// This will be implemented in Phase 1-4
	fmt.Println("HAYALET daemon v0.1.0 - skeleton ready")
	fmt.Printf("Config loaded: env=%s, api=%s\n", cfg.App.Env, cfg.API.ListenAddress)
}
