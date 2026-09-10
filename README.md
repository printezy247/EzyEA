<div align="center">
  <img src="docs/diagrams/hero.svg" alt="EzyEA Hero - Gold Trading EA" width="240"/>
  <h1>📈 EzyEA</h1>
  <p><strong>Multi-version MetaTrader 5 Expert Advisors for XAUUSD & BTCUSD.</strong></p>
  <p>7+ EA versions (V1–V4 + variants), Zone Quality pipeline, session volume logic, fixed-exit risk management, and optimized .set files — built for prop-firm challenges and live trading.</p>
</div>

<img src="docs/diagrams/wave-separator.svg" alt="Wave separator" width="100%"/>

<div align="center">
  
[![MetaTrader 5](https://img.shields.io/badge/MetaTrader%205-EA-0067A5?style=for-the-badge&logo=metatrader&logoColor=white)](https://www.metatrader5.com)
[![MQ5](https://img.shields.io/badge/Language-MQ5-FF8C00?style=for-the-badge)](https://www.mql5.com)
[![Symbols](https://img.shields.io/badge/Symbols-XAUUSD%20%7C%20BTCUSD-FFD700?style=for-the-badge&logo=bitcoin&logoColor=black)](https://www.tradingview.com/symbols/XAUUSD/)
[![Prop Firm](https://img.shields.io/badge/Prop%20Firm-Ready-00FFA3?style=for-the-badge)](https://github.com/printezy247/EzyEA)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/printezy247/EzyEA?style=for-the-badge&logo=github&logoColor=white)](https://github.com/printezy247/EzyEA/stargazers)

</div>

---

## ⚡ The Promise

<div align="center">
  <img src="docs/diagrams/promise.svg" alt="The Promise - Multi-Version EA, XAUUSD/BTCUSD, Prop-Firm Ready" width="100%"/>
</div>

---

## 📦 EA Version Timeline

<div align="center">
  <img src="docs/diagrams/versions.svg" alt="EA Versions - V1 Foundation, V2 Zone Quality, V2.1b Precision, V2.2 BTCUSD, V3 Fresh Series, V4 & EzyScalp" width="100%"/>
</div>

---

## 🗂️ Repository Structure

```
EzyEA/
├── EzyEA_V1_XAUUSD.mq5              # V1 Foundation
├── EzyEA_V1.1_XAUUSD.mq5            # V1.1 refinement
├── EzyEA_V2_XAUUSD.mq5              # V2 base
├── EzyEA_V2.1_XAUUSD.mq5            # V2.1
├── EzyEA_V2.1_XAUUSD.mq5            # V2.1 (alt)
├── EzyEA_V3_XAUUSD.mq5              # V3 base
├── EzyEA_V3.2_XAUUSD.mq5            # V3.2
├── EzyEA_V3b_XAUUSD.mq5             # V3b variant
├── EzyEA_V3_BTCUSD.mq5              # V3 BTCUSD
├── EzyEA_V4_XAUUSD.mq5              # V4 advanced
├── EzyScalp_XAUUSD_FRESH_V1.mq5     # Scalper V1
├── EzyScalp_XAUUSD_FRESH_V2.mq5     # Scalper V2
├── EzyMap_V2_0_ZONE_QUALITY.mq5     # Zone Quality indicator
├── EzyMap_V2_1a_SESSION_VOL.mq5     # Session Volume indicator
├── EzyMap_V2_1b_FIXEDEXIT_TEST.mq5  # Fixed exit test
├── EzyMap_V2_1b_TRIGGER_REFINED.mq5 # Trigger refined
├── EzyMap_V2_2_BTCUSD_ADAPTATION.mq5# BTCUSD adaptation
├── EzyMap_V2_2_BTCUSD_FIXEDEXIT_TEST.mq5
├── EzyMap_V3_116_FRESH_V3_1_BTCUSD.mq5
├── EzyMap_V3_116_FRESH_V3_1_XAUUSDsc.mq5
├── EzyMap_V3_116_FRESH_V3_3_XAUUSDsc.mq5
├── EzyMap_V3_116_FRESH_V3_BTCUSD.mq5
├── EzyMap_V3_116_FRESH_V3_XAUUSDsc.mq5
├── EzyMap_V3_126_FRESH_V4_1_XAUUSDsc.mq5
├── EzyMap_V3_126_FRESH_V4_BTCUSD.mq5
├── EzyMap_V3_126_FRESH_V4_XAUUSDsc.mq5
├── EzyMap_V3_140_FRESH_V2_XAUUSDsc.mq5
├── EzyMap_V3_176_V3_175_BASE_SYNCHRONIZED_LIVE_EXIT_SL21_TRAIL7.mq5
├── EzyMap_V3_184_V3_182_BASE_EVERY_ZERO_CONF_LEVEL_NO_ENTRY_GOVERNORS_SL24_TRAIL13.mq5
├── EzyMap_V3_190_REFINED.mq5
├── EzyMap_V5_XAUUSD_SND_SCALPER.mq5
├── *.set                            # Optimized parameter files per version
├── V2_0_CHANGES.md                  # Version changelogs
├── V2_1a_CHANGES.md
├── V2_1b_CHANGES.md
├── V2_2_BTCUSD_CHANGES.md
├── V3_190_CHANGES.md
├── README.md
└── .gitignore
```

---

## 🎯 Core Architecture

<div align="center">
  <img src="docs/diagrams/architecture.svg" alt="EA Architecture - Signal Engine, Entry Logic, Risk Management, Position Sizing, Execution" width="100%"/>
</div>

### Pipeline Stages (V2 Zone Quality)

| Stage | Component | Purpose |
|---|---|---|
| **Stage 0** | Baseline | Raw signal generation |
| **Stage 1** | Session Filter | London/NY/Asian session logic |
| **Stage 2** | Session Volume | Volume confirmation per session |
| **Stage 3** | Zone Quality | High-probability zone filtering |
| **Stage 4** | Trigger Refined | Precise entry timing |
| **Stage 5** | Fixed Exit | TP/SL + trailing logic |

---

## 🛡️ Risk Management Features

- **Fixed Exit Logic** — Pre-defined TP/SL on every trade (no guesswork)
- **Trailing Stop** — Configurable (7–24 pts) with step trailing
- **Drawdown Guardian** — Daily/weekly max drawdown limits
- **Governor Filters** — Confidence thresholds, zero-conf-level blocking
- **Spread/Slippage Control** — Execution quality filters
- **Max Concurrent Trades** — Position sizing with risk % per trade

---

## 📊 Symbol Coverage

| Symbol | Versions | Notes |
|---|---|---|
| **XAUUSD** (Gold) | V1, V1.1, V2, V2.1, V3, V3.2, V3b, V4, V3.116, V3.126, V3.140, V3.176, V3.184, V3.190 | Primary focus |
| **BTCUSD** | V3, V2.2, V3.116, V3.126 | Crypto adaptation |
| **XAUUSDsc** | V3.116, V3.126, V3.140 | Scaled/swap-free variants |

---

## ⚙️ Optimized .set Files

Each EA version includes tuned `.set` files for different strategies:

- **STAGE0_BASELINE** — Default baseline parameters
- **STAGE1** — Session filter enabled
- **STAGE2_SESSION_VOL** — Volume confirmation
- **STAGE3** — Zone quality active
- **STAGE4** — Trigger refinement
- **STAGE5** — Fixed exit + trailing
- **FULL** — All stages combined
- **RECOMMENDED** — Best overall config
- **DIAGNOSTIC** — Debug/analysis configs

> Load the appropriate `.set` in MT5 Strategy Tester or live chart → Expert Advisor properties → Inputs → Load.

---

## 🧪 Testing & Validation

```bash
# 1. Open MetaEditor 5
# 2. Compile any .mq5 file (F7)
# 3. Open Strategy Tester (Ctrl+R)
# 4. Select EA, symbol (XAUUSD/BTCUSD), timeframe (M5/M15/H1)
# 4. Load corresponding .set file
# 5. Run backtest / optimization
```

**Recommended test setup:**
- **Timeframe**: M5 or M15
- **Period**: 2023-2024 (including high-volatility events)
- **Spread**: Raw/ECN typical (20-50 pts for XAUUSD)
- **Deposit**: $10,000 (prop-firm standard)
- **Risk**: 1-2% per trade

---

## 📈 Key Metrics to Monitor

| Metric | Target | Notes |
|---|---|---|
| **Profit Factor** | > 1.5 | Higher = more robust |
| **Max Drawdown** | < 10% | Prop-firm limit typically 5-10% |
| **Win Rate** | 45-55% | With RR > 1.5 |
| **Recovery Factor** | > 3.0 | Profit / Max DD |
| **Sharpe Ratio** | > 1.0 | Risk-adjusted returns |

---

## 🚀 Quick Start

1. **Clone**: `git clone https://github.com/printezy247/EzyEA.git`
2. **Copy** desired `.mq5` + `.set` files to `MQL5/Experts/`
3. **Copy** indicator `.mq5` files to `MQL5/Indicators/EzyMap/`
4. **Compile** in MetaEditor (F7)
5. **Backtest** in Strategy Tester with matching `.set`
6. **Deploy** to demo → live / prop-firm challenge

---

## 📝 Version Highlights

| Version | Key Innovation |
|---|---|
| **V1** | Core trend-following logic for Gold |
| **V2** | 5-stage Zone Quality pipeline + Session Volume |
| **V2.1b** | Fixed Exit test + Trigger refinement |
| **V2.2** | BTCUSD adaptation with diagnostic passes |
| **V3 Fresh** | Synchronized base, governors, trail SL (21/7, 24/13) |
| **V3.190** | Every zero-conf-level blocked, refined governors |
| **V4** | Advanced unified logic |
| **EzyScalp** | High-frequency SND scalper for Gold |

---

## 📚 Documentation

- `V2_0_CHANGES.md` — Zone Quality pipeline introduction
- `V2_1a_CHANGES.md` — Session Volume logic
- `V2_1b_CHANGES.md` — Fixed Exit + Trigger Refined
- `V2_2_BTCUSD_CHANGES.md` — Crypto adaptation details
- `V3_190_CHANGES.md` — Governor/Confidence system
- `EzyScalp_XAUUSD_FRESH_V1/V2_README.md` — Scalper docs

---

## ⚠️ Disclaimer

**Educational & research purposes only. Not financial advice.**

- Past performance ≠ future results
- Test thoroughly on demo before live
- Prop-firm rules vary — verify compliance
- High leverage = high risk
- Author not liable for trading losses

---

## 🤝 Contributing

1. Fork the repo
2. Create feature branch: `git checkout -b feat/new-ea-version`
3. Add `.mq5` + `.set` + `CHANGES.md`
4. Commit: `git commit -m 'Add V5: description'`
5. Push & open Pull Request

---

## 📄 License

MIT License — free for personal and commercial use.

---

<div align="center">
  <img src="docs/assets/footer.svg" alt="printezy · EzyEA" width="400"/>
  <br><br>
  <sub>Multi-version MT5 EAs for Gold & Bitcoin. Built for prop-firm challenges.</sub>
</div>