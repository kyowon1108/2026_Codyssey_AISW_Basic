# /// script
# requires-python = ">=3.10"
# dependencies = ["typer>=0.16,<1", "pydantic>=2.11,<3", "httpx2[http2,brotli,zstd]>=2.13,<3"]
# ///
# How to run: from a Git root, uv run /absolute/path/to/B3-2/main.py commit
"""Launch the assignment CLI from any Git repository root."""

from gitgen.cli import app

if __name__ == "__main__":
    app()
