"""CLI command router for claude-usage-tracker."""

import argparse
import json
import shutil
import sys
from pathlib import Path


def _read_json(path: str | Path) -> dict[str, object]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _require_existing_file(path: str | Path, label: str) -> Path:
    resolved = Path(path)
    if not resolved.is_file():
        raise FileNotFoundError(f"{label} not found: {resolved}")
    return resolved


def _require_existing_dir(path: str | Path, label: str) -> Path:
    resolved = Path(path)
    if not resolved.is_dir():
        raise FileNotFoundError(f"{label} not found: {resolved}")
    return resolved


def _handle_render_waybar(fixture_suite: str | None, config: str | None) -> int:
    try:
        if fixture_suite is not None:
            if config is not None:
                _require_existing_file(config, "config")
            suite_path = _require_existing_dir(fixture_suite, "fixture suite")
            payload = _read_json(suite_path / "expected.json")
            sys.stdout.write(json.dumps(payload) + "\n")
            return 0

        from datetime import UTC, datetime

        from claude_usage_tracker import config as config_module
        from claude_usage_tracker.live_session import assemble_render_inputs
        from claude_usage_tracker.render import render_waybar
        from claude_usage_tracker.system import default_browser_root, default_transcript_root

        if config is not None:
            _require_existing_file(config, "config")
            app_config = config_module.load_config(config)
        else:
            app_config = config_module.load_config()

        inputs = assemble_render_inputs(
            config=app_config,
            transcript_root=default_transcript_root(),
            browser_root=default_browser_root(),
        )
        from claude_usage_tracker.notifier import decide_notifications, dispatch
        from claude_usage_tracker.state import load_state, save_state
        from claude_usage_tracker.sync import SyncAuthority

        if (
            inputs.sync is not None
            and inputs.sync.authority is SyncAuthority.FRESH
            and app_config.notifications.enabled
            and not _notifications_suppressed_for_meridian(inputs, app_config)
        ):
            try:
                current_state = load_state()
                notifications, new_state = decide_notifications(
                    sync=inputs.sync,
                    config=app_config,
                    state=current_state,
                    now=datetime.now(UTC),
                )
                for notification in notifications:
                    try:
                        dispatch(notification)
                    except Exception as exc:
                        sys.stderr.write(f"notify: dispatch failed: {exc}\n")
                if new_state is not current_state:
                    save_state(new_state)
            except Exception as exc:
                sys.stderr.write(f"notify: {exc}\n")

        payload = render_waybar(
            sync=inputs.sync,
            breakdowns=inputs.breakdowns,
            error=inputs.error,
            active_meridian_profile=inputs.active_meridian_profile,
        )
        sys.stdout.write(json.dumps(payload) + "\n")
        return 0

    except FileNotFoundError as exc:
        sys.stderr.write(f"render-waybar: {exc}\n")
        return 1
    except Exception as exc:
        import traceback
        from claude_usage_tracker.render import ICON
        sys.stderr.write(traceback.format_exc())
        error_payload = {
            "text": f"{ICON} —",
            "tooltip": f"Internal error: {type(exc).__name__}",
            "class": "error",
        }
        sys.stdout.write(json.dumps(error_payload) + "\n")
        return 0


