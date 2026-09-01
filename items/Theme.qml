import QtQuick

// Shared visual constants for item authors -- optional, but keeps
// third-party items visually consistent with the built-ins without
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
}
