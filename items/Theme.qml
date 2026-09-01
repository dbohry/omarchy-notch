import QtQuick

// Shared visual constants + color helpers for item authors -- optional, but
// keeps third-party items visually consistent with the built-ins without
// hand-copying hex codes. Instantiate as `Theme { id: theme }` from any
// items/*.qml file (same-directory QML files are visible as types
// automatically, no import needed).
QtObject {
  readonly property color textPrimary: "#f2f2f2"
  readonly property color textSecondary: "#cfcfcf"
  readonly property color textMuted: "#8a8a8a"
  readonly property color textFaint: "#9a9aa5"
  readonly property color cardBg: "#111111"
  readonly property color borderColor: "#45455a"
  readonly property color trackBg: "#333333"
  readonly property color divider: "#2a2a2a"
  readonly property color otherColor: "#555555"

  // Green/amber/red for a 0..1 utilization figure.
  function severityColor(pct) {
    if (pct >= 0.9) return "#e05d5d"
    if (pct >= 0.6) return "#e0c93e"
    return "#3ecf6e"
  }

  // Progressively darker shades of one accent, so a stacked bar segment and
  // its legend row stay visually paired without needing unrelated colors.
  function rankColor(accent, rank) {
    if (rank === 0) return accent
    if (rank === 1) return Qt.darker(accent, 1.5)
    return Qt.darker(accent, 2.2)
  }
}
