"""Streaming JSONL stores and atomic file replacement."""

from __future__ import annotations

import heapq
import json
import os
import tempfile
from collections.abc import Iterator, Sequence
from contextlib import AbstractContextManager, contextmanager
from pathlib import Path
from typing import Final, TextIO

from .errors import AppError, RecordFormatError
from .models import Transaction
from .validation import parse_amount, parse_category, parse_month


DEFAULT_CATEGORIES: Final[tuple[str, ...]] = ("food", "transport", "rent", "salary", "other")


@contextmanager
def atomic_text_writer(path: Path) -> Iterator[TextIO]:
    """Replace a file only after its complete new contents are durable."""
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            yield stream
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def reverse_lines(path: Path) -> Iterator[str]:
    """Yield complete UTF-8 lines from the end without reading the whole file."""
    with path.open("rb") as stream:
        stream.seek(0, os.SEEK_END)
        position = stream.tell()
        remainder = b""
        while position:
            size = min(8192, position)
            position -= size
            stream.seek(position)
            parts = (stream.read(size) + remainder).split(b"\n")
            remainder = parts[0]
            for raw in reversed(parts[1:]):
                if raw:
                    yield raw.decode("utf-8")
        if remainder:
            yield remainder.decode("utf-8")


@contextmanager
def exclusive_file_lock(path: Path) -> Iterator[None]:
    """Serialize CLI writers across processes while preserving crash release."""
    with path.open("a+b") as stream:
        if os.name == "nt":
            import msvcrt

            stream.seek(0, os.SEEK_END)
            if stream.tell() == 0:
                stream.write(b"\0")
                stream.flush()
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl

            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if os.name == "nt":
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


class TransactionRepository:
    """Keep transactions sorted by date so reverse iteration is newest-first."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def iter_all(self) -> Iterator[Transaction]:
        with self.path.open("r", encoding="utf-8") as stream:
            for line in stream:
                if line.strip():
                    yield Transaction.from_json_line(line)

    def iter_latest(self) -> Iterator[Transaction]:
        for line in reverse_lines(self.path):
            yield Transaction.from_json_line(line)

    def get(self, tx_id: str) -> Transaction | None:
        return next((transaction for transaction in self.iter_all() if transaction.id == tx_id), None)

    def save_many(self, transactions: Sequence[Transaction]) -> int:
        incoming = sorted(transactions, key=lambda transaction: transaction.sort_key)
        with atomic_text_writer(self.path) as stream:
            for transaction in heapq.merge(self.iter_all(), incoming, key=lambda item: item.sort_key):
                stream.write(transaction.to_json_line())
        return len(incoming)

    def replace(self, replacement: Transaction) -> None:
        found = False

        def survivors() -> Iterator[Transaction]:
            nonlocal found
            for transaction in self.iter_all():
                if transaction.id == replacement.id:
                    found = True
                else:
                    yield transaction

        with atomic_text_writer(self.path) as stream:
            for transaction in heapq.merge(survivors(), (replacement,), key=lambda item: item.sort_key):
                stream.write(transaction.to_json_line())
            if not found:
                raise AppError("거래를 찾을 수 없습니다.", "list에서 id를 확인한 뒤 다시 시도하세요.")

    def delete(self, tx_id: str) -> None:
        found = False
        with atomic_text_writer(self.path) as stream:
            for transaction in self.iter_all():
                if transaction.id == tx_id:
                    found = True
                else:
                    stream.write(transaction.to_json_line())
            if not found:
                raise AppError("거래를 찾을 수 없습니다.", "list에서 id를 확인한 뒤 다시 시도하세요.")

    def uses_category(self, category: str) -> bool:
        return any(transaction.category == category for transaction in self.iter_all())


class CategoryStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    def iter_names(self) -> Iterator[str]:
        with self.path.open("r", encoding="utf-8") as stream:
            for line in stream:
                if not line.strip():
                    continue
                try:
                    raw = json.loads(line)
                    if not isinstance(raw, dict) or not isinstance(raw.get("name"), str):
                        raise RecordFormatError
                    yield parse_category(raw["name"])
                except (ValueError, RecursionError, RecordFormatError, AppError) as exc:
                    raise AppError("카테고리 파일이 손상되었습니다.", "categories.jsonl 파일을 확인하세요.") from exc

    def exists(self, name: str) -> bool:
        return any(stored == name for stored in self.iter_names())

    def add(self, name: str) -> None:
        if self.exists(name):
            raise AppError("이미 등록된 카테고리입니다.", "category list로 목록을 확인하세요.")
        with atomic_text_writer(self.path) as stream:
            for existing in self.iter_names():
                stream.write(json.dumps({"name": existing}, ensure_ascii=False) + "\n")
            stream.write(json.dumps({"name": name}, ensure_ascii=False) + "\n")

    def remove(self, name: str) -> None:
        found = False
        with atomic_text_writer(self.path) as stream:
            for existing in self.iter_names():
                if existing == name:
                    found = True
                else:
                    stream.write(json.dumps({"name": existing}, ensure_ascii=False) + "\n")
            if not found:
                raise AppError("카테고리를 찾을 수 없습니다.", "category list로 이름을 확인하세요.")


class BudgetStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    def iter_budgets(self) -> Iterator[tuple[str, int]]:
        with self.path.open("r", encoding="utf-8") as stream:
            for line in stream:
                if not line.strip():
                    continue
                try:
                    raw = json.loads(line)
                    if not isinstance(raw, dict) or not isinstance(raw.get("month"), str) or type(raw.get("amount")) is not int:
                        raise RecordFormatError
                    yield parse_month(raw["month"]), parse_amount(str(raw["amount"]))
                except (ValueError, RecursionError, RecordFormatError, AppError) as exc:
                    raise AppError("예산 파일이 손상되었습니다.", "budgets.jsonl 파일을 확인하세요.") from exc

    def get(self, month: str) -> int | None:
        return next((amount for saved_month, amount in self.iter_budgets() if saved_month == month), None)

    def set(self, month: str, amount: int) -> None:
        found = False
        with atomic_text_writer(self.path) as stream:
            for saved_month, saved_amount in self.iter_budgets():
                if saved_month == month:
                    found = True
                    saved_amount = amount
                stream.write(json.dumps({"month": saved_month, "amount": saved_amount}, ensure_ascii=False) + "\n")
            if not found:
                stream.write(json.dumps({"month": month, "amount": amount}, ensure_ascii=False) + "\n")


class LedgerStorage:
    """Own the three durable JSONL files and their repositories."""

    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir
        self.transactions = TransactionRepository(data_dir / "transactions.jsonl")
        self.categories = CategoryStore(data_dir / "categories.jsonl")
        self.budgets = BudgetStore(data_dir / "budgets.jsonl")

    @property
    def lock_path(self) -> Path:
        return self.data_dir / ".ledger.lock"

    def write_lock(self) -> AbstractContextManager[None]:
        return exclusive_file_lock(self.lock_path)

    def initialize(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        with self.write_lock():
            self.transactions.path.touch(exist_ok=True)
            self.budgets.path.touch(exist_ok=True)
            if not self.categories.path.exists():
                with atomic_text_writer(self.categories.path) as stream:
                    for name in DEFAULT_CATEGORIES:
                        stream.write(json.dumps({"name": name}, ensure_ascii=False) + "\n")
