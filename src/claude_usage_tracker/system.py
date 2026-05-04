"""System path resolvers and diagnostic helpers."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class SecretServiceStatus:
    """Diagnostic snapshot for Linux Secret Service access."""

    available: bool
    available_reason: str
    label_lookup_ok: bool
    label_lookup_detail: str
    application_lookup_ok: bool
    application_lookup_detail: str


def default_browser_root() -> Path:
    """Return the default browser user-data parent directory on Linux."""
    return Path.home() / ".config"


def default_transcript_root() -> Path:
    """Return the default Claude transcript root directory."""
    return Path.home() / ".claude" / "projects"


def secret_service_status() -> SecretServiceStatus:
    """Return a diagnostic snapshot of the secret service and key lookup status."""
    try:
        import secretstorage
    except ImportError:
        return SecretServiceStatus(
            available=False,
            available_reason="secretstorage not installed",
            label_lookup_ok=False,
            label_lookup_detail="secretstorage not installed",
            application_lookup_ok=False,
            application_lookup_detail="secretstorage not installed",
        )

    try:
        connection = secretstorage.dbus_init()
    except Exception as exc:
        return SecretServiceStatus(
            available=False,
            available_reason=f"dbus_init failed: {exc}",
            label_lookup_ok=False,
            label_lookup_detail="service unavailable",
            application_lookup_ok=False,
            application_lookup_detail="service unavailable",
        )

    try:
        available = secretstorage.check_service_availability(connection)
        available_reason = "ok" if available else "service not available"
    except Exception as exc:
        available = False
        available_reason = f"check failed: {exc}"

    if not available:
        try:
            connection.close()
        except Exception:
            pass
        return SecretServiceStatus(
            available=False,
            available_reason=available_reason,
            label_lookup_ok=False,
            label_lookup_detail="service unavailable",
            application_lookup_ok=False,
            application_lookup_detail="service unavailable",
        )

    label_ok = False
    label_detail = ""
    try:
        items = list(secretstorage.search_items(connection, {"label": "Chrome Safe Storage"}))
        if items:
            label_ok = True
            label_detail = f"found {len(items)} item(s)"
        else:
            label_detail = "no items found"
    except Exception as exc:
        label_detail = f"lookup failed: {exc}"

    app_ok = False
    app_detail = ""
    try:
        items = list(secretstorage.search_items(connection, {"application": "chrome"}))
        if items:
            app_ok = True
            app_detail = f"found {len(items)} item(s)"
        else:
            app_detail = "no items found"
    except Exception as exc:
        app_detail = f"lookup failed: {exc}"

    try:
        connection.close()
    except Exception:
        pass

    return SecretServiceStatus(
        available=True,
        available_reason="ok",
        label_lookup_ok=label_ok,
        label_lookup_detail=label_detail,
        application_lookup_ok=app_ok,
        application_lookup_detail=app_detail,
    )
