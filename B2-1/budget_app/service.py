"""Business rules that join the file stores to CLI operations."""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import date
from itertools import islice
from pathlib import Path

from .csv_io import read_import_file, write_export_file
from .errors import AppError
from .models import Transaction, TransactionDraft, TransactionPatch
from .storage import LedgerStorage
from .validation import TransactionType, check_date_range


@dataclass(frozen=True, slots=True)
class SearchFilters:
    start: date | None = None
    end: date | None = None
    month: str | None = None
    category: str | None = None
    type: TransactionType | None = None
    query: str | None = None
    tag: str | None = None


@dataclass(frozen=True, slots=True)
class MonthlySummary:
    count: int
    income: int
    expense: int
    category_top: tuple[tuple[str, int], ...]
    budget: int | None

    @property
    def balance(self) -> int:
        return self.income - self.expense


class BudgetService:
    """Apply category, transaction, search, and budget rules."""

    def __init__(self, storage: LedgerStorage) -> None:
        self.storage = storage

    def add(self, draft: TransactionDraft) -> Transaction:
        with self.storage.write_lock():
            self._require_category(draft.category)
            transaction = Transaction.create(draft)
            self.storage.transactions.save_many((transaction,))
        return transaction

    def list_recent(self, limit: int) -> Iterator[Transaction]:
        return islice(self.storage.transactions.iter_latest(), limit)

    def search(self, filters: SearchFilters) -> Iterator[Transaction]:
        check_date_range(filters.start, filters.end)
        if filters.category is not None:
            self._require_category(filters.category)
        for transaction in self.storage.transactions.iter_latest():
            if filters.start is not None and transaction.date < filters.start:
                continue
            if filters.end is not None and transaction.date > filters.end:
                continue
            if filters.month is not None and transaction.date.isoformat()[:7] != filters.month:
                continue
            if filters.category is not None and transaction.category != filters.category:
                continue
            if filters.type is not None and transaction.type != filters.type:
                continue
            if filters.query is not None and filters.query.casefold() not in transaction.memo.casefold():
                continue
            if filters.tag is not None and filters.tag.casefold() not in (tag.casefold() for tag in transaction.tags):
                continue
            yield transaction

    def summary(self, month: str, top: int) -> MonthlySummary:
        count = income = expense = 0
        category_expenses: dict[str, int] = {}
        for transaction in self.storage.transactions.iter_all():
            if transaction.date.isoformat()[:7] != month:
                continue
            count += 1
            if transaction.type == "income":
                income += transaction.amount
            else:
                expense += transaction.amount
                category_expenses[transaction.category] = category_expenses.get(transaction.category, 0) + transaction.amount
        ranked = sorted(category_expenses.items(), key=lambda item: (-item[1], item[0]))[:top]
        return MonthlySummary(count, income, expense, tuple(ranked), self.storage.budgets.get(month))

    def update(self, tx_id: str, patch: TransactionPatch) -> None:
        with self.storage.write_lock():
            original = self.storage.transactions.get(tx_id)
            if original is None:
                raise AppError("거래를 찾을 수 없습니다.", "list에서 id를 확인한 뒤 다시 시도하세요.")
            if patch.category is not None:
                self._require_category(patch.category)
            self.storage.transactions.replace(patch.apply(original))

    def delete(self, tx_id: str) -> None:
        with self.storage.write_lock():
            self.storage.transactions.delete(tx_id)

    def category_names(self) -> list[str]:
        return sorted(self.storage.categories.iter_names())

    def category_add(self, name: str) -> None:
        with self.storage.write_lock():
            self.storage.categories.add(name)

    def category_remove(self, name: str) -> None:
        with self.storage.write_lock():
            if self.storage.transactions.uses_category(name):
                raise AppError("사용 중인 카테고리는 삭제할 수 없습니다.", "해당 거래를 수정하거나 삭제한 뒤 다시 시도하세요.")
            self.storage.categories.remove(name)

    def budget_set(self, month: str, amount: int) -> None:
        with self.storage.write_lock():
            self.storage.budgets.set(month, amount)

    def budget_get(self, month: str) -> int | None:
        return self.storage.budgets.get(month)

    def import_csv(self, path: Path) -> int:
        drafts = list(read_import_file(path))
        with self.storage.write_lock():
            for draft in drafts:
                self._require_category(draft.category)
            return self.storage.transactions.save_many(tuple(Transaction.create(draft) for draft in drafts))

    def export_csv(self, path: Path, filters: SearchFilters, *, overwrite: bool = False) -> int:
        with self.storage.write_lock():
            protected = (
                self.storage.transactions.path,
                self.storage.categories.path,
                self.storage.budgets.path,
                self.storage.lock_path,
            )
            destination = path.resolve(strict=False)
            if any(destination == saved.resolve(strict=False) or (path.exists() and path.samefile(saved)) for saved in protected):
                raise AppError("저장 파일로 내보낼 수 없습니다.", "거래·카테고리·예산·잠금 파일과 다른 CSV 경로를 지정하세요.")
            if path.exists() and not overwrite:
                raise AppError("출력 파일이 이미 존재합니다.", "덮어쓰려면 --force를 지정하세요.")
            return write_export_file(path, self.search(filters))

    def _require_category(self, name: str) -> None:
        if not self.storage.categories.exists(name):
            raise AppError(f"등록되지 않은 카테고리입니다: {name}", "category list로 확인하거나 category add로 등록하세요.")
