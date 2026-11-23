# AutoSave Sentinel — Reactive Omni Buildathon

**Track: "Set It and Forget It"** · Reactive Network (Omni) · Emilio Tecnologías

A set-and-forget savings automation: every time you deposit into the vault,
a Reactive contract automatically moves a fixed percentage to your savings
wallet — no keeper bots, no manual steps, no polling. A Python Telegram bot
tells you each time it happens and keeps a running savings report.

> Deposit 100 → 20 auto-saved, 80 stays spendable. You set the rule once.

## How it works

```
┌─────────────────────┐   DepositReceived   ┌──────────────────────┐
│  AutoSaveVault      │ ──────────────────▶ │  AutoSaveReactive    │
│  Base Sepolia       │    (origin event)   │  Lasna (Reactive)    │
│  (84532)            │                     │  react():            │
│                     │                     │   if amount ≥ min:   │
│  deposit() ──escrow │                     │   save = amt × bps   │
│                     │ ◀────────────────── │   requestCallbackV1  │
│  executeAutoSave()  │   callback via      └──────────────────────┘
│  (callback, auth'd) │   callback proxy
└─────────┬───────────┘
          │ AutoSaved / AlertRaised
          ▼
┌─────────────────────┐
│  Python Telegram    │  "AutoSave executed: 20.00 mUSDC moved…"
│  notifier + report  │  + savings/PnL ledger
└─────────────────────┘
```

1. **Origin** — `AutoSaveVault.deposit()` (Base Sepolia) credits your escrow
   and emits `DepositReceived(user, amount, newEscrow)`.
2. **Reactive** — `AutoSaveReactive` (Lasna, chain 5318007) is subscribed to
   that event via the Reactive system contract
   (`0x8888…8888`). `react()` applies the rule (default: save 20%, min
   deposit 10 mUSDC) and calls `SYSTEM.requestCallbackV_1_0(...)`.
   Below-minimum deposits are counted and skipped — `react()` never reverts
   on them (reverting reactive txs are still billed in full).
3. **Destination** — the Base Sepolia callback proxy
   (`0x476F44b11F5C942c58f4c8E3d0300E5710743585`) injects the reactive
   contract's address into the payload and calls
   `AutoSaveVault.executeAutoSave(...)`, which authenticates with **both**
   `onlyServiceProvider` and `onlyCallbackSender` (per Reactive docs),
   moves the slice to the savings wallet, and emits `AutoSaved` +
   `AlertRaised`.
4. **Off-chain** — `bot/autosave_bot.py` watches `AutoSaved` events and
   sends a Telegram alert per save, plus an aggregated savings report.

Users can withdraw their remaining escrow at any time; the owner can retune
the rule (`setRule`), pause (unsubscribes — stops billing), and rotate the
savings wallet without redeploying.

## Contracts

| Contract | Chain | Role |
|---|---|---|
| `src/AutoSaveReactive.sol` | Lasna 5318007 | Subscribes to deposits, applies rule, requests callback |
| `src/AutoSaveVault.sol` | Base Sepolia 84532 | Escrow + authenticated callback receiver |
| `src/MockUSDC.sol` | Base Sepolia 84532 | 6-decimal test stablecoin (anyone can mint) |
| `src/reactive/*.sol` | — | Minimal Reactive Omni API (see note below) |

> **Note on `src/reactive/`:** these are original, minimal re-implementations
> of the public Reactive Omni interfaces/base contracts as documented at
> <https://dev.reactive.network>, vendored so the project builds hermetically.
> For production, swap them for the official library:
> `forge install Reactive-Network/reactive-lib-omni` and update the
> `@reactive/` remapping in `foundry.toml`.

## Quick start (local, no wallet needed)

```bash
# Foundry: https://book.getfoundry.sh/getting-started/installation
./scripts/demo_local.sh        # build + 11 full-loop tests + bot tests + sim
```

Or step by step:

```bash
forge build
forge test -vv                 # origin → react → callback loop, mocked system/proxy
python3 scripts/simulate_loop.py
python3 bot/autosave_bot.py    # dry-run: prints would-be Telegram alerts
(cd bot && python3 -m unittest test_bot)
```

