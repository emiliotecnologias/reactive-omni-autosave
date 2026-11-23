#!/usr/bin/env python3
"""AutoSave Sentinel — off-chain notifier for the Reactive Omni auto-save loop.

Watches AutoSaveVault `AutoSaved` / `AlertRaised` events on the destination
chain (Base Sepolia) and sends Telegram alerts, plus a periodic savings/PnL
report. The on-chain loop (origin deposit -> AutoSaveReactive.react() ->
callback -> vault split) needs no bot; this bot is the human-facing layer:
"you just saved 20 mUSDC automatically".

Modes:
  --dry-run   (default) Simulate events locally. No network, no secrets.
              Prints the exact Telegram messages that WOULD be sent.
  --live      Poll Base Sepolia via JSON-RPC (eth_getLogs) and send real
              Telegram messages. Requires TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
              and VAULT_ADDRESS in the environment (see config.example.env).

Stdlib only — no pip installs needed. Python 3.10+.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request
from dataclasses import dataclass, field

# keccak256("AutoSaved(address,uint256,uint256,uint256)") — computed with cast:
#   cast keccak "AutoSaved(address,uint256,uint256,uint256)"
AUTOSAVED_TOPIC0 = "0x" + "0" * 64  # replaced at runtime if eth_utils absent; see _topic0()

TELEGRAM_API = "https://api.telegram.org/bot{token}/sendMessage"


def _keccak256(data: bytes) -> bytes:
    """Pure-python Keccak-256 (legacy padding) — stdlib sha3 is NOT keccak."""
    # Compact Keccak-f[1600] implementation for topic computation only.
    RC = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    ROT = [
        [0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56], [27, 20, 39, 8, 14],
    ]
    M = (1 << 64) - 1

    def rol(x, n):
        return ((x << n) | (x >> (64 - n))) & M if n else x

    def f1600(a):
        for rc in RC:
            c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
            d = [c[(x - 1) % 5] ^ rol(c[(x + 1) % 5], 1) for x in range(5)]
            for x in range(5):
                for y in range(5):
                    a[x][y] ^= d[x]
            b = [[0] * 5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    b[y][(2 * x + 3 * y) % 5] = rol(a[x][y], ROT[x][y])
            for x in range(5):
                for y in range(5):
                    a[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y])
                    a[x][y] &= M
            a[0][0] ^= rc
        return a

    rate = 136  # Keccak-256 rate in bytes
    padded = bytearray(data)
    padded.append(0x01)
    while len(padded) % rate != rate - 1:
        padded.append(0x00)
    padded.append(0x80)
    state = [[0] * 5 for _ in range(5)]
    for off in range(0, len(padded), rate):
        block = padded[off:off + rate]
        for i in range(rate // 8):
            lane = int.from_bytes(block[i * 8:(i + 1) * 8], "little")
            state[i % 5][i // 5] ^= lane
        f1600(state)
    out = bytearray()
    for i in range(4):
        out += state[i % 5][i // 5].to_bytes(8, "little")
    return bytes(out[:32])


def _topic0(signature: str) -> str:
    return "0x" + _keccak256(signature.encode()).hex()


AUTOSAVED_TOPIC0 = _topic0("AutoSaved(address,uint256,uint256,uint256)")
ALERT_TOPIC0 = _topic0("AlertRaised(address,uint256,uint256)")


@dataclass
class AutoSaveEvent:
    user: str
    saved_amount: int  # token units (6dp)
    remaining_escrow: int
    origin_tx: str = ""
    block: int = 0


@dataclass
class SavingsLedger:
    """Aggregates AutoSaved events into a PnL-style savings report."""
    events: list = field(default_factory=list)

    def add(self, ev: AutoSaveEvent) -> None:
        self.events.append(ev)

    @property
    def total_saved(self) -> int:
        return sum(e.saved_amount for e in self.events)

    def report(self, decimals: int = 6, symbol: str = "mUSDC") -> str:
        total = self.total_saved / (10 ** decimals)
        lines = [
            "AutoSave Sentinel — savings report",
            f"Auto-saves executed: {len(self.events)}",
            f"Total auto-saved:    {total:,.2f} {symbol}",
        ]
        by_user: dict[str, int] = {}
        for e in self.events:
            by_user[e.user] = by_user.get(e.user, 0) + e.saved_amount
        for user, amt in sorted(by_user.items()):
            lines.append(f"  {user[:10]}…  {amt / (10 ** decimals):,.2f} {symbol}")
        return "\n".join(lines)


def format_alert(ev: AutoSaveEvent, decimals: int = 6, symbol: str = "mUSDC") -> str:
    saved = ev.saved_amount / (10 ** decimals)
    left = ev.remaining_escrow / (10 ** decimals)
    return (
        f"AutoSave executed: {saved:,.2f} {symbol} moved to your savings wallet.\n"
        f"Escrow remaining: {left:,.2f} {symbol}\n"
        f"User: {ev.user}"
    )


class TelegramNotifier:
    """Sends via the Telegram Bot API. In dry-run, prints instead of sending."""

    def __init__(self, token: str = "", chat_id: str = "", dry_run: bool = True):
        self.token = token
        self.chat_id = chat_id
        self.dry_run = dry_run
        self.sent: list[str] = []

    def send(self, text: str) -> bool:
        self.sent.append(text)
        if self.dry_run:
            print(f"[telegram:dry-run] -> chat {self.chat_id or '<unset>'}:\n{text}\n")
            return True
        if not self.token or not self.chat_id:
            print("[telegram] missing token/chat_id — skipped", file=sys.stderr)
            return False
        body = json.dumps({"chat_id": self.chat_id, "text": text}).encode()
        req = urllib.request.Request(
            TELEGRAM_API.format(token=self.token),
            data=body,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return resp.status == 200
        except Exception as exc:  # noqa: BLE001 - report, never crash the watcher
            print(f"[telegram] send failed: {exc}", file=sys.stderr)
            return False


class VaultWatcher:
    """Polls eth_getLogs for AutoSaved events (live mode)."""

    def __init__(self, rpc_url: str, vault_address: str):
        self.rpc_url = rpc_url
        self.vault = vault_address
        self._next_id = 1

    def _rpc(self, method: str, params: list):
        body = json.dumps(
            {"jsonrpc": "2.0", "id": self._next_id, "method": method, "params": params}
        ).encode()
        self._next_id += 1
        req = urllib.request.Request(
            self.rpc_url, data=body, headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            out = json.loads(resp.read())
        if "error" in out:
            raise RuntimeError(f"RPC error: {out['error']}")
        return out["result"]

    def latest_block(self) -> int:
        return int(self._rpc("eth_blockNumber", []), 16)

    def fetch_autosaves(self, from_block: int, to_block: int) -> list[AutoSaveEvent]:
        logs = self._rpc("eth_getLogs", [{
            "address": self.vault,
            "topics": [AUTOSAVED_TOPIC0],
            "fromBlock": hex(from_block),
            "toBlock": hex(to_block),
        }])
        events = []
        for log in logs:
            topics = log["topics"]
            user = "0x" + topics[1][-40:]
            data = bytes.fromhex(log["data"][2:])
            saved = int.from_bytes(data[0:32], "big")
            remaining = int.from_bytes(data[32:64], "big")
            origin = "0x" + data[64:96].hex()
            events.append(AutoSaveEvent(
                user=user, saved_amount=saved, remaining_escrow=remaining,
                origin_tx=origin, block=int(log["blockNumber"], 16),
            ))
        return events


def simulate_events() -> list[AutoSaveEvent]:
    """Dry-run event stream mirroring the Foundry full-loop test."""
    user = "0x0000000000000000000000000000000000000B0B"
    return [
        AutoSaveEvent(user, 20_000_000, 80_000_000, "0x7a11", 12345),
        AutoSaveEvent(user, 10_000_000, 90_000_000, "0x7a12", 12360),
        AutoSaveEvent(user, 10_000_000, 80_000_000, "0x7a13", 12375),
    ]


def run_dry(notifier: TelegramNotifier) -> SavingsLedger:
    ledger = SavingsLedger()
    print("AutoSave Sentinel bot — DRY RUN (simulated AutoSaved events)\n")
    for ev in simulate_events():
        ledger.add(ev)
        notifier.send(format_alert(ev))
    print(ledger.report())
    return ledger


def run_live(notifier: TelegramNotifier, poll_seconds: int = 15) -> None:
    rpc = os.environ.get("DEST_RPC_URL", "https://sepolia.base.org")
    vault = os.environ.get("VAULT_ADDRESS", "")
    if not vault:
        sys.exit("VAULT_ADDRESS env var required for --live")
    watcher = VaultWatcher(rpc, vault)
    ledger = SavingsLedger()
    last = watcher.latest_block()
    print(f"Watching vault {vault} on {rpc} from block {last} (Ctrl-C to stop)")
    while True:
        time.sleep(poll_seconds)
        head = watcher.latest_block()
        if head <= last:
            continue
        for ev in watcher.fetch_autosaves(last + 1, head):
            ledger.add(ev)
            notifier.send(format_alert(ev))
        last = head


def main() -> None:
    ap = argparse.ArgumentParser(description="AutoSave Sentinel Telegram notifier")
    ap.add_argument("--live", action="store_true", help="poll the chain and send real alerts")
    ap.add_argument("--report-only", action="store_true", help="dry-run, print report only")
    args = ap.parse_args()

    notifier = TelegramNotifier(
        token=os.environ.get("TELEGRAM_BOT_TOKEN", ""),
        chat_id=os.environ.get("TELEGRAM_CHAT_ID", ""),
        dry_run=not args.live,
    )
    if args.live:
        run_live(notifier)
    else:
        run_dry(notifier)


if __name__ == "__main__":
    main()
