"""Seed writable upstream configuration without replacing the owner's edits."""

import json
from datetime import datetime, timezone
from pathlib import Path

config = Path("/config")
(config / ".storage").mkdir(exist_ok=True)


def seed(path, content):
    target = config / path
    if not target.exists():
        target.write_text(content, encoding="utf-8")
        target.chmod(0o600)


def store(key, version, minor, data):
    seed(f".storage/{key}", json.dumps({
        "version": version, "minor_version": minor, "key": key, "data": data,
    }))


seed("configuration.yaml", Path("/wonton/configuration.yaml").read_text())
for name, content in [("automations.yaml", "[]\n"), ("scripts.yaml", "{}\n"), ("scenes.yaml", "[]\n")]:
    seed(name, content)

# HA 2026.10 imports YAML HTTP settings as an unconfirmed five-minute trial.
# Seed its stable store instead; do not stage a pending config or edit live storage.
store("http", 2, 2, {
    "stable": {
        "server_host": ["127.0.0.1"], "server_port": 8123,
        "cors_allowed_origins": [], "use_x_forwarded_for": False,
        "trusted_proxies": [], "login_attempts_threshold": -1,
        "ip_ban_enabled": True, "ssl_profile": "modern", "use_x_frame_options": True,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "error": None, "error_message": None,
    },
    "pending": None, "yaml_migration_done": True,
})
store("core.analytics", 1, 1, {
    "onboarded": True, "uuid": None,
    "preferences": {name: False for name in ["base", "diagnostics", "usage", "statistics", "snapshots"]},
})