The Foundry suite etches a mock system contract at `0x8888…8888` and a mock
callback proxy, then proves: the 20% split end-to-end, below-minimum skips,
pause/resume subscription handling, `onlySystem` rejection of forged logs,
callback rejection for direct callers and wrong reactive senders, rule
updates, multi-deposit accumulation, and withdrawals.

## Deployment (testnets)

You need a **testnet-only** key with (a) Base Sepolia ETH and (b) Lasna REACT.
Get testnet REACT by sending Ethereum Sepolia or Base Sepolia ETH to the
Reactive faucet contracts (per Reactive docs, "Get Testnet REACT"):
Ethereum Sepolia `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`,
Base Sepolia `0x2afaFD298b23b62760711756088F75B7409f5967`.

The reactive contract subscribes to the vault address, and the vault needs
the reactive address — break the cycle in this order:

```bash
export PRIVATE_KEY=0x…            # testnet-only dev key
export SAVINGS_WALLET=0x…

# 1) Reactive on Lasna (ORIGIN_VAULT=0x0…0 = chain-wide topic subscription;
#    react() then only accepts logs from the wired vault address)
ORIGIN_VAULT=0x0000000000000000000000000000000000000000 \
  forge script script/Deploy.s.sol:DeployReactive --rpc-url lasna --broadcast
# → note REACTIVE_ADDR from the output

# 2) Token + vault on Base Sepolia
REACTIVE_ADDR=0x… forge script script/Deploy.s.sol:DeployVault \
  --rpc-url base_sepolia --broadcast
# → note TOKEN_ADDR + VAULT_ADDR

# 3) Wire destination on Lasna
REACTIVE_ADDR=0x… VAULT_ADDR=0x… \
  forge script script/Deploy.s.sol:WireDestination --rpc-url lasna --broadcast

# 4) Trigger the loop: mint + deposit 100 mUSDC
TOKEN_ADDR=0x… VAULT_ADDR=0x… \
  forge script script/Deploy.s.sol:TriggerDeposit --rpc-url base_sepolia --broadcast
```

Then collect the full-loop evidence: the deposit tx (Base Sepolia), the
reactive tx + `CallbackRequest` (Lasna / Reactscan), and the callback tx
(Base Sepolia, `AutoSaved` event). Fund the reactive contract with REACT and
the vault with Base Sepolia ETH — a contract in debt receives nothing.

Verify on Sourcify: `forge verify-contract --verifier sourcify --chain-id 5318007 <addr> AutoSaveReactive`.

## Bot (live mode)

```bash
cp bot/config.example.env .env   # fill TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, VAULT_ADDRESS
set -a; source .env; set +a
python3 bot/autosave_bot.py --live
```

Stdlib only — no pip installs. Dry-run (default) needs no configuration.

## Project layout

```
src/            contracts (+ src/reactive/ Omni API)
test/           Foundry tests + mocks (system contract, callback proxy)
script/         Deploy.s.sol — 4-step testnet deployment + trigger
bot/            Python Telegram notifier (+ unit tests, config template)
scripts/        demo_local.sh, simulate_loop.py
SUBMISSION.md   DoraHacks submission text
demo-video.mp4  <3-min demo from real terminal/test output
```

## Honest status

- ✅ Contracts compile (solc 0.8.29) and **11/11 Foundry tests pass**,
  including a full origin → react → callback → split loop against mocked
  Reactive system/proxy contracts.
- ✅ Bot unit tests pass (6/6, incl. Keccak-256 vectors); dry-run works with
  zero secrets.
- ⏳ **Testnet deployment pending the project owner's wallet decision** —
  deploy scripts are ready; no real funds were used. Deployed addresses and
  full-loop tx hashes will be added to `SUBMISSION.md` after deployment.
- `MockUSDC` is a test token with a public mint — testnet only, not real USDC.

## AI assistance disclosure

Built by Emilio Tecnologías with AI assistance (Muse): contract design,
Solidity, tests, Python bot, docs, and demo were AI-assisted and reviewed by
the owner. The Reactive Omni API usage follows the official docs at
<https://dev.reactive.network>. No third-party code was copied; the
`src/reactive/` files are original minimal implementations of the documented
public API.

## License

MIT
