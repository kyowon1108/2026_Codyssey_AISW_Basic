from pathlib import Path

import pytest

from gitgen.git import collect, git
from gitgen.models import AppError, Context
from gitgen.safety import redact


def context() -> Context:
    return Context(status="", diff="", reason="", requirements="")


def test_clean_repo(repo: Path) -> None:
    assert collect(repo, context(), safe=True).status == ""


def test_staged_and_unstaged(repo: Path) -> None:
    _ = (repo / "app.txt").write_text("staged\n", encoding="utf-8")
    _ = git(["add", "app.txt"], repo)
    _ = (repo / "app.txt").write_text("working\n", encoding="utf-8")
    result = collect(repo, context(), safe=True)
    assert "+staged" in result.diff
    assert "+working" in result.diff


def test_untracked_literal_filename(repo: Path) -> None:
    _ = (repo / "[new] file.txt").write_text("new content\n", encoding="utf-8")
    assert "+new content" in collect(repo, context(), safe=True).diff


def test_delete(repo: Path) -> None:
    (repo / "app.txt").unlink()
    assert "-old" in collect(repo, context(), safe=True).diff


def test_rename(repo: Path) -> None:
    _ = git(["mv", "app.txt", "renamed.txt"], repo)
    assert "rename to renamed.txt" in collect(repo, context(), safe=True).diff


def test_exclude_and_mask_all_context(repo: Path) -> None:
    _ = (repo / ".env").write_text("private content", encoding="utf-8")
    _ = (repo / "app.txt").write_text("email=person@example.com\n", encoding="utf-8")
    data = context().model_copy(update={"reason": "person@example.com"})
    result = collect(repo, data, safe=True)
    assert result.excluded == 1
    assert "private content" not in result.diff
    assert "person@example.com" not in result.model_dump_json()


def test_only_sensitive_changes(repo: Path) -> None:
    _ = (repo / ".env").write_text("secret", encoding="utf-8")
    with pytest.raises(AppError):
        _ = collect(repo, context(), safe=True)


def test_bounded_context(repo: Path) -> None:
    for i in range(12):
        _ = (repo / f"file{i}.txt").write_text("line\n" * 300, encoding="utf-8")
    result = collect(repo, context(), safe=True)
    assert result.limited
    assert len(result.status.splitlines()) <= 10
    assert len(result.diff.splitlines()) <= 200
    assert len(result.diff) <= 20000


def test_subdirectory_rejected(repo: Path) -> None:
    child = repo / "child"
    child.mkdir()
    with pytest.raises(AppError):
        _ = collect(child, context(), safe=True)


def test_raw_mode_retains_email(repo: Path) -> None:
    _ = (repo / "app.txt").write_text("person@example.com\n", encoding="utf-8")
    assert "person@example.com" in collect(repo, context(), safe=False).diff


@pytest.mark.parametrize(
    "text",
    [
        "sk-fake-test-abcdefghijklmnop",
        "AKIAABCDEFGHIJKLMNOP",
        "ghp_abcdefghijklmnopqrstuvwxyz",
        "password = hunter2",
        "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----",
    ],
)
def test_credential_patterns(text: str) -> None:
    assert redact(text) == "[REDACTED]"