def _handle_doctor(fixture_suite: str | None, config: str | None) -> int:
    if fixture_suite is not None:
        if config is not None:
            _require_existing_file(config, "config")
        suite_path = _require_existing_dir(fixture_suite, "fixture suite")
        manifest = _read_json(suite_path / "manifest.json")

        if manifest["status"] != "ok":
            sys.stderr.write(f"doctor: {manifest['reason']}\n")
            return 1

        sys.stdout.write(
            "status: ok\n"
            f"browser: {manifest['browser']}\n"
            f"profile: {manifest['profile']}\n"
            f"backend: {manifest['backend']}\n"
        )
        return 0

    from claude_usage_tracker import config as config_module
    from claude_usage_tracker.browser.profiles import ProfileResolutionError, resolve_profile
    from claude_usage_tracker.system import (
        default_browser_root,
        default_transcript_root,
        secret_service_status,
    )

    if config is not None:
        _require_existing_file(config, "config")
        _app_config = config_module.load_config(config)
    else:
        _app_config = config_module.load_config()

    browser_id = "none"
    profile_name = "none"
    profile_resolved = False
    try:
        profile = resolve_profile(default_browser_root(), config_path=None)
        browser_id = profile.browser_id
        profile_name = profile.profile_name
        profile_resolved = True
    except ProfileResolutionError:
        pass

    ss = secret_service_status()

    transcript_root = default_transcript_root()
    transcript_count = (
        len(list(transcript_root.rglob("*.jsonl"))) if transcript_root.is_dir() else 0
    )

    if not profile_resolved or not ss.available:
        status = "fail"
    elif not ss.label_lookup_ok and not ss.application_lookup_ok:
        status = "warn"
    else:
        status = "ok"

    sys.stdout.write(f"status: {status}\n")
    sys.stdout.write(f"browser: {browser_id}\n")
    sys.stdout.write(f"profile: {profile_name}\n")
    sys.stdout.write(f"backend: {'secret-service' if ss.available else 'none'}\n")
    sys.stdout.write(
        f"secret_service_available: {'yes' if ss.available else 'no'} "
        f"({ss.available_reason})\n"
    )
    sys.stdout.write(
        "secret_service_label_lookup: "
        f"{'ok' if ss.label_lookup_ok else 'fail'} ({ss.label_lookup_detail})\n"
    )
    sys.stdout.write(
        "secret_service_application_lookup: "
        f"{'ok' if ss.application_lookup_ok else 'fail'} ({ss.application_lookup_detail})\n"
    )
    sys.stdout.write(f"transcript_root: {transcript_root} ({transcript_count} files)\n")

    return 0 if status in ("ok", "warn") else 1


def _notifications_suppressed_for_meridian(inputs, app_config) -> bool:
    if not app_config.meridian.enabled:
        return False
    if inputs.active_meridian_profile is None:
        return False
    if inputs.resolved_profile_name is None:
        return False

    for profile in app_config.meridian.profiles:
        if profile.meridian_id == inputs.active_meridian_profile:
            return profile.chrome_profile != inputs.resolved_profile_name
    return False


def _handle_settings(config: str, headless_save: str | None) -> int:
    config_path = _require_existing_file(config, "config")
    if not headless_save:
        print("settings: not yet implemented")
        return 0

    save_path = Path(headless_save)
    save_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(config_path, save_path)
    print(f"saved settings to {save_path}")
    return 0


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="claude-usage-tracker",
        description="Linux Waybar widget showing live Claude API usage",
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    render_parser = subparsers.add_parser(
        "render-waybar",
        help="Render Waybar-compatible JSON payload (one-shot)",
    )
    render_parser.add_argument("--fixture-suite", required=False, default=None)
    render_parser.add_argument("--config", required=False, default=None)

    settings_parser = subparsers.add_parser(
        "settings",
        help="Open dedicated settings UI (can also be launched directly)",
    )
    settings_parser.add_argument("--config", required=True)
    settings_parser.add_argument("--headless-save")

    doctor_parser = subparsers.add_parser(
        "doctor",
        help="Validate environment and browser configuration",
    )
    doctor_parser.add_argument("--fixture-suite", required=False, default=None)
    doctor_parser.add_argument("--config", required=False, default=None)

    subparsers.add_parser(
        "settings-gui",
        help="Open notification settings window",
    )

    return parser


def main(argv=None) -> int:
    parser = create_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    if args.command == "render-waybar":
        return _handle_render_waybar(
            getattr(args, "fixture_suite", None),
            getattr(args, "config", None),
        )
    if args.command == "settings":
        return _handle_settings(args.config, args.headless_save)
    if args.command == "doctor":
        return _handle_doctor(
            getattr(args, "fixture_suite", None),
            getattr(args, "config", None),
        )
    if args.command == "settings-gui":
        from claude_usage_tracker.settings_gui import run_settings_gui
        return run_settings_gui()

    return 1
