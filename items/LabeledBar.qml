import QtQuick

// Labeled progress bar with an optional footer line.
Column {
  id: root
  property string label: ""
  property string detail: ""  // right-aligned on the label row
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
