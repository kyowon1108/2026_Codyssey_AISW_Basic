"""Fixed UTF-8 CSV interchange format for transactions."""

from __future__ import annotations

import csv
from collections.abc import Iterator
from pathlib import Path
from typing import Final

from .errors import AppError
from .models import Transaction, TransactionDraft
from .storage import atomic_text_writer
from .validation import parse_amount, parse_category, parse_date, parse_tags, parse_type


CSV_COLUMNS: Final[tuple[str, ...]] = ("date", "type", "category", "amount", "memo", "tags")
REQUIRED_COLUMNS: Final[frozenset[str]] = frozenset(CSV_COLUMNS[:4])


def read_import_file(path: Path) -> Iterator[TransactionDraft]:
    """Parse rows lazily; the service stages them before changing JSONL."""
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, strict=True)
        if reader.fieldnames is None or not REQUIRED_COLUMNS.issubset(reader.fieldnames):
            raise AppError("CSV 헤더에 필수 열이 없습니다.", "date,type,category,amount 열을 확인하세요.")
        if len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise AppError("CSV 헤더에 중복된 열이 있습니다.", "각 열 이름을 한 번씩만 사용하세요.")
        for row_number, row in enumerate(reader, start=2):
            if None in row:
                raise AppError(f"CSV {row_number}행에 열이 너무 많습니다.", "쉼표가 들어간 값은 큰따옴표로 감싸세요.")
            try:
                yield TransactionDraft(
                    type=parse_type(row["type"] or ""),
                    date=parse_date(row["date"] or ""),
                    amount=parse_amount(row["amount"] or ""),
                    category=parse_category(row["category"] or ""),
                    memo=row.get("memo") or "",
                    tags=parse_tags(row.get("tags") or ""),
                )
            except AppError as exc:
                raise AppError(f"CSV {row_number}행: {exc.message}", exc.hint) from exc


def write_export_file(path: Path, transactions: Iterator[Transaction]) -> int:
    """Write a CSV atomically while consuming transactions one at a time."""
    count = 0
    with atomic_text_writer(path) as stream:
        writer = csv.DictWriter(stream, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for transaction in transactions:
            writer.writerow(
                {
                    "date": transaction.date.isoformat(),
                    "type": transaction.type,
                    "category": transaction.category,
                    "amount": transaction.amount,
                    "memo": transaction.memo,
                    "tags": ",".join(transaction.tags),
                }
            )
            count += 1
    return count
