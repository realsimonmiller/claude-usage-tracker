"""PySide6 notification settings window for claude-usage-tracker."""
from __future__ import annotations

import sys

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QVBoxLayout,
    QWidget,
)

from claude_usage_tracker.config import Config, NotificationsConfig, load_config, save_config

CANDIDATE_THRESHOLDS = [25, 50, 60, 75, 80, 90, 95]

DARK_STYLE = """
QDialog, QWidget {
    background-color: #181824;
    color: #cdd6f4;
    font-family: 'JetBrainsMono Nerd Font', monospace;
    font-size: 13px;
}
QGroupBox {
    border: 1px solid #45475a;
    border-radius: 6px;
    margin-top: 8px;
    padding-top: 8px;
    color: #cdd6f4;
    font-weight: bold;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 8px;
    padding: 0 4px;
}
QCheckBox {
    spacing: 6px;
    color: #cdd6f4;
}
QCheckBox::indicator {
    width: 16px;
    height: 16px;
    border: 1px solid #6c7086;
    border-radius: 3px;
    background: #1e1e2e;
}
QCheckBox::indicator:checked {
    background: #89b4fa;
    border-color: #89b4fa;
}
QPushButton {
    background-color: #313244;
    color: #cdd6f4;
    border: 1px solid #45475a;
    border-radius: 6px;
    padding: 6px 20px;
    min-width: 80px;
}
QPushButton:hover {
    background-color: #45475a;
}
QPushButton:default {
    background-color: #89b4fa;
    color: #1e1e2e;
    border-color: #89b4fa;
    font-weight: bold;
}
"""


def run_settings_gui() -> int:
    """Open the notification settings window. Returns 0 on success."""
    app = QApplication.instance() or QApplication(sys.argv)
    app.setApplicationName("claude-usage-tracker")

    config = load_config()

    dialog = QDialog()
    dialog.setWindowTitle("Claude Usage — Notifications")
    dialog.setMinimumWidth(380)
    dialog.setStyleSheet(DARK_STYLE)

    layout = QVBoxLayout(dialog)
    layout.setSpacing(12)
    layout.setContentsMargins(16, 16, 16, 16)

    enabled_cb = QCheckBox("Notifications enabled")
    enabled_cb.setChecked(config.notifications.enabled)
    layout.addWidget(enabled_cb)

    def make_threshold_group(
        title: str, current: list[int]
    ) -> tuple[QGroupBox, dict[int, QCheckBox]]:
        group = QGroupBox(title)
        row = QHBoxLayout(group)
        row.setSpacing(8)
        boxes: dict[int, QCheckBox] = {}
        for t in CANDIDATE_THRESHOLDS:
            cb = QCheckBox(f"{t}%")
            cb.setChecked(t in current)
            row.addWidget(cb)
            boxes[t] = cb
        row.addStretch()
        return group, boxes

    block_group, block_boxes = make_threshold_group(
        "5-Hour Block thresholds", config.notifications.block_thresholds
    )
    week_group, week_boxes = make_threshold_group(
        "Weekly Window thresholds", config.notifications.week_thresholds
    )
    layout.addWidget(block_group)
    layout.addWidget(week_group)

    def update_enabled_state() -> None:
        on = enabled_cb.isChecked()
        block_group.setEnabled(on)
        week_group.setEnabled(on)

    enabled_cb.toggled.connect(update_enabled_state)
    update_enabled_state()

    buttons = QDialogButtonBox(
        QDialogButtonBox.StandardButton.Cancel | QDialogButtonBox.StandardButton.Save
    )
    buttons.button(QDialogButtonBox.StandardButton.Save).setDefault(True)
    buttons.accepted.connect(dialog.accept)
    buttons.rejected.connect(dialog.reject)
    layout.addWidget(buttons)

    if dialog.exec() == QDialog.DialogCode.Accepted:
        new_block = sorted(t for t, cb in block_boxes.items() if cb.isChecked())
        new_week = sorted(t for t, cb in week_boxes.items() if cb.isChecked())
        # Ensure at least one threshold if enabling (config validation requires non-empty)
        if not new_block:
            new_block = [50, 75, 90]
        if not new_week:
            new_week = [50, 75, 90]
        new_config = Config(
            browser_mode=config.browser_mode,
            profile_override=config.profile_override,
            refresh_interval_seconds=config.refresh_interval_seconds,
            tooltip=config.tooltip,
            notifications=NotificationsConfig(
                enabled=enabled_cb.isChecked(),
                block_thresholds=new_block,
                week_thresholds=new_week,
            ),
            settings_window=config.settings_window,
            meridian=config.meridian,
        )
        save_config(new_config)

    return 0
