"""Expected errors presented at the command-line boundary."""

from __future__ import annotations


class AppError(Exception):
    """A user-correctable error with an actionable hint."""

    def __init__(self, message: str, hint: str) -> None:
        super().__init__(message)
        self.message = message
        self.hint = hint

    def __str__(self) -> str:
        return self.message


class RecordFormatError(Exception):
    """A decoded JSONL record has the wrong shape or field types."""
