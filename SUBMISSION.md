# DoraHacks Submission — Reactive Omni Buildathon

> Copy-paste source for the DoraHacks form. Fields marked **PENDING** are
> filled after the owner-approved testnet deployment (see README §Deployment).

## Project name

AutoSave Sentinel

## Track

Set It and Forget It

## One-liner

Deposit money, and a Reactive contract automatically saves a fixed percentage
for you — no keeper, no polling, no manual steps — with a Telegram alert every
time it happens.

## Description

AutoSave Sentinel is a set-and-forget savings automation built on Reactive
Network (Omni).

**The problem:** saving a slice of every incoming payment is exactly the kind
of small, repetitive rule people set once and then forget to follow. Keeper
bots and cron jobs break, cost gas to poll, and need someone to run them.

**The solution:** an on-chain rule that runs itself.

1. A user deposits test stablecoins into `AutoSaveVault` on Base Sepolia. The
   vault credits a per-user escrow and emits `DepositReceived`.
2. `AutoSaveReactive`, deployed on Reactive Lasna, is subscribed to that event
   through the Reactive system contract. Its `react()` checks the rule
   (default: deposits ≥ 10 mUSDC save 20%) and requests a callback with
   `SYSTEM.requestCallbackV_1_0`.
3. The Base Sepolia callback proxy delivers the callback to
   `AutoSaveVault.executeAutoSave`, which authenticates the caller with both
   `onlyServiceProvider` and `onlyCallbackSender`, moves the savings slice to
   the user's savings wallet, and emits `AutoSaved` + `AlertRaised`.
4. A Python Telegram bot watches `AutoSaved` events, sends an instant alert
   ("AutoSave executed: 20.00 mUSDC moved…"), and maintains a savings report.

Users can withdraw their remaining escrow at any time. The owner can retune
the percentage/minimum, pause (unsubscribes, stops billing), or rotate the
savings wallet without redeploying. Below-minimum deposits are counted and
skipped without reverting `react()`.

**Why Reactive:** the whole point of the product is "set it and forget it" —
the contract itself decides when to act based on origin-chain events. There
is no off-chain trigger to keep alive; the Python bot is only a notifier.

## How it uses Reactive Network

- Reactive contract (`AbstractReactive`, `onlySystem` `react()`) subscribed
  via `SYSTEM.subscribe` to `DepositReceived` on Base Sepolia (84532).
- Cross-chain callback via `SYSTEM.requestCallbackV_1_0` to the destination
  vault; destination authenticates via callback proxy + injected sender
  (`AbstractCallback` pattern from the official docs).
- Pause/resume uses `subscribe`/`unsubscribe` + `_coverDebt()` per docs.
- Chains: origin/destination Base Sepolia (84532), reactive on Lasna (5318007).

## Links

- Repository: https://github.com/emiliotecnologias/reactive-omni-autosave
- Demo video (<3 min, real terminal/test output): `demo-video.mp4` in repo

## Deployed addresses (testnet)

- AutoSaveReactive (Lasna 5318007): **PENDING OWNER DEPLOYMENT**
- AutoSaveVault (Base Sepolia 84532): **PENDING OWNER DEPLOYMENT**
- MockUSDC (Base Sepolia 84532): **PENDING OWNER DEPLOYMENT**

## Full-loop transaction hashes

- Origin deposit tx (Base Sepolia): **PENDING**
- Reactive tx / CallbackRequest (Lasna): **PENDING**
- Callback tx with AutoSaved event (Base Sepolia): **PENDING**

> Local proof available today: `forge test` runs the identical loop against
> mocked system/proxy contracts (11 tests), and `scripts/simulate_loop.py`
> walks the same numbers. Deployment requires a testnet wallet, which the
> project owner controls; scripts are in `script/Deploy.s.sol`.

## Tech stack

Solidity 0.8.29 · Foundry · Reactive Omni (Lasna) · Base Sepolia ·
Python 3 (stdlib only) · Telegram Bot API

## Team

Emilio Tecnologías (solo builder, Miami) — Python/automation background;
first Reactive contracts built for this buildathon.

## AI assistance disclosure

Built with AI assistance (Muse): design, Solidity, tests, Python bot,
documentation and demo video were AI-assisted and owner-reviewed. Reactive
Omni API usage follows https://dev.reactive.network. The `src/reactive/`
files are original minimal implementations of the documented public API
(production should use `Reactive-Network/reactive-lib-omni`).

## What we'd do next

- Per-user rules (each depositor picks their own % and savings wallet).
- Watch real ERC-20 `Transfer` events to a watched wallet, not just vault
  deposits.
- Weekly Telegram digest + goal tracking ("you're 40% to your $500 goal").
