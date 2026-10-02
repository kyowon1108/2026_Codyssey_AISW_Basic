"""Conservative file exclusion and text redaction for outgoing context."""

import re
from pathlib import PurePosixPath
from typing import Final

PATTERNS: Final = (
    r"sk-[A-Za-z0-9_-]{12,}",
    r"(?:AKIA|ASIA)[A-Z0-9]{16}",
    r"gh[pousr]_[A-Za-z0-9]{20,}",
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}",
    r"(?is)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
    r"(?im)(?:api[_-]?key|secret|password|token)\s*[=:]\s*[^\r\n]+",
)


def redact(text: str) -> str:
    """Mask common credentials, assignments, private keys, and email addresses."""
    for pattern in PATTERNS:
        text = re.sub(pattern, "[REDACTED]", text)
    return text


def allowed_file(path: str) -> bool:
    """Exclude credential files before their diff is collected."""
    parts = PurePosixPath(path).parts
    name = PurePosixPath(path).name.lower()
    return not (
        any(part.lower() in {".aws", ".ssh", ".git", ".venv"} for part in parts)
        or name == ".env"
        or name.startswith(".env.")
        or name in {"credentials", "credentials.json", "id_rsa", "id_ed25519"}
        or name.endswith((".pem", ".key", ".p12", ".pfx"))
    )
