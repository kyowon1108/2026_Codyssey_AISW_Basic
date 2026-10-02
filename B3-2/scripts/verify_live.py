# /// script
# requires-python = ">=3.10"
# dependencies = ["typer>=0.16,<1", "pydantic>=2.11,<3", "httpx2[http2,brotli,zstd]>=2.13,<3"]
# ///
# How to run: cd B3-2 && uv run python -m scripts.verify_live
"""Exercise both commands against the real API using a disposable Git repository."""

import os
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

from gitgen.git import git


def main() -> None:
    """Keep API credentials in the environment and print only CLI results."""
    source = Path(__file__).resolve().parents[1] / "main.py"
    with TemporaryDirectory(prefix="b3-2-live-") as folder:
        root = Path(folder)
        _ = git(["init", "-q"], root)
        _ = git(["config", "user.name", "B3-2 verification"], root)
        _ = git(["config", "user.email", "verification@example.invalid"], root)
        sample = root / "greeting.py"
        _ = sample.write_text('def greet(name):\n    return "Hello " + name\n', encoding="utf-8")
        _ = git(["add", "greeting.py"], root)
        _ = git(["commit", "-qm", "initial"], root)
        _ = sample.write_text(
            'def greet(name: str) -> str:\n    return f"Hello {name.strip()}"\n',
            encoding="utf-8",
        )
        before = git(["status", "--porcelain=v1"], root)
        for mode in ("commit", "pr"):
            result = subprocess.run(  # noqa: S603 -- own CLI and fixed arguments
                [
                    sys.executable,
                    str(source),
                    mode,
                    "--reason",
                    "입력 이름의 앞뒤 공백 제거",
                    "--requirements",
                    "타입 힌트와 이름 공백 정리 동작을 설명",
                ],
                cwd=root,
                env=os.environ.copy(),
                capture_output=True,
                text=True,
                timeout=100,
                check=False,
            )
            print(f"=== LIVE {mode} / exit={result.returncode} ===")
            print(result.stdout)
            print(result.stderr)
            if result.returncode:
                sys.exit(result.returncode)
        if git(["status", "--porcelain=v1"], root) != before:
            sys.exit("검증 실패: CLI가 Git 상태를 변경했습니다.")
        print("Git 상태 불변: PASS")


if __name__ == "__main__":
    main()
