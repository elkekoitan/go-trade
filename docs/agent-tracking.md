# HAYALET Agent Tracking Document

**Son Guncelleme / Last Updated**: 2026-02-15
**Proje Fazı / Project Phase**: Phase 0 - Bootstrap

---

## 1. ARCHITECT AGENT

**Sorumluluk**: Sistem tasarimi, arayuz sozlesmeleri, CLAUDE.md, proje yapisi
**Sahip Dosyalar**: `docs/`, `CLAUDE.md`, `internal/model/`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| TAMAM | Proje yapisini olustur | 2026-02-15 | Dizin yapisi, CLAUDE.md |
| TAMAM | Agent sistemi tasarimi | 2026-02-15 | docs/agent-tracking.md |
| TAMAM | Mimari dokuman | 2026-02-15 | docs/architecture.md |
| ACIK | Arayuz sozlesmeleri (model/types.go) | - | - |

**Sonraki Gorevler**:
- internal/model/ arayuz tanimlari
- Modul bagimliliklari haritasi

---

## 2. TRADING ENGINE AGENT

**Sorumluluk**: Grid, cascade, lot modelleri, skor sistemi, smartclose
**Sahip Dosyalar**: `internal/engine/`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| ACIK | Grid engine (3 spacing, 4 lot model) | - | - |
| ACIK | Cascade R1-R6 + K2-K6 TP | - | - |
| ACIK | Composite scoring (EA'dan port) | - | - |
| ACIK | SmartClose algoritmasi | - | - |
| ACIK | Preset yonetimi | - | - |

**Sonraki Gorevler**:
- Phase 2'de tam implementasyon
- EA analiz dokumani referans alinacak

---

## 3. BRIDGE AGENT

**Sorumluluk**: C++ DLL, shared memory, ring buffer, heartbeat
**Sahip Dosyalar**: `native/shm/`, `internal/bridge/`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| ACIK | SHM layout tanimlari | - | - |
| ACIK | Windows SHM implementasyonu | - | - |
| ACIK | Bridge soyutlama (SHM/Pipe/TCP) | - | - |
| ACIK | C++ DLL yazimi | - | - |
| ACIK | TCP fallback | - | - |

**Sonraki Gorevler**:
- Phase 1'de tam implementasyon
- MT5 TickMill hesap bilgileri bekleniyor

---

## 4. EA AGENT

**Sorumluluk**: MQL4/MQL5 Expert Advisor gelistirme, DLL entegrasyonu
**Sahip Dosyalar**: `ea/mt4/`, `ea/mt5/`, `ea/reference/`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| TAMAM | Referans EA'lari analiz et | 2026-02-15 | docs/ea-analysis.md |
| ACIK | MT5 bridge EA yaz | - | - |
| ACIK | MT4 bridge EA yaz | - | - |
| ACIK | Komut parser + OrderSend | - | - |

**Sonraki Gorevler**:
- Phase 1'de bridge EA yazimi
- Magic number aralik kontrolu

---

## 5. API AGENT

**Sorumluluk**: REST API, WebSocket streaming, gRPC, JWT auth
**Sahip Dosyalar**: `internal/api/`, `internal/grpcserver/`, `proto/`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| ACIK | REST endpoint'ler | - | - |
| ACIK | WebSocket hub + streaming | - | - |
| ACIK | JWT authentication | - | - |
| ACIK | Rate limiting + CORS | - | - |
| ACIK | gRPC servisleri | - | - |

**Sonraki Gorevler**:
- Phase 4'te tam implementasyon
- Dashboard icin API oncelikli

---

## 6. DASHBOARD AGENT

**Sorumluluk**: Web UI, gercek zamanli gorsellestirme, kullanici yonetimi
**Sahip Dosyalar**: `web/`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| ACIK | Next.js proje kurulumu | - | - |
| ACIK | i18n (TR + EN) | - | - |
| ACIK | Auth akisi | - | - |
| ACIK | Overview dashboard | - | - |
| ACIK | Pozisyon sayfasi | - | - |
| ACIK | Grid gorsellestirici | - | - |
| ACIK | Risk yonetim paneli | - | - |
| ACIK | Override kontrolleri | - | - |

**Sonraki Gorevler**:
- Phase 5'te tam implementasyon
- API hazir olduktan sonra baslanacak

---

## 7. RISK AGENT

**Sorumluluk**: Balance Guard, circuit breaker, drawdown izleme, hedge
**Sahip Dosyalar**: `internal/engine/risk.go`, `circuit.go`, `hedge.go`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| ACIK | Balance Guard 5 seviye | - | - |
| ACIK | Circuit breaker | - | - |
| ACIK | Hedge engine (tam/kismi/gecikmeli) | - | - |
| ACIK | Smart close | - | - |
| ACIK | Override sistemi | - | - |

**Sonraki Gorevler**:
- Phase 3'te tam implementasyon

---

## 8. TEST AGENT

**Sorumluluk**: Unit test, entegrasyon testi, backtest dogrulama
**Sahip Dosyalar**: `*_test.go`, `test/`, `internal/backtest/`

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| ACIK | Engine unit testleri | - | - |
| ACIK | Bridge entegrasyon testleri | - | - |
| ACIK | API endpoint testleri | - | - |
| ACIK | Backtest motoru | - | - |

**Sonraki Gorevler**:
- Her fazda ilgili testler yazilacak
- Phase 8'de backtest tam implementasyon

---

## 9. DEVOPS AGENT

**Sorumluluk**: Build sistemi, deploy, CI/CD, izleme
**Sahip Dosyalar**: `Makefile`, `scripts/`, Docker configs

| Durum | Gorev | Tarih | Kanit |
|-------|-------|-------|-------|
| ACIK | Makefile olustur | - | - |
| ACIK | DLL build scripti | - | - |
| ACIK | EA deploy scripti | - | - |
| ACIK | Dev ortam scripti | - | - |

**Sonraki Gorevler**:
- Build automation
- Deployment scripts

---

## Faz Ozeti / Phase Summary

| Faz | Aktif Ajanlar | Durum |
|-----|--------------|-------|
| Phase 0: Bootstrap | Architect | DEVAM EDIYOR |
| Phase 1: Bridge | Bridge, EA | BEKLIYOR |
| Phase 2: Trading Engine | Trading Engine | BEKLIYOR |
| Phase 3: Risk & Hedge | Risk | BEKLIYOR |
| Phase 4: API | API | BEKLIYOR |
| Phase 5: Dashboard | Dashboard | BEKLIYOR |
| Phase 6: Multi-Account | Trading Engine, Dashboard | BEKLIYOR |
| Phase 7: Stealth & Signals | Trading Engine | BEKLIYOR |
| Phase 8: Backtest | Test | BEKLIYOR |
| Phase 9: Hardening | DevOps, Test | BEKLIYOR |
| Phase 10: Launch | Tumu | BEKLIYOR |
