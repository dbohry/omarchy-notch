import QtQuick
import "items"

// Gear button + settings popover: toggle/reorder items, pick pill size.
// Not a ring item -- chrome, so it lives beside Panel.qml rather than under
// items/. Pure presentation; all state lives on `host` (Panel.qml root).
Item {
  id: root
  property var host: null

  Theme { id: theme }

  readonly property int glyphSize: 18
  width: glyphSize
  height: glyphSize

  // host.gearRevealed also drives pill.height, so the pill grows to make
  // room at the same time this fades in.
  readonly property bool revealed: !!root.host && root.host.gearRevealed
  opacity: revealed ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 150 } }

  Text {
    anchors.centerIn: parent
    text: "⚙"
    color: popoverRect.visible ? theme.textPrimary : theme.textMuted
    font.pixelSize: root.glyphSize
  }

  TapHandler {
    enabled: root.revealed
    onTapped: if (root.host) root.host.configOpen = !root.host.configOpen
  }

  readonly property alias popover: popoverRect

  Rectangle {
    id: popoverRect
    visible: !!root.host && root.host.configOpen
    width: visible ? 220 : 0
    height: visible ? (contentColumn.implicitHeight + 24) : 0
    radius: 10
    color: theme.cardBg
    clip: true
    anchors.right: parent.left
    anchors.rightMargin: 26
    anchors.verticalCenter: parent.verticalCenter

    // Must stay a child of popoverRect so "parent" resolves right.
    Rectangle {
      visible: popoverRect.visible
      width: 16
      height: 16
      color: popoverRect.color
      rotation: 45
      x: parent.width - width / 2
      anchors.verticalCenter: parent.verticalCenter
    }

    Column {
      id: contentColumn
      anchors.centerIn: parent
      width: parent.width - 24
      spacing: 10

      Text {
        text: "Settings"
        color: theme.textPrimary
        font.pixelSize: 14
        font.bold: true
      }

      Row {
        width: parent.width
        spacing: 6

        Repeater {
          model: ["small", "medium", "large"]

          Rectangle {
            required property string modelData
            width: (contentColumn.width - 12) / 3
            height: 26
            radius: 6
            color: root.host && root.host.sizeKey === modelData ? theme.borderColor : theme.trackBg

            Text {
              anchors.centerIn: parent
              text: modelData.charAt(0).toUpperCase()
              color: theme.textPrimary
              font.pixelSize: 12
            }

            TapHandler {
              onTapped: if (root.host) root.host.setSizeKey(modelData)
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: theme.divider }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          model: root.host ? root.host.allItems : []

          Row {
            id: itemRow
            required property var modelData
            required property int index
            width: contentColumn.width
            height: 22
            spacing: 6

            Rectangle {
              width: 14
              height: 14
              radius: 3
              anchors.verticalCenter: parent.verticalCenter
              color: itemRow.modelData.enabled ? "#3ecf6e" : "transparent"
              border.color: theme.borderColor
              border.width: 1

              TapHandler {
                onTapped: if (root.host) root.host.toggleItem(itemRow.modelData.id)
              }
            }

            Text {
              text: itemRow.modelData.id
              color: itemRow.modelData.enabled ? theme.textPrimary : theme.textMuted
              font.pixelSize: 12
              width: contentColumn.width - 14 - 26 - 12
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter

              TapHandler {
                onTapped: if (root.host) root.host.toggleItem(itemRow.modelData.id)
              }
            }

            Row {
              spacing: 4
              anchors.verticalCenter: parent.verticalCenter

              Text {
                text: "▲"
                color: itemRow.index > 0 ? theme.textSecondary : theme.divider
                font.pixelSize: 10

                TapHandler {
                  enabled: itemRow.index > 0
                  onTapped: root.host.moveItem(itemRow.modelData.id, -1)
                }
              }

              Text {
                text: "▼"
                color: (root.host && itemRow.index < root.host.allItems.length - 1) ? theme.textSecondary : theme.divider
                font.pixelSize: 10

                TapHandler {
                  enabled: !!root.host && itemRow.index < root.host.allItems.length - 1
                  onTapped: root.host.moveItem(itemRow.modelData.id, 1)
                }
              }
            }
          }
        }
      }
    }
  }
}
