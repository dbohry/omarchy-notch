import QtQuick
import Quickshell.Io

// Fallback for any configured id with no matching items/*.qml file.
Item {
  id: root
  visible: false

  property string itemId: ""
  property var host: null

  readonly property string assetsDir: "/usr/share/omarchy/shell/plugins/agents/assets"
  // Unlisted ids still work: icon falls back to <id>.svg, color to grey.
  readonly property var known_agents: ({
    claude:    { icon: "claude.svg",    color: "#e8622c", name: "Claude" },
    codex:     { icon: "codex.svg",     color: "#3ecf6e", name: "Codex" },
    fireworks: { icon: "fireworks.svg", color: "#e0c93e", name: "Fireworks" }
  })
  readonly property var meta: root.known_agents[root.itemId] || ({})

  property var record: null

  Component.onCompleted: if (root.host && root.host.agentUsage) root.host.agentUsage.users++
  Component.onDestruction: if (root.host && root.host.agentUsage) root.host.agentUsage.users--

  readonly property bool available: root.record !== null
  readonly property var limits: (root.record && Array.isArray(root.record.limits)) ? root.record.limits : []
  readonly property string displayName: root.meta.name || (root.record && root.record.name) || root.itemId
  readonly property string icon: root.assetsDir + "/" + (root.meta.icon || (root.itemId + ".svg"))

  readonly property real percent: root.limits.length > 0 ? Math.max(0, Math.min(1, root.limits[0].percent || 0)) : 0
  readonly property bool known: root.limits.length > 0
  readonly property bool showArc: true
  readonly property color ringColor: root.meta.color || "#8a8a8a"
  readonly property string bottomLabel: root.known ? (Math.round(root.percent * 100) + "%") : "--"

  function resetLabel(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    return "Resets " + Qt.formatDateTime(d, "ddd h:mm AP")
  }

  FileView {
    path: (root.host && root.itemId) ? (root.host.usageDir + "/" + root.itemId + ".json") : ""
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
    Item {
      Image {
        anchors.centerIn: parent
        width: parent.width * 0.42
        height: width
        sourceSize.width: width
        sourceSize.height: height
        source: "file://" + root.icon
        fillMode: Image.PreserveAspectFit
      }
    }
  }

  readonly property int cardWidth: 220

  readonly property Component cardContent: root.limits.length > 0 ? root.usageCard : null

  readonly property Component usageCard: Component {
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

        LabeledBar {
          width: cardColumn.width
          label: modelData.label || ""
          detail: root.resetLabel(modelData.resetsAt)
          fraction: Math.max(0, Math.min(1, modelData.percent || 0))
          footer: Math.round((modelData.percent || 0) * 100) + "% Used"
        }
      }
    }
  }
}
