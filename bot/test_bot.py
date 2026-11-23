#!/usr/bin/env python3
"""Unit tests for the AutoSave Sentinel bot (stdlib unittest, no network)."""
import unittest

from autosave_bot import (
    AUTOSAVED_TOPIC0,
    AutoSaveEvent,
    SavingsLedger,
    TelegramNotifier,
    _keccak256,
    _topic0,
    format_alert,
    run_dry,
    simulate_events,
)


class KeccakTests(unittest.TestCase):
    def test_empty_string_vector(self):
        # Known Keccak-256("") test vector.
        self.assertEqual(
            _keccak256(b"").hex(),
            "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
        )

    def test_transfer_topic(self):
        # ERC-20 Transfer topic0 is a well-known constant.
        self.assertEqual(
            _topic0("Transfer(address,address,uint256)"),
            "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
        )

    def test_autosaved_topic_shape(self):
        self.assertTrue(AUTOSAVED_TOPIC0.startswith("0x"))
        self.assertEqual(len(AUTOSAVED_TOPIC0), 66)


class LedgerTests(unittest.TestCase):
    def test_totals(self):
        ledger = SavingsLedger()
        for ev in simulate_events():
            ledger.add(ev)
        self.assertEqual(ledger.total_saved, 40_000_000)
        report = ledger.report()
        self.assertIn("Auto-saves executed: 3", report)
        self.assertIn("40.00 mUSDC", report)


class AlertTests(unittest.TestCase):
    def test_format(self):
        ev = AutoSaveEvent("0xabc", 20_000_000, 80_000_000)
        text = format_alert(ev)
        self.assertIn("20.00 mUSDC", text)
        self.assertIn("80.00 mUSDC", text)

    def test_dry_run_sends_nothing_real(self):
        notifier = TelegramNotifier(dry_run=True)
        ledger = run_dry(notifier)
        self.assertEqual(len(notifier.sent), 3)
        self.assertEqual(ledger.total_saved, 40_000_000)


if __name__ == "__main__":
    unittest.main()
