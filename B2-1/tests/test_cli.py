"""End-to-end checks through the public console interface."""

from __future__ import annotations

import csv
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[1]


class CliCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.data_dir = Path(self.temp_dir.name) / "data"

    def run_cli(self, *args: str, input_text: str = "") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-m", "budget_app", "--data-dir", str(self.data_dir), *args],
            cwd=PROJECT_DIR,
            input=input_text,
            text=True,
            capture_output=True,
            check=False,
        )

    def add_transaction(self, date: str, kind: str, category: str, amount: str, memo: str, tags: str = "") -> str:
        result = self.run_cli("add", input_text=f"{date}\n{kind}\n{category}\n{amount}\n{memo}\n{tags}\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        match = re.search(r"id=(TX-[A-Za-z0-9]+)", result.stdout)
        self.assertIsNotNone(match, result.stdout)
        return match.group(1)


class BudgetCliTests(CliCase):

    def test_add_list_and_search_sort_by_transaction_date(self) -> None:
        self.add_transaction("2024-01-20", "expense", "food", "2000", "later", "meal")
        self.add_transaction("2024-01-05", "expense", "food", "1000", "earlier", "snack")

        listed = self.run_cli("list", "--limit", "2")
        searched = self.run_cli("search", "--from", "2024-01-01", "--to", "2024-01-31", "--tag", "meal")

        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertLess(listed.stdout.index("later"), listed.stdout.index("earlier"))
        self.assertEqual(searched.returncode, 0, searched.stderr)
        self.assertIn("later", searched.stdout)
        self.assertNotIn("earlier", searched.stdout)
        self.assertEqual(sorted(path.name for path in self.data_dir.glob("*.jsonl")), ["budgets.jsonl", "categories.jsonl", "transactions.jsonl"])

    def test_budget_summary_update_delete_and_category_guard(self) -> None:
        expense_id = self.add_transaction("2024-02-15", "expense", "food", "1000", "lunch")
        self.add_transaction("2024-02-01", "income", "salary", "3000", "pay")
        self.assertEqual(self.run_cli("budget", "set", "--month", "2024-02", "--amount", "2000").returncode, 0)

        summary = self.run_cli("summary", "--month", "2024-02", "--top", "2")
        guarded = self.run_cli("category", "remove", "--name", "food")
        updated = self.run_cli("update", "--id", expense_id, "--amount", "1200", "--memo", "updated")
        deleted = self.run_cli("delete", "--id", expense_id)
        missing = self.run_cli("delete", "--id", expense_id)

        self.assertEqual(summary.returncode, 0, summary.stderr)
        self.assertIn("총 수입: 3000", summary.stdout)
        self.assertIn("총 지출: 1000", summary.stdout)
        self.assertIn("사용률: 50.0%", summary.stdout)
        self.assertNotEqual(guarded.returncode, 0)
        self.assertEqual(updated.returncode, 0, updated.stderr)
        self.assertEqual(deleted.returncode, 0, deleted.stderr)
        self.assertNotEqual(missing.returncode, 0)
        self.assertNotIn("Traceback", missing.stderr)
        self.assertEqual(self.run_cli("category", "remove", "--name", "food").returncode, 0)

    def test_import_rolls_back_on_invalid_row_and_export_round_trips(self) -> None:
        self.add_transaction("2024-03-01", "expense", "food", "500", "existing", "meal")
        before = (self.data_dir / "transactions.jsonl").read_bytes()
        source = Path(self.temp_dir.name) / "incoming.csv"
        with source.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("date", "type", "category", "amount", "memo", "tags"))
            writer.writerow(("2024-03-02", "expense", "food", "700", "imported", "meal,work"))
            writer.writerow(("2024-03-03", "expense", "food", "0", "invalid", ""))

        rejected = self.run_cli("import", "--from", str(source))
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual((self.data_dir / "transactions.jsonl").read_bytes(), before)
        self.assertNotIn("Traceback", rejected.stderr)

        with source.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("date", "type", "category", "amount", "memo", "tags"))
            writer.writerow(("2024-03-02", "expense", "food", "700", "imported", "meal,work"))
        imported = self.run_cli("import", "--from", str(source))
        destination = Path(self.temp_dir.name) / "export.csv"
        exported = self.run_cli("export", "--out", str(destination), "--month", "2024-03")

        self.assertEqual(imported.returncode, 0, imported.stderr)
        self.assertEqual(exported.returncode, 0, exported.stderr)
        with destination.open("r", encoding="utf-8", newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 2)
        self.assertEqual(set(rows[0]), {"date", "type", "category", "amount", "memo", "tags"})
        self.assertEqual(rows[0]["memo"], "imported")
        self.assertEqual(rows[0]["tags"], "meal,work")
        self.assertEqual(rows[1]["memo"], "existing")

    def test_invalid_input_and_help_have_useful_exit_codes(self) -> None:
        bad_add = self.run_cli("add", input_text="2024-13-40\nexpense\nfood\n100\n\n\n")
        bad_export = self.run_cli("export", "--out", str(Path(self.temp_dir.name) / "out.csv"))
        help_result = self.run_cli("--help")

        self.assertNotEqual(bad_add.returncode, 0)
        self.assertIn("힌트", bad_add.stderr)
        self.assertNotIn("Traceback", bad_add.stderr)
        self.assertNotEqual(bad_export.returncode, 0)
        self.assertEqual(help_result.returncode, 0)
        self.assertIn("summary", help_result.stdout)


if __name__ == "__main__":
    unittest.main()
