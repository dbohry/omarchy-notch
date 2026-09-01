import QtQuick

// Card title plus the big "42% / Memory in use" hero row, with optional
// faint right-aligned notes (clock speed, load averages, ...).
Column {
  id: root
  property string title: ""
  property string value: ""
  property string caption: ""
  property var notes: []

  spacing: 10

  Theme { id: theme }

  Text {
    text: root.title
    color: theme.textPrimary
    font.pixelSize: 14
    font.bold: true
  }

  Item {
    width: parent.width
    height: 40

    Column {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: 0
      Text {
        text: root.value
        color: theme.textPrimary
        font.pixelSize: 30
        font.bold: true
      }
      Text {
        text: root.caption
        color: theme.textMuted
        font.pixelSize: 11
      }
    }
    Column {
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: 2
      Repeater {
        model: root.notes
        Text {
          anchors.right: parent.right
          text: modelData
          color: theme.textFaint
          font.pixelSize: 11
        }
      }
    }
  }
}
