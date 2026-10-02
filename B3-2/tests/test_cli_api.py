import json
from pathlib import Path

import pytest
from pydantic import SecretStr
from typer.testing import CliRunner

from gitgen.cli import app
from gitgen.git import git
from gitgen.models import AppError, Draft, Mode, Settings, validate_draft
from tests.conftest import Endpoint


def completion(title: str, body: str = "") -> str:
    content = json.dumps({"summary": "app.txt 변경", "title": title, "body": body})
    return json.dumps({"choices": [{"message": {"content": content}, "finish_reason": "stop"}]})


def test_empty_skips_api_key(repo: Path) -> None:
    assert Path.cwd() == repo
    result = CliRunner().invoke(app, ["commit"])
    assert result.exit_code == 0
    assert "0회" in result.stdout


def test_missing_key(repo: Path) -> None:
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    result = CliRunner().invoke(app, ["commit"])
    assert result.exit_code == 2
    assert "AI_API_KEY" in result.output


@pytest.mark.parametrize("mode", ["commit", "pr"])
def test_real_http_cli(
    repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch, mode: str
) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    body = "## Why\n- 이유\n## What\n- 변경\n## How to Test\n- 확인 예정"
    endpoint.replies.append((200, completion("feat: 개선", body)))
    before = git(["status", "--porcelain=v1"], repo)
    result = CliRunner().invoke(
        app,
        [
            mode,
            "--base-url",
            endpoint.url,
            "--model",
            "test-model",
            "--temperature",
            "0.4",
            "--max-tokens",
            "321",
        ],
    )
    assert result.exit_code == 0, result.output
    assert "feat: 개선" in result.stdout
    assert len(endpoint.received) == 1
    request = endpoint.received[0]
    assert (request.model, request.temperature, request.max_completion_tokens) == (
        "test-model",
        0.4,
        321,
    )
    assert git(["status", "--porcelain=v1"], repo) == before


@pytest.mark.parametrize("status", [400, 401, 403, 429, 500, 302])
def test_http_errors(
    repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch, status: int
) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    endpoint.replies.append((status, "sensitive upstream error"))
    result = CliRunner().invoke(app, ["commit", "--base-url", endpoint.url])
    assert result.exit_code == 2
    assert str(status) in result.output
    assert "sensitive upstream error" not in result.output
    assert len(endpoint.received) == 1


def test_format_repair(repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    endpoint.replies.extend([(200, completion("x" * 73)), (200, completion("fix: short"))])
    result = CliRunner().invoke(app, ["commit", "--base-url", endpoint.url])
    assert result.exit_code == 0, result.output
    assert "fix: short" in result.stdout
    assert len(endpoint.received) == 2


def test_format_failure_stops_at_two(
    repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    endpoint.replies.append((200, completion("x" * 73)))
    result = CliRunner().invoke(app, ["commit", "--base-url", endpoint.url])
    assert result.exit_code == 2
    assert len(endpoint.received) == 2
    assert "x" * 73 not in result.output


@pytest.mark.parametrize(
    ("title", "body"),
    [
        ("title\nline", ""),
        ("x" * 81, ""),
        ("valid", "## Why\n- \n## What\n- change\n## How to Test\n- check"),
    ],
)
def test_pr_invalid_format(title: str, body: str) -> None:
    with pytest.raises(AppError):
        _ = validate_draft(Draft(summary="summary", title=title, body=body), Mode.PR)


def test_insecure_endpoint_rejected() -> None:
    with pytest.raises(AppError):
        _ = Settings(api_key=SecretStr("test"), base_url="http://example.com/v1")
