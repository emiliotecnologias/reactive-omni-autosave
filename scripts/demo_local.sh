#!/usr/bin/env bash
# AutoSave Sentinel — one-command local demo (no wallet, no network secrets).
# Runs: contract build -> full-loop Foundry tests -> bot unit tests ->
#       loop simulation -> bot dry-run.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== 1/5 forge build ==="
forge build

echo
echo "=== 2/5 forge test (full Reactive Omni loop, mocked system+proxy) ==="
forge test -vv

echo
echo "=== 3/5 python bot unit tests ==="
(cd bot && python3 -m unittest test_bot)

echo
echo "=== 4/5 loop simulation ==="
python3 scripts/simulate_loop.py

echo
echo "=== 5/5 bot dry-run ==="
python3 bot/autosave_bot.py

echo
echo "Demo complete. Deployment to Lasna + Base Sepolia: see README."
