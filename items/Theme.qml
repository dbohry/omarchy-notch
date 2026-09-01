import QtQuick

// Shared colors + helpers. Instantiate as `Theme { id: theme }` from any
// items/*.qml file.
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

  function severityColor(pct) {  // green/amber/red for 0..1 utilization
    if (pct >= 0.9) return "#e05d5d"
    if (pct >= 0.6) return "#e0c93e"
    return "#3ecf6e"
  }

  function rankColor(accent, rank) {  // progressively darker shades of accent
    if (rank === 0) return accent
    if (rank === 1) return Qt.darker(accent, 1.5)
    return Qt.darker(accent, 2.2)
  }
}
