#!/usr/bin/env python3
"""AutoSave Sentinel — local full-loop simulation (no chain, no secrets).

Walks the exact Reactive Omni loop with the same numbers as the Foundry
test `test_FullLoop_DepositSplitsTwentyPercent`:

  1. ORIGIN    user deposits 100 mUSDC -> AutoSaveVault emits DepositReceived
  2. REACTIVE  AutoSaveReactive.react() on Lasna: 100 >= min 10,
               save = 100 * 2000bps / 10000 = 20 mUSDC
  3. CALLBACK  SYSTEM.requestCallbackV_1_0 -> Base Sepolia callback proxy
               injects the reactive address, calls executeAutoSave
  4. VAULT     20 mUSDC escrow -> savings wallet; AutoSaved + AlertRaised
  5. BOT       Python notifier turns AlertRaised into a Telegram message

This mirrors `forge test` (which proves the same flow against the real
Solidity bytecode with mock system/proxy contracts).
"""
import sys
import time

sys.path.insert(0, "bot")
from autosave_bot import AutoSaveEvent, SavingsLedger, TelegramNotifier, format_alert  # noqa: E402

USER = "0x0000000000000000000000000000000000000B0B"
SAVE_BPS = 2000
MIN_AMOUNT = 10_000_000
DECIMALS = 6


def fmt(units: int) -> str:
    return f"{units / 10 ** DECIMALS:,.2f} mUSDC"


def main() -> None:
    print("=" * 68)
    print("AutoSave Sentinel — Reactive Omni full-loop simulation")
    print("Track: Set It and Forget It | Origin/Dest: Base Sepolia (84532)")
    print("Reactive: Lasna testnet (5318007) | Rule: save 20%, min 10 mUSDC")
    print("=" * 68)

    deposit = 100_000_000  # 100 mUSDC
    print(f"\n[1] ORIGIN — Base Sepolia")
    print(f"    user {USER[:12]}… deposits {fmt(deposit)} into AutoSaveVault")
    print(f"    -> DepositReceived(user, {fmt(deposit)}, escrow={fmt(deposit)})")
    time.sleep(0.4)

    print(f"\n[2] REACTIVE — Lasna (5318007), system contract calls react()")
    save = deposit * SAVE_BPS // 10_000
    print(f"    deposit {fmt(deposit)} >= min {fmt(MIN_AMOUNT)}  OK")
    print(f"    save = {fmt(deposit)} x {SAVE_BPS}bps / 10000 = {fmt(save)}")
    print(f"    -> SYSTEM.requestCallbackV_1_0(chainId=84532, vault, 1_000_000 gas)")
    time.sleep(0.4)

    print(f"\n[3] CALLBACK — Base Sepolia callback proxy")
    print(f"    proxy injects reactive address into payload[0], calls")
    print(f"    executeAutoSave(reactive, user, {fmt(save)}, originTx)")
    print(f"    onlyServiceProvider OK | onlyCallbackSender OK")
    time.sleep(0.4)

    print(f"\n[4] VAULT — savings slice moved, no keeper involved")
    print(f"    escrow: {fmt(deposit)} -> {fmt(deposit - save)}")
    print(f"    savings wallet: +{fmt(save)}")
    print(f"    -> AutoSaved + AlertRaised events emitted")
    time.sleep(0.4)

    print(f"\n[5] BOT — Python Telegram notifier (dry-run)")
    ev = AutoSaveEvent(USER, save, deposit - save, "0x7a11", 12345)
    notifier = TelegramNotifier(dry_run=True)
    notifier.send(format_alert(ev))
    ledger = SavingsLedger()
    ledger.add(ev)
    print(ledger.report())

    print("\nLoop complete: deposit -> react -> callback -> split -> alert.")
    print("On-chain proof of the same flow: `forge test` (11 tests).")


if __name__ == "__main__":
    main()
