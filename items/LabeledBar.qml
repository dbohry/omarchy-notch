import QtQuick

// "Used ............ 5.1 / 16.0 GB" over a severity-colored progress bar,
// with an optional line underneath. Used by the memory and agent cards.
Column {
  id: root
  property string label: ""
  // Right-aligned on the label row (a total, a reset time, ...).
  property string detail: ""
  property real fraction: 0
  property string footer: ""

  spacing: 4

  Theme { id: theme }

  Item {
    width: parent.width
    height: 16
    Text {
      anchors.left: parent.left
      text: root.label
      color: theme.textSecondary
      font.pixelSize: 11
    }
    Text {
      anchors.right: parent.right
      text: root.detail
      color: theme.textMuted
      font.pixelSize: 11
    }
  }

  Rectangle {
    width: parent.width
    height: 6
    radius: 3
    color: theme.trackBg
    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, root.fraction))
      height: parent.height
      radius: 3
      color: theme.severityColor(root.fraction)
    }
  }

  Text {
    visible: root.footer !== ""
    text: root.footer
    color: theme.textSecondary
    font.pixelSize: 11
  }
}
