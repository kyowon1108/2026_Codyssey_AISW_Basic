"""Typed transaction values and JSONL serialization."""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
from datetime import date
from uuid import uuid4

from .errors import AppError, RecordFormatError
from .validation import TransactionType, parse_amount, parse_category, parse_date, parse_type


@dataclass(frozen=True, slots=True)
class TransactionDraft:
    type: TransactionType
    date: date
    amount: int
    category: str
    memo: str = ""
    tags: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Transaction:
    id: str
    type: TransactionType
    date: date
    amount: int
    category: str
    memo: str = ""
    tags: tuple[str, ...] = ()

    @classmethod
    def create(cls, draft: TransactionDraft) -> Transaction:
        return cls(f"TX-{uuid4().hex.upper()}", draft.type, draft.date, draft.amount, draft.category, draft.memo, draft.tags)

    @classmethod
    def from_json_line(cls, line: str) -> Transaction:
        try:
            raw = json.loads(line)
            if not isinstance(raw, dict):
                raise RecordFormatError
            tx_id = raw["id"]
            tx_type = raw["type"]
            tx_date = raw["date"]
            amount = raw["amount"]
            category = raw["category"]
            memo = raw.get("memo", "")
            tags = raw.get("tags", [])
            if not isinstance(tx_id, str) or not tx_id:
                raise RecordFormatError
            if not isinstance(tx_type, str) or not isinstance(tx_date, str) or not isinstance(category, str):
                raise RecordFormatError
            if type(amount) is not int or not isinstance(memo, str):
                raise RecordFormatError
            if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
                raise RecordFormatError
            return cls(tx_id, parse_type(tx_type), parse_date(tx_date), parse_amount(str(amount)), parse_category(category), memo, tuple(tags))
        except (ValueError, RecursionError, KeyError, RecordFormatError, AppError) as exc:
            raise AppError("저장된 거래 데이터가 손상되었습니다.", "transactions.jsonl 파일을 확인하거나 백업에서 복구하세요.") from exc

    def to_json_line(self) -> str:
        return json.dumps(
            {
                "id": self.id,
                "type": self.type,
                "date": self.date.isoformat(),
                "amount": self.amount,
                "category": self.category,
                "memo": self.memo,
                "tags": list(self.tags),
            },
            ensure_ascii=False,
            separators=(",", ":"),
        ) + "\n"

    @property
    def sort_key(self) -> tuple[date, str]:
        return self.date, self.id


@dataclass(frozen=True, slots=True)
class TransactionPatch:
    date: date | None = None
    type: TransactionType | None = None
    category: str | None = None
    amount: int | None = None
    memo: str | None = None
    tags: tuple[str, ...] | None = None

    def apply(self, original: Transaction) -> Transaction:
        return replace(
            original,
            date=self.date if self.date is not None else original.date,
            type=self.type if self.type is not None else original.type,
            category=self.category if self.category is not None else original.category,
            amount=self.amount if self.amount is not None else original.amount,
            memo=self.memo if self.memo is not None else original.memo,
            tags=self.tags if self.tags is not None else original.tags,
        )
