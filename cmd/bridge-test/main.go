// bridge-test is a diagnostic tool that opens the SHM bridge and prints
// ticks, positions, and account data as they arrive from MT5.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go-trade/internal/bridge"
)

func main() {
	name := flag.String("name", "HAYALET_SHM", "shared memory name")
	tickCap := flag.Uint("ticks", 4096, "tick ring buffer capacity")
	posCap := flag.Uint("pos", 1024, "position ring buffer capacity")
	cmdCap := flag.Uint("cmd", 512, "command ring buffer capacity")
	acctCap := flag.Uint("acct", 64, "account ring buffer capacity")
	flag.Parse()

	fmt.Printf("[bridge-test] Opening SHM: %s (tick=%d pos=%d cmd=%d acct=%d)\n",
		*name, *tickCap, *posCap, *cmdCap, *acctCap)

	br, err := bridge.Open(*name, uint32(*tickCap), uint32(*posCap), uint32(*cmdCap), uint32(*acctCap))
	if err != nil {
		fmt.Printf("[bridge-test] WARNING: %v\n", err)
	}
	defer br.Close()

	fmt.Printf("[bridge-test] Bridge mode: %s\n", br.Mode())
	fmt.Println("[bridge-test] Waiting for data from MT5... (Ctrl+C to stop)")
	fmt.Println("---")

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	tickCount := 0
	posCount := 0
	acctCount := 0

	for {
		select {
		case <-sigCh:
			fmt.Printf("\n[bridge-test] Total: %d ticks, %d positions, %d accounts\n", tickCount, posCount, acctCount)
			return
		case <-ticker.C:
			ticks := br.ReadTicks(256)
			for _, t := range ticks {
				tickCount++
				fmt.Printf("TICK #%d  %s  Bid=%.5f  Ask=%.5f  Time=%s\n",
					tickCount, t.Symbol, t.Bid, t.Ask, t.Time.Format("15:04:05.000"))
			}

			positions := br.ReadPositions(256)
			for _, p := range positions {
				posCount++
				fmt.Printf("POS  #%d  %s %s  Vol=%.2f  Price=%.5f  Magic=%d  Acct=%s\n",
					p.ID, p.Symbol, p.Side, p.Volume, p.Price, p.Magic, p.AccountID)
			}

			accounts := br.ReadAccounts(16)
			for _, a := range accounts {
				acctCount++
				fmt.Printf("ACCT  %s  Bal=%.2f  Eq=%.2f  Margin=%.2f\n",
					a.AccountID, a.Balance, a.Equity, a.Margin)
			}

			br.Heartbeat(time.Now())
		}
	}
}
