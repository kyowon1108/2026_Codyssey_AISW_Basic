"""Terminal interface for collecting changes and displaying validated drafts."""

import os
import sys
from pathlib import Path
from typing import Annotated

import typer
from pydantic import SecretStr, ValidationError
from typing_extensions import assert_never

from gitgen.api import generate
from gitgen.git import collect
from gitgen.models import COMMIT_RECOMMENDED, AppError, Context, Mode, Settings, validate_draft
from gitgen.safety import redact

app = typer.Typer(pretty_exceptions_enable=False)


# The public CLI binds individual flags; keeping them explicit provides usable --help.
@app.command()
def run(
    mode: Annotated[Mode, typer.Argument(help="생성할 초안: commit 또는 pr")],
    model: Annotated[str, typer.Option(help="Chat Completions 호환 모델")] = "gpt-5-mini",
    temperature: Annotated[
        float | None, typer.Option(help="온도 (0~2); 기본은 모델 기본값")
    ] = None,
    max_tokens: Annotated[int, typer.Option(help="출력 토큰 한도 (1~32768)")] = 4000,
    safe_mode: Annotated[
        bool, typer.Option("--safe-mode/--raw-mode", help="민감 파일 제외·마스킹")
    ] = True,
    reason: Annotated[str, typer.Option(help="변경 이유")] = "",
    requirements: Annotated[str, typer.Option(help="관련 요구사항 또는 검증할 조건")] = "",
    base_url: Annotated[
        str, typer.Option(help="신뢰하는 OpenAI 호환 API의 v1 URL")
    ] = "https://copa.codyssey.kr/v1",
) -> None:
    """Generate a draft without modifying Git history or remote repositories."""
    try:
        context = collect(
            Path.cwd(),
            Context(status="", diff="", reason=reason, requirements=requirements),
            safe=safe_mode,
        )
        if not context.status:
            print("[INFO] 변경 사항이 없습니다. API 호출: 0회")
            return
        key = os.environ.get("AI_API_KEY") or os.environ.get("OPENAI_API_KEY", "")
        if not key.strip():
            raise AppError("AI_API_KEY 또는 OPENAI_API_KEY 환경변수가 설정되지 않았습니다.")
        settings = Settings(
            model=model,
            temperature=temperature,
            max_tokens=max_tokens,
            api_key=SecretStr(key),
            base_url=base_url,
        )
        print(
            f"[INFO] Git 변경 감지: {len(context.status.splitlines())}개 파일, "
            + f"제외: {context.excluded}개"
        )
        print(
            f"[INFO] 컨텍스트 제한: {'적용' if context.limited else '없음'} "
            + f"/ 안전 모드: {safe_mode}"
        )
        draft, calls = generate(settings, context, mode)
        if safe_mode:
            draft = draft.model_copy(
                update={
                    "summary": redact(draft.summary),
                    "title": redact(draft.title),
                    "body": redact(draft.body),
                }
            )
            draft = validate_draft(draft, mode)
        print(f"[DONE] 생성 및 형식 검증 완료 / API 호출: {calls}회")
        print("\n--- Change Summary ---\n" + draft.summary)
        match mode:
            case Mode.COMMIT:
                if len(draft.title) > COMMIT_RECOMMENDED:
                    print("[INFO] 제목이 권장 길이 50자를 초과합니다 (최대 72자 충족).")
                print("\n--- Commit Message ---\n" + draft.title)
            case Mode.PR:
                print("\n--- PR Title ---\n" + draft.title + "\n\n--- PR Body ---")
            case _:
                assert_never(mode)
        if draft.body:
            print(draft.body)
        print("----------------------\n[INFO] 적용 전에 초안을 검토하세요.")
    except ValidationError as exc:
        print(
            "[ERROR] 옵션 범위를 확인하세요: temperature 0~2, "
            + "max-tokens 1~32768, 맥락 4000자 이내.",
            file=sys.stderr,
        )
        raise typer.Exit(2) from exc
    except (AppError, OSError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise typer.Exit(2) from exc
