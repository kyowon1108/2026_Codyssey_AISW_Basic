"""Typed boundaries for API settings, Git context, and generated drafts."""

import re
from enum import Enum
from typing import Annotated, ClassVar, Final
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator
from typing_extensions import assert_never

SECTIONS: Final = ("Why", "What", "How to Test")
COMMIT_RECOMMENDED: Final = 50


class AppError(Exception):
    """An expected failure suitable for a concise CLI error."""


class Mode(str, Enum):
    """Supported generation tasks."""

    COMMIT = "commit"
    PR = "pr"


class Settings(BaseModel):
    """Validated API controls shared by the CLI and REST adapter."""

    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, strict=True)
    model: Annotated[str, Field(min_length=1)] = "gpt-5-mini"
    temperature: Annotated[float, Field(ge=0, le=2, allow_inf_nan=False)] | None = None
    max_tokens: Annotated[int, Field(ge=1, le=32768)] = 4000
    api_key: SecretStr
    base_url: str = "https://copa.codyssey.kr/v1"

    @field_validator("base_url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        """Allow HTTPS providers or a loopback HTTP integration-test server."""
        url = urlsplit(value)
        secure = url.scheme == "https" or (
            url.scheme == "http" and url.hostname in {"127.0.0.1", "localhost", "::1"}
        )
        if (
            not secure
            or not url.hostname
            or url.username
            or url.password
            or url.query
            or url.fragment
        ):
            raise AppError("base-url은 인증정보·쿼리가 없는 HTTPS 주소여야 합니다.")
        return value.rstrip("/")


class Context(BaseModel):
    """A bounded snapshot of changes and user-supplied intent."""

    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    status: str
    diff: str
    reason: Annotated[str, Field(max_length=4000)]
    requirements: Annotated[str, Field(max_length=4000)]
    limited: bool = False
    excluded: int = 0


class Draft(BaseModel):
    """Machine-readable output; prose is validated separately by mode."""

    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, strict=True, extra="forbid")
    summary: Annotated[str, Field(min_length=1, max_length=4000)]
    title: Annotated[str, Field(min_length=1, max_length=4000)]
    body: Annotated[str, Field(max_length=12000)] = ""

    @field_validator("summary", "title", "body")
    @classmethod
    def clean_text(cls, value: str) -> str:
        """Reject terminal control sequences and trim outer whitespace."""
        if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", value):
            raise AppError("AI 응답에 터미널 제어 문자가 포함되어 있습니다.")
        return value.strip()


def validate_draft(draft: Draft, mode: Mode) -> Draft:
    """Enforce title limits and section bullets without inventing prose."""
    limit = 72 if mode is Mode.COMMIT else 80
    if not draft.summary or not draft.title or "\n" in draft.title or "\r" in draft.title:
        raise AppError("요약과 제목은 비어 있을 수 없고 제목은 한 줄이어야 합니다.")
    if len(draft.title) > limit:
        raise AppError(f"제목은 최대 {limit}자여야 합니다.")
    match mode:
        case Mode.COMMIT:
            if draft.body and not re.search(r"(?m)^[-*] \S", draft.body):
                raise AppError("커밋 본문에 핵심 변경 사항 불릿이 필요합니다.")
        case Mode.PR:
            for section in SECTIONS:
                part = re.search(
                    rf"(?m)^## {re.escape(section)}\s*\n(.*?)(?=^## |\Z)",
                    draft.body,
                    re.DOTALL,
                )
                if part is None or not re.search(r"(?m)^[-*] \S", part.group(1)):
                    raise AppError(f"PR 본문에 '## {section}'와 비어 있지 않은 불릿이 필요합니다.")
        case _:
            assert_never(mode)
    return draft
