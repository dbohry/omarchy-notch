import QtQuick
import Quickshell
import Quickshell.Io

// Generic fallback for any configured id that isn't a more specific
// items/*.qml file -- one instance per agent id (claude, codex,
// fireworks, or any future id omarchy.agents writes a usage record for).
// Watches its own usage record; no host-level registry involved.
Item {
  id: root
  visible: false

  property string itemId: ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string assetsDir: "/usr/share/omarchy/shell/plugins/agents/assets"

  readonly property var iconFor: ({ "claude": "claude.svg", "codex": "codex.svg", "fireworks": "fireworks.svg" })
  readonly property var colorFor: ({ "claude": "#e8622c", "codex": "#3ecf6e", "fireworks": "#e0c93e" })
  readonly property var displayNameFor: ({ "claude": "Claude", "codex": "Codex", "fireworks": "Fireworks" })

  property var record: null

  readonly property bool available: root.record !== null
  readonly property string agentName: (root.record && root.record.name) || root.itemId
  readonly property string displayName: root.displayNameFor[root.itemId] || root.agentName
  readonly property var limits: (root.record && Array.isArray(root.record.limits)) ? root.record.limits : []
  readonly property real percent: root.limits.length > 0 ? Math.max(0, Math.min(1, root.limits[0].percent || 0)) : 0
  readonly property bool known: root.limits.length > 0
  readonly property bool showArc: true
  readonly property color ringColor: root.colorFor[root.itemId] || "#8a8a8a"
  readonly property string icon: root.assetsDir + "/" + (root.iconFor[root.itemId] || (root.itemId + ".svg"))
  readonly property string bottomLabel: root.known ? (Math.round(root.percent * 100) + "%") : "--"

  function severityColor(pct) {
    if (pct >= 0.9) return "#e05d5d"
    if (pct >= 0.6) return "#e0c93e"
    return "#3ecf6e"
  }

  function formatResetTime(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    return Qt.formatDateTime(d, "ddd h:mm AP")
  }

  FileView {
    path: root.itemId ? (root.usageDir + "/" + root.itemId + ".json") : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.record = JSON.parse(String(text() || ""))
      } catch (e) {
        console.warn("notch", "bad usage record", root.itemId, e)
        root.record = null
      }
    }
    onLoadFailed: root.record = null
  }

  readonly property Component ringContent: Component {
    Image {
      anchors.centerIn: parent
      width: parent.width * 0.42
      height: width
      source: "file://" + root.icon
      fillMode: Image.PreserveAspectFit
    }
  }

  readonly property int cardWidth: 220

  readonly property Component cardComponentImpl: Component {
    Column {
      id: cardColumn
      width: parent.width
      spacing: 10

      Theme { id: theme }

      Row {
        spacing: 8
        Image {
          source: "file://" + root.icon
          width: 18
          height: 18
          anchors.verticalCenter: parent.verticalCenter
          fillMode: Image.PreserveAspectFit
        }
        Text {
          text: root.displayName + " Usage"
          color: theme.textPrimary
          font.pixelSize: 14
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Repeater {
        model: root.limits.slice(0, 2)

        Column {
          width: cardColumn.width
          spacing: 4

          Item {
            width: parent.width
            height: 16
            Text {
              anchors.left: parent.left
              text: modelData.label || ""
              color: theme.textSecondary
              font.pixelSize: 11
            }
            Text {
              anchors.right: parent.right
              text: root.formatResetTime(modelData.resetsAt) ? ("Resets " + root.formatResetTime(modelData.resetsAt)) : ""
              color: theme.textMuted
              font.pixelSize: 10
            }
          }

          Rectangle {
            width: parent.width
            height: 6
            radius: 3
            color: theme.trackBg
            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, modelData.percent || 0))
              height: parent.height
              radius: 3
              color: root.severityColor(modelData.percent || 0)
            }
          }

          Text {
            text: Math.round((modelData.percent || 0) * 100) + "% Used"
            color: theme.textSecondary
            font.pixelSize: 11
          }
        }
      }
    }
  }

  readonly property Component cardContent: root.limits.length > 0 ? root.cardComponentImpl : null
}
