"""User-facing command behavior and readable console output."""

from __future__ import annotations

import argparse
from collections.abc import Iterator

from .errors import AppError
from .models import Transaction, TransactionDraft, TransactionPatch
from .service import BudgetService, SearchFilters
from .validation import check_date_range, parse_amount, parse_category, parse_date, parse_month, parse_tags, parse_type


def run_command(arguments: argparse.Namespace, service: BudgetService) -> int:
    match arguments.command:  # noqa: MATCH_OK - argparse supplies an open string; default reports user error.
        case "add":
            return _add(service)
        case "list":
            return _list(arguments, service)
        case "search":
            return _search(arguments, service)
        case "summary":
            return _summary(arguments, service)
        case "budget":
            return _budget(arguments, service)
        case "category":
            return _category(arguments, service)
        case "update":
            return _update(arguments, service)
        case "delete":
            return _delete(arguments, service)
        case "import":
            return _import(arguments, service)
        case "export":
            return _export(arguments, service)
        case _:
            raise AppError("알 수 없는 명령어입니다.", "--help로 사용 가능한 명령어를 확인하세요.")


def _prompt(label: str) -> str:
    try:
        return input(label)
    except EOFError as exc:
        raise AppError("입력이 중간에 끝났습니다.", "필요한 값을 모두 입력한 뒤 다시 실행하세요.") from exc


def _add(service: BudgetService) -> int:
    draft = TransactionDraft(
        date=parse_date(_prompt("날짜(YYYY-MM-DD): ")),
        type=parse_type(_prompt("타입(income/expense): ")),
        category=parse_category(_prompt("카테고리: ")),
        amount=parse_amount(_prompt("금액(양수 정수): ")),
        memo=_prompt("메모(선택): ").strip(),
        tags=parse_tags(_prompt("태그(쉼표 구분, 선택): ")),
    )
    transaction = service.add(draft)
    print(f"[저장 완료] id={transaction.id}")
    return 0


def _print_transactions(transactions: Iterator[Transaction]) -> int:
    count = 0
    for transaction in transactions:
        tags = ",".join(transaction.tags)
        print(f"{transaction.id} | {transaction.date.isoformat()} | {transaction.type} | {transaction.category} | {transaction.amount} | {transaction.memo} | {tags}")
        count += 1
    if count == 0:
        print("데이터 없음")
    return 0


def _list(arguments: argparse.Namespace, service: BudgetService) -> int:
    if arguments.limit <= 0:
        raise AppError("--limit은 0보다 커야 합니다.", "예: list --limit 20")
    return _print_transactions(service.list_recent(arguments.limit))


def _filters(arguments: argparse.Namespace) -> SearchFilters:
    start = parse_date(arguments.date_from) if getattr(arguments, "date_from", None) is not None else None
    end = parse_date(arguments.date_to) if getattr(arguments, "date_to", None) is not None else None
    check_date_range(start, end)
    return SearchFilters(
        start=start,
        end=end,
        month=parse_month(arguments.month) if getattr(arguments, "month", None) is not None else None,
        category=parse_category(arguments.category) if getattr(arguments, "category", None) is not None else None,
        type=parse_type(arguments.type) if getattr(arguments, "type", None) is not None else None,
        query=arguments.q.strip() if getattr(arguments, "q", None) is not None else None,
        tag=arguments.tag.strip() if getattr(arguments, "tag", None) is not None else None,
    )


def _search(arguments: argparse.Namespace, service: BudgetService) -> int:
    return _print_transactions(service.search(_filters(arguments)))


def _summary(arguments: argparse.Namespace, service: BudgetService) -> int:
    month = parse_month(arguments.month)
    if arguments.top <= 0:
        raise AppError("--top은 0보다 커야 합니다.", "예: summary --month 2024-01 --top 3")
    result = service.summary(month, arguments.top)
    if result.count == 0:
        print(f"{month}: 데이터 없음")
    print(f"총 수입: {result.income}원")
    print(f"총 지출: {result.expense}원")
    print(f"잔액: {result.balance}원")
    if result.budget is not None:
        usage_tenths, remainder = divmod(result.expense * 1000, result.budget)
        if remainder * 2 >= result.budget:
            usage_tenths += 1
        print(f"예산: {result.budget}원 (사용률: {usage_tenths // 10}.{usage_tenths % 10}%)")
        if result.expense > result.budget:
            print("[경고] 월 예산을 초과했습니다.")
    print(f"지출 TOP {arguments.top}")
    for index, (name, amount) in enumerate(result.category_top, start=1):
        print(f"{index}) {name} {amount}원")
    return 0


def _budget(arguments: argparse.Namespace, service: BudgetService) -> int:
    month = parse_month(arguments.month)
    match arguments.action:  # noqa: MATCH_OK - argparse supplies an open string; default reports user error.
        case "set":
            amount = parse_amount(arguments.amount)
            service.budget_set(month, amount)
            print(f"[저장 완료] {month} 예산 {amount}원")
        case "show":
            amount = service.budget_get(month)
            print(f"{month} 예산: {amount}원" if amount is not None else f"{month}: 설정된 예산 없음")
        case _:
            raise AppError("알 수 없는 예산 명령어입니다.", "budget --help를 확인하세요.")
    return 0


def _category(arguments: argparse.Namespace, service: BudgetService) -> int:
    match arguments.action:  # noqa: MATCH_OK - argparse supplies an open string; default reports user error.
        case "add":
            name = parse_category(arguments.name if arguments.name is not None else _prompt("카테고리명: "))
            service.category_add(name)
            print(f"[저장 완료] category={name}")
        case "list":
            for name in service.category_names():
                print(f"- {name}")
        case "remove":
            name = parse_category(arguments.name if arguments.name is not None else _prompt("삭제할 카테고리명: "))
            service.category_remove(name)
            print(f"[삭제 완료] category={name}")
        case _:
            raise AppError("알 수 없는 카테고리 명령어입니다.", "category --help를 확인하세요.")
    return 0


def _update(arguments: argparse.Namespace, service: BudgetService) -> int:
    fields = ("date", "type", "category", "amount", "memo", "tags")
    if not any(getattr(arguments, field) is not None for field in fields):
        raise AppError("수정할 필드가 없습니다.", "update --help에서 수정 가능한 옵션을 확인하세요.")
    patch = TransactionPatch(
        date=parse_date(arguments.date) if arguments.date is not None else None,
        type=parse_type(arguments.type) if arguments.type is not None else None,
        category=parse_category(arguments.category) if arguments.category is not None else None,
        amount=parse_amount(arguments.amount) if arguments.amount is not None else None,
        memo=arguments.memo.strip() if arguments.memo is not None else None,
        tags=parse_tags(arguments.tags) if arguments.tags is not None else None,
    )
    service.update(arguments.id, patch)
    print(f"[수정 완료] id={arguments.id}")
    return 0


def _delete(arguments: argparse.Namespace, service: BudgetService) -> int:
    service.delete(arguments.id)
    print(f"[삭제 완료] id={arguments.id}")
    return 0


def _import(arguments: argparse.Namespace, service: BudgetService) -> int:
    count = service.import_csv(arguments.source)
    print(f"[완료] imported={count}, skipped=0")
    return 0


def _export(arguments: argparse.Namespace, service: BudgetService) -> int:
    if arguments.month is None and arguments.date_from is None and arguments.date_to is None:
        raise AppError("내보내기 조건이 없습니다.", "--month 또는 --from/--to 중 하나 이상을 지정하세요.")
    count = service.export_csv(arguments.out, _filters(arguments), overwrite=arguments.force)
    print(f"[완료] {arguments.out} ({count} records)")
    return 0
