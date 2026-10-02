from collections.abc import Iterator
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread

import pytest
from pydantic import BaseModel
from typing_extensions import override

from gitgen.git import git


class InputMessage(BaseModel):
    role: str
    content: str


class InputRequest(BaseModel):
    model: str
    temperature: float | None = None
    max_completion_tokens: int
    messages: list[InputMessage]


@dataclass(frozen=True, slots=True)
class Endpoint:
    url: str
    replies: list[tuple[int, str]]
    received: list[InputRequest]


@pytest.fixture
def repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    _ = git(["init", "-q"], tmp_path)
    _ = git(["config", "user.email", "test@example.invalid"], tmp_path)
    _ = git(["config", "user.name", "Test"], tmp_path)
    _ = (tmp_path / "app.txt").write_text("old\n", encoding="utf-8")
    _ = git(["add", "app.txt"], tmp_path)
    _ = git(["commit", "-qm", "initial"], tmp_path)
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("AI_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    return tmp_path


@pytest.fixture
def endpoint() -> Iterator[Endpoint]:
    replies: list[tuple[int, str]] = []
    received: list[InputRequest] = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:
            data = self.rfile.read(int(self.headers["Content-Length"]))
            received.append(InputRequest.model_validate_json(data))
            status, text = replies[min(len(received) - 1, len(replies) - 1)]
            payload = text.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            _ = self.wfile.write(payload)

        @override
        def log_message(self, format: str, *args: str) -> None:
            return

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01})
        thread.start()
        try:
            yield Endpoint(f"http://127.0.0.1:{server.server_port}/v1", replies, received)
        finally:
            server.shutdown()
            thread.join(timeout=5)
