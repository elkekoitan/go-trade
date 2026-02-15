// Package logging provides structured logging for the HAYALET system using zap.
package logging

import (
	"fmt"
	"os"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gopkg.in/natefinch/lumberjack.v2"
)

// Build creates a new zap.Logger with JSON output to both file and stdout.
// The log file is rotated at 50MB with 10 backups kept for 30 days.
func Build(level string) (*zap.Logger, error) {
	lvl, err := zapcore.ParseLevel(level)
	if err != nil {
		return nil, fmt.Errorf("parsing log level %q: %w", level, err)
	}

	// Ensure logs directory exists
	if err := os.MkdirAll("logs", 0o755); err != nil {
		return nil, fmt.Errorf("creating logs directory: %w", err)
	}

	// File writer with rotation
	fileWriter := &lumberjack.Logger{
		Filename:   "logs/hayalet.log",
		MaxSize:    50, // MB
		MaxBackups: 10,
		MaxAge:     30, // days
		Compress:   true,
	}

	encoderCfg := zap.NewProductionEncoderConfig()
	encoderCfg.TimeKey = "ts"
	encoderCfg.EncodeTime = zapcore.ISO8601TimeEncoder

	core := zapcore.NewTee(
		zapcore.NewCore(
			zapcore.NewJSONEncoder(encoderCfg),
			zapcore.AddSync(fileWriter),
			lvl,
		),
		zapcore.NewCore(
			zapcore.NewJSONEncoder(encoderCfg),
			zapcore.AddSync(os.Stdout),
			lvl,
		),
	)

	logger := zap.New(core, zap.AddCaller(), zap.AddStacktrace(zapcore.ErrorLevel))
	return logger, nil
}
