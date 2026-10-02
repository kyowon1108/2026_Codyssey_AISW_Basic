"""Read-only collection of staged, unstaged, and untracked Git changes."""

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Final

from gitgen.models import AppError, Context
from gitgen.safety import allowed_file, redact

MAX_FILES: Final = 10
MAX_LINES: Final = 200
MAX_CHARS: Final = 20000
MAX_FILE_BYTES: Final = 65536


@dataclass(frozen=True, slots=True)
class FileChange:
    """Retain both paths so rename diffs include the original file."""

    code: str
    path: str
    source: str


def git(args: list[str], root: Path) -> str:
    """Run Git without shell interpretation or external diff programs."""
    try:
        result = subprocess.run(  # noqa: S603 -- fixed git executable, argument list
            ["git", "-c", "core.quotePath=false", *args],  # noqa: S607
            cwd=root,
            env={**os.environ, "GIT_OPTIONAL_LOCKS": "0", "GIT_PAGER": "cat"},
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise AppError("Git 실행 실패: 설치 상태 또는 실행 시간 초과를 확인하세요.") from exc
    valid = result.returncode == 0 or ("--no-index" in args and result.returncode == 1)
    if not valid:
        raise AppError("Git 명령 실패: Git 저장소 루트에서 실행하고 충돌 상태를 확인하세요.")
    return result.stdout


def file_diff(root: Path, entry: FileChange) -> tuple[str, bool]:
    """Read a file's index/worktree diff, omitting oversized untracked content."""
    code, path = entry.code, entry.path
    if code == "??":
        file = root / path
        if file.is_symlink() or not file.is_file() or file.stat().st_size > MAX_FILE_BYTES:
            return f"Untracked file (content omitted): {path}", True
        return git(
            [
                "diff",
                "--no-index",
                "--no-ext-diff",
                "--no-textconv",
                "--",
                os.devnull,
                path,
            ],
            root,
        ), False
    paths = list(dict.fromkeys([f":(literal){path}", f":(literal){entry.source}"]))
    snippets = [
        git(["diff", *staged, "--no-ext-diff", "--no-textconv", "--", *paths], root)
        for staged in ([], ["--cached"])
    ]
    return "\n".join(snippets), False


def collect(root: Path, context: Context, *, safe: bool) -> Context:
    """Bound a snapshot before constructing the API prompt."""
    top = git(["rev-parse", "--show-toplevel"], root).strip()
    if Path(top).resolve() != root.resolve():
        raise AppError("Git 프로젝트 루트 디렉토리에서 실행하세요.")
    status = git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], root)
    entries = iter(status.split("\0"))
    selected: list[FileChange] = []
    excluded = 0
    total = 0
    for entry in entries:
        if not entry:
            continue
        code, path = entry[:2], entry[3:]
        source = next(entries, "") if "R" in code or "C" in code else path
        total += 1
        if safe and (not allowed_file(path) or not allowed_file(source)):
            excluded += 1
            continue
        selected.append(FileChange(code, path, source))
    if total == 0:
        return context.model_copy(update={"status": "", "diff": ""})
    if not selected:
        raise AppError("전송 가능한 변경 사항이 없습니다. 민감 파일이 모두 제외되었습니다.")
    limited = len(selected) > MAX_FILES
    snippets: list[str] = []
    for entry in selected[:MAX_FILES]:
        snippet, omitted = file_diff(root, entry)
        snippets.append(snippet)
        limited = limited or omitted
    text = "\n".join(snippets)
    if safe:
        text = redact(text)
    lines = text.splitlines()
    bounded = "\n".join(lines[:MAX_LINES])[:MAX_CHARS]
    status_text = "\n".join(f"{entry.code} {entry.path}" for entry in selected[:MAX_FILES])
    outgoing = context.model_copy(
        update={
            "status": status_text,
            "diff": bounded,
            "limited": limited
            or len(lines) > MAX_LINES
            or len(bounded) < len("\n".join(lines[:MAX_LINES])),
            "excluded": excluded,
        }
    )
    if safe:
        outgoing = outgoing.model_copy(
            update={
                "status": redact(outgoing.status),
                "reason": redact(outgoing.reason),
                "requirements": redact(outgoing.requirements),
            }
        )
    return outgoing
