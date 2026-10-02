"""Additional public-CLI scenarios for errors and report filters."""

from __future__ import annotations

import os
import subprocess
import sys
import unittest

from test_cli import PROJECT_DIR, CliCase


class BudgetCliEdgeTests(CliCase):
    def test_summary_warns_on_budget_overrun_and_empty_month(self) -> None:
        self.add_transaction("2024-04-02", "expense", "food", "1200", "lunch")
        self.assertEqual(self.run_cli("budget", "set", "--month", "2024-04", "--amount", "1000").returncode, 0)

        overrun = self.run_cli("summary", "--month", "2024-04")
        empty = self.run_cli("summary", "--month", "2024-05")
        persisted = self.run_cli("budget", "show", "--month", "2024-04")

        self.assertIn("120.0%", overrun.stdout)
        self.assertIn("초과", overrun.stdout)
        self.assertIn("데이터 없음", empty.stdout)
        self.assertIn("1000원", persisted.stdout)

    def test_rejects_invalid_fields_and_unknown_category_without_traceback(self) -> None:
        attempts = (
            "2024-01-01\nexpense\nfood\n0\n\n\n",
            "2024-01-01\nexpense\nfood\n1_0\n\n\n",
            "2024-01-01\ninvalid\nfood\n100\n\n\n",
            "2024-01-01\nexpense\nmissing\n100\n\n\n",
        )
        for attempt in attempts:
            with self.subTest(attempt=attempt):
                result = self.run_cli("add", input_text=attempt)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("힌트", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(self.run_cli("list").stdout.strip(), "데이터 없음")

    def test_search_combines_type_category_memo_and_tag(self) -> None:
        self.add_transaction("2024-06-10", "expense", "food", "300", "Team lunch", "work,meal")
        self.add_transaction("2024-06-11", "expense", "transport", "400", "bus", "work")
        matching = self.run_cli("search", "--from", "2024-06-01", "--to", "2024-06-30", "--type", "expense", "--category", "food", "--q", "lunch", "--tag", "meal")

        self.assertEqual(matching.returncode, 0, matching.stderr)
        self.assertIn("Team lunch", matching.stdout)
        self.assertNotIn("bus", matching.stdout)

    def test_corrupt_jsonl_exits_with_hint_without_traceback(self) -> None:
        self.run_cli("list")  # Initialize the three files.
        ledger = self.data_dir / "transactions.jsonl"
        for broken in (
            '{"id": 1}\n',
            '{"amount":' + "1" * 5000 + '}\n',
            "[" * 2000 + "0" + "]" * 2000 + "\n",
        ):
            with self.subTest(broken=broken[:20]):
                ledger.write_text(broken, encoding="utf-8")
                result = self.run_cli("list")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("힌트", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_corrupt_category_and_budget_jsonl_have_friendly_errors(self) -> None:
        self.run_cli("category", "list")
        broken = "[" * 2000 + "0" + "]" * 2000 + "\n"
        cases = (
            (self.data_dir / "categories.jsonl", ("category", "list")),
            (self.data_dir / "budgets.jsonl", ("budget", "show", "--month", "2024-01")),
        )
        for path, command in cases:
            with self.subTest(path=path):
                original = path.read_bytes()
                try:
                    path.write_text(broken, encoding="utf-8")
                    result = self.run_cli(*command)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("힌트", result.stderr)
                    self.assertNotIn("Traceback", result.stderr)
                finally:
                    path.write_bytes(original)

    def test_export_cannot_replace_storage_or_lock_files(self) -> None:
        self.add_transaction("2024-07-01", "expense", "food", "100", "safe")
        files = (*self.data_dir.glob("*.jsonl"), self.data_dir / ".ledger.lock")
        before = {path: path.read_bytes() for path in files}
        for path in files:
            with self.subTest(path=path):
                result = self.run_cli("export", "--out", str(path), "--month", "2024-07", "--force")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Traceback", result.stderr)
                self.assertEqual({item: item.read_bytes() for item in files}, before)

    def test_export_requires_force_to_replace_an_existing_csv(self) -> None:
        self.add_transaction("2024-07-01", "expense", "food", "100", "safe")
        destination = self.data_dir.parent / "existing.csv"
        destination.write_text("keep me", encoding="utf-8")

        refused = self.run_cli("export", "--out", str(destination), "--month", "2024-07")
        self.assertEqual(destination.read_text(encoding="utf-8"), "keep me")
        forced = self.run_cli("export", "--out", str(destination), "--month", "2024-07", "--force")

        self.assertNotEqual(refused.returncode, 0)
        self.assertEqual(forced.returncode, 0, forced.stderr)
        self.assertIn("date,type,category,amount,memo,tags", destination.read_text(encoding="utf-8"))

    def test_unterminated_csv_quote_rolls_back_entire_import(self) -> None:
        self.add_transaction("2024-07-01", "expense", "food", "100", "existing")
        before = (self.data_dir / "transactions.jsonl").read_bytes()
        source = self.data_dir.parent / "malformed.csv"
        source.write_text(
            'date,type,category,amount,memo,tags\n'
            '2024-07-02,expense,food,200,valid,\n'
            '2024-07-03,expense,food,300,"unterminated\n',
            encoding="utf-8",
        )

        result = self.run_cli("import", "--from", str(source))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.data_dir / "transactions.jsonl").read_bytes(), before)
        self.assertNotIn("Traceback", result.stderr)

    def test_duplicate_csv_header_is_rejected_without_importing(self) -> None:
        self.run_cli("category", "list")
        source = self.data_dir.parent / "duplicate-header.csv"
        source.write_text(
            "date,type,category,amount,memo,tags,date\n"
            "2024-07-02,expense,food,200,meal,,2024-07-03\n",
            encoding="utf-8",
        )

        result = self.run_cli("import", "--from", str(source))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.data_dir / "transactions.jsonl").read_bytes(), b"")

    def test_large_budget_usage_avoids_float_overflow(self) -> None:
        self.add_transaction("2024-07-01", "expense", "food", "1" + "0" * 400, "large")
        self.assertEqual(self.run_cli("budget", "set", "--month", "2024-07", "--amount", "1").returncode, 0)

        result = self.run_cli("summary", "--month", "2024-07")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("사용률:", result.stdout)
        self.assertNotIn("Traceback", result.stderr)

    @unittest.skipUnless(os.name == "posix", "fcntl file locks are POSIX-only")
    def test_second_cli_writer_waits_for_ledger_lock(self) -> None:
        import fcntl

        self.run_cli("category", "list")  # Initialize the data directory.
        lock_file = self.data_dir / ".ledger.lock"
        with lock_file.open("a+b") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            process = subprocess.Popen(
                [sys.executable, "-m", "budget_app", "--data-dir", str(self.data_dir), "budget", "set", "--month", "2024-07", "--amount", "100"],
                cwd=PROJECT_DIR,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.wait(timeout=1)
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            stdout, stderr = process.communicate(timeout=5)

        self.assertEqual(process.returncode, 0, stderr)
        self.assertIn("저장 완료", stdout)

    def test_every_command_has_help(self) -> None:
        commands = (
            ("add",), ("list",), ("search",), ("summary",),
            ("budget",), ("budget", "set"), ("budget", "show"),
            ("category",), ("category", "add"), ("category", "list"), ("category", "remove"),
            ("update",), ("delete",), ("import",), ("export",),
        )
        for command in commands:
            with self.subTest(command=command):
                result = self.run_cli(*command, "--help")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("usage:", result.stdout)


if __name__ == "__main__":
    unittest.main()
