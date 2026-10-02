"""Argument parsing and the single user-facing error boundary."""

from __future__ import annotations

import argparse
import csv
import sys
from collections.abc import Callable
from functools import wraps
from pathlib import Path

from .commands import run_command
from .errors import AppError
from .service import BudgetService
from .storage import LedgerStorage


class FriendlyParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise AppError(f"명령어 인자가 올바르지 않습니다: {message}", "--help로 사용 방법을 확인하세요.")


def handle_cli_errors(command: Callable[[], int]) -> Callable[[], int]:
    """Translate expected failures into short messages and nonzero exits."""

    @wraps(command)
    def wrapped() -> int:
        try:
            return command()
        except AppError as exc:
            print(f"[오류] {exc.message}\n[힌트] {exc.hint}", file=sys.stderr)
            return 2
        except OSError as exc:
            print(f"[오류] 파일 처리에 실패했습니다: {exc}\n[힌트] 경로와 읽기/쓰기 권한을 확인하세요.", file=sys.stderr)
            return 2
        except (UnicodeError, csv.Error) as exc:
            print(f"[오류] 파일 형식이 올바르지 않습니다: {exc}\n[힌트] UTF-8 CSV/JSONL 형식을 확인하세요.", file=sys.stderr)
            return 2
        except KeyboardInterrupt:
            print("\n[오류] 사용자가 작업을 중단했습니다.\n[힌트] 다시 실행하면 저장된 데이터는 유지됩니다.", file=sys.stderr)
            return 130

    return wrapped


def build_parser() -> FriendlyParser:
    parser = FriendlyParser(prog="python -m budget_app", description="JSONL 파일에 저장하는 용돈 기입장")
    parser.add_argument("--data-dir", type=Path, default=Path("data"), help="저장 폴더 (기본: ./data; 명령어 앞에 입력)")
    commands = parser.add_subparsers(dest="command", required=True, parser_class=FriendlyParser)

    commands.add_parser("add", help="대화형으로 거래 추가")

    listing = commands.add_parser("list", help="거래를 날짜 최신순으로 조회")
    listing.add_argument("--limit", type=int, default=20, help="최대 출력 건수 (기본: 20)")

    searching = commands.add_parser("search", help="조건에 맞는 거래 검색")
    _add_filters(searching)

    summary = commands.add_parser("summary", help="월별 수입/지출 요약")
    summary.add_argument("--month", required=True, help="YYYY-MM")
    summary.add_argument("--top", type=int, default=5, help="지출 카테고리 최대 건수 (기본: 5)")

    budget = commands.add_parser("budget", help="월 예산 설정 또는 조회")
    budget_actions = budget.add_subparsers(dest="action", required=True, parser_class=FriendlyParser)
    budget_set = budget_actions.add_parser("set", help="월 예산 저장")
    budget_set.add_argument("--month", required=True, help="YYYY-MM")
    budget_set.add_argument("--amount", required=True, help="양수 정수")
    budget_show = budget_actions.add_parser("show", help="월 예산 조회")
    budget_show.add_argument("--month", required=True, help="YYYY-MM")

    category = commands.add_parser("category", help="카테고리 추가/목록/삭제")
    category_actions = category.add_subparsers(dest="action", required=True, parser_class=FriendlyParser)
    category_add = category_actions.add_parser("add", help="카테고리 추가 (기본 대화형)")
    category_add.add_argument("--name", help="카테고리 이름 (생략 시 입력)")
    category_actions.add_parser("list", help="카테고리 목록")
    category_remove = category_actions.add_parser("remove", help="사용하지 않는 카테고리 삭제")
    category_remove.add_argument("--name", help="카테고리 이름 (생략 시 입력)")

    update = commands.add_parser("update", help="옵션 방식으로 거래 수정")
    update.add_argument("--id", required=True, help="수정할 거래 id")
    update.add_argument("--date", help="YYYY-MM-DD")
    update.add_argument("--type", help="income 또는 expense")
    update.add_argument("--category", help="등록된 카테고리")
    update.add_argument("--amount", help="양수 정수")
    update.add_argument("--memo", help="새 메모 (빈 문자열로 삭제)")
    update.add_argument("--tags", help="쉼표 구분 태그 (빈 문자열로 삭제)")

    delete = commands.add_parser("delete", help="id로 거래 삭제")
    delete.add_argument("--id", required=True, help="삭제할 거래 id")

    importing = commands.add_parser("import", help="UTF-8 CSV 거래 가져오기")
    importing.add_argument("--from", dest="source", type=Path, required=True, help="CSV 파일 경로")

    exporting = commands.add_parser("export", help="조건에 맞는 거래를 UTF-8 CSV로 내보내기")
    exporting.add_argument("--out", type=Path, required=True, help="출력 CSV 경로")
    exporting.add_argument("--month", help="YYYY-MM")
    exporting.add_argument("--from", dest="date_from", help="시작일 YYYY-MM-DD")
    exporting.add_argument("--to", dest="date_to", help="종료일 YYYY-MM-DD")
    exporting.add_argument("--force", action="store_true", help="기존 CSV 파일 덮어쓰기")
    return parser


def _add_filters(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--from", dest="date_from", help="시작일 YYYY-MM-DD")
    parser.add_argument("--to", dest="date_to", help="종료일 YYYY-MM-DD")
    parser.add_argument("--category", help="카테고리")
    parser.add_argument("--type", help="income 또는 expense")
    parser.add_argument("--q", help="메모에 포함된 단어")
    parser.add_argument("--tag", help="태그")


@handle_cli_errors
def main() -> int:
    arguments = build_parser().parse_args()
    storage = LedgerStorage(arguments.data_dir)
    storage.initialize()
    return run_command(arguments, BudgetService(storage))
