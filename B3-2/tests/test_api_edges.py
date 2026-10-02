import json
from pathlib import Path

import httpx2
import pytest
from pydantic import SecretStr
from typer.testing import CliRunner

from gitgen.api import request
from gitgen.cli import app
from gitgen.models import AppError, Settings
from tests.conftest import Endpoint
from tests.test_cli_api import completion


@pytest.mark.parametrize("failure", [httpx2.ReadTimeout("timeout"), httpx2.ConnectError("offline")])
def test_transport_errors(failure: httpx2.RequestError) -> None:
    def handler(_incoming: httpx2.Request) -> httpx2.Response:
        raise failure

    with httpx2.Client(transport=httpx2.MockTransport(handler)) as client, pytest.raises(AppError):
        _ = request(client, Settings(api_key=SecretStr("test")), "{}")


def test_malformed_envelope(
    repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    endpoint.replies.append((200, "{}"))
    result = CliRunner().invoke(app, ["commit", "--base-url", endpoint.url])
    assert result.exit_code == 2
    assert len(endpoint.received) == 1


def test_redaction_reaches_http_body(
    repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("person@example.com\n", encoding="utf-8")
    endpoint.replies.append((200, completion("fix: mask")))
    result = CliRunner().invoke(
        app, ["commit", "--base-url", endpoint.url, "--reason", "person@example.com"]
    )
    assert result.exit_code == 0
    assert "person@example.com" not in endpoint.received[0].model_dump_json()


def test_error_explanation_redacts_key() -> None:
    key = "test-only-key"

    def handler(_incoming: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(401, json={"error": {"message": "invalid: " + key}})

    with (
        httpx2.Client(transport=httpx2.MockTransport(handler)) as client,
        pytest.raises(AppError) as error,
    ):
        _ = request(client, Settings(api_key=SecretStr(key)), "{}")
    assert key not in str(error.value)
    assert "[REDACTED]" in str(error.value)


@pytest.mark.parametrize(
    ("flag", "value"),
    [
        ("--temperature", "nan"),
        ("--temperature", "2.1"),
        ("--max-tokens", "0"),
        ("--max-tokens", "32769"),
    ],
)
def test_invalid_options_make_zero_requests(
    repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch, flag: str, value: str
) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    result = CliRunner().invoke(app, ["commit", "--base-url", endpoint.url, flag, value])
    assert result.exit_code == 2
    assert endpoint.received == []


def test_truncated_response(
    repo: Path, endpoint: Endpoint, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("AI_API_KEY", "test-only-key")
    _ = (repo / "app.txt").write_text("changed", encoding="utf-8")
    endpoint.replies.append(
        (
            200,
            json.dumps(
                {
                    "choices": [
                        {
                            "message": {"content": "partial"},
                            "finish_reason": "length",
                        }
                    ]
                }
            ),
        )
    )
    result = CliRunner().invoke(app, ["commit", "--base-url", endpoint.url])
    assert result.exit_code == 2
    assert len(endpoint.received) == 1
