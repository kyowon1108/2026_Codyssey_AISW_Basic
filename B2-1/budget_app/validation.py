"""Parse untrusted CLI and CSV values once at their boundaries."""

from __future__ import annotations

import re
from datetime import date
from typing import Literal

from .errors import AppError


TransactionType = Literal["income", "expense"]


def parse_date(raw: str) -> date:
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", raw):
        raise AppError("날짜 형식이 올바르지 않습니다.", "YYYY-MM-DD 형식으로 입력하세요. 예: 2024-01-15")
    try:
        return date.fromisoformat(raw)
    except ValueError as exc:
        raise AppError("존재하지 않는 날짜입니다.", "달력에 있는 날짜를 입력하세요. 예: 2024-02-29") from exc


def parse_month(raw: str) -> str:
    if not re.fullmatch(r"\d{4}-\d{2}", raw):
        raise AppError("월 형식이 올바르지 않습니다.", "YYYY-MM 형식으로 입력하세요. 예: 2024-01")
    try:
        date.fromisoformat(f"{raw}-01")
    except ValueError as exc:
        raise AppError("존재하지 않는 월입니다.", "1월부터 12월 사이의 월을 입력하세요.") from exc
    return raw


def parse_amount(raw: str) -> int:
    digits = raw.strip()
    if not re.fullmatch(r"[0-9]+", digits):
        raise AppError("금액은 정수여야 합니다.", "0보다 큰 정수를 입력하세요. 예: 15000")
    try:
        amount = int(digits)
    except ValueError as exc:
        raise AppError("금액은 정수여야 합니다.", "0보다 큰 정수를 입력하세요. 예: 15000") from exc
    if amount <= 0:
        raise AppError("금액은 0보다 커야 합니다.", "양수 정수를 입력하세요. 예: 15000")
    return amount


def parse_type(raw: str) -> TransactionType:
    match raw:  # noqa: MATCH_OK - parsing arbitrary input requires a rejecting default.
        case "income":
            return "income"
        case "expense":
            return "expense"
        case _:
            raise AppError("거래 타입이 올바르지 않습니다.", "income 또는 expense를 입력하세요.")


def parse_category(raw: str) -> str:
    name = raw.strip()
    if not name:
        raise AppError("카테고리 이름이 비어 있습니다.", "category list에서 기존 이름을 확인하거나 category add로 등록하세요.")
    if "\n" in name or "\r" in name:
        raise AppError("카테고리 이름에 줄바꿈을 사용할 수 없습니다.", "한 줄로 입력하세요.")
    return name


def parse_tags(raw: str) -> tuple[str, ...]:
    return tuple(dict.fromkeys(part.strip() for part in raw.split(",") if part.strip()))


def check_date_range(start: date | None, end: date | None) -> None:
    if start is not None and end is not None and start > end:
        raise AppError("시작일이 종료일보다 늦습니다.", "--from과 --to 날짜를 확인하세요.")
