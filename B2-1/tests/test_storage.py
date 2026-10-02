"""Storage tests for ordering, streaming, and replacement safety."""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from budget_app.errors import AppError
from budget_app.models import Transaction, TransactionDraft
from budget_app.storage import DEFAULT_CATEGORIES, LedgerStorage
from budget_app.validation import parse_date


class TransactionStorageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.storage = LedgerStorage(Path(self.temp_dir.name))
        self.storage.initialize()

    def test_reverse_stream_handles_long_utf8_record(self) -> None:
        older = Transaction.create(TransactionDraft("expense", parse_date("2024-01-01"), 10, "food", "가" * 4000))
        newer = Transaction.create(TransactionDraft("expense", parse_date("2024-02-01"), 20, "food", "newer"))
        self.storage.transactions.save_many((newer, older))

        rows = list(self.storage.transactions.iter_latest())

        self.assertEqual([row.id for row in rows], [newer.id, older.id])
        self.assertEqual(rows[1].memo, "가" * 4000)

    def test_update_reorders_and_missing_delete_preserves_original_bytes(self) -> None:
        first = Transaction.create(TransactionDraft("expense", parse_date("2024-01-01"), 10, "food"))
        second = Transaction.create(TransactionDraft("expense", parse_date("2024-02-01"), 20, "food"))
        self.storage.transactions.save_many((first, second))

        self.storage.transactions.replace(replace(first, date=parse_date("2024-03-01")))
        before = self.storage.transactions.path.read_bytes()
        with self.assertRaises(AppError):
            self.storage.transactions.delete("TX-DOES-NOT-EXIST")

        self.assertEqual([row.id for row in self.storage.transactions.iter_latest()], [first.id, second.id])
        self.assertEqual(self.storage.transactions.path.read_bytes(), before)

    def test_removing_all_categories_stays_removed_after_restart(self) -> None:
        for name in DEFAULT_CATEGORIES:
            self.storage.categories.remove(name)

        reopened = LedgerStorage(self.storage.data_dir)
        reopened.initialize()

        self.assertEqual(list(reopened.categories.iter_names()), [])


if __name__ == "__main__":
    unittest.main()
