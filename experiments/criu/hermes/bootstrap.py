"""Generate disposable dashboard credentials without logging plaintext."""

import os
import secrets
from pathlib import Path

from plugins.dashboard_auth.basic import hash_password


auth_dir = Path("/auth")
os.umask(0o077)
password = secrets.token_urlsafe(32)
(auth_dir / "password").write_text(password, encoding="utf-8")
(auth_dir / "password_hash").write_text(hash_password(password), encoding="utf-8")
(auth_dir / "signing_key").write_text(secrets.token_urlsafe(48), encoding="utf-8")
