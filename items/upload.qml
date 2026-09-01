import QtQuick
import Quickshell
import Quickshell.Io

// Polls bin/notch-network-stats independently of items/download.qml (see
// that file's comment) -- two cheap process spawns instead of sharing
// state between two otherwise-unrelated items.
Item {
  id: root
  visible: false

  property string itemId: ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/plugins/notch"

  readonly property color uploadColor: "#ec407a"

  property real txRate: 0
  property bool ready: false

  readonly property bool available: true
  readonly property real percent: 0
  readonly property bool known: root.ready
  readonly property bool showArc: false
  readonly property color ringColor: root.uploadColor

  function formatRate(bytesPerSec) {
    if (bytesPerSec < 1024) return Math.round(bytesPerSec) + "B/s"
    if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + "K/s"
    return (bytesPerSec / (1024 * 1024)).toFixed(1) + "M/s"
  }

  readonly property string bottomLabel: root.known ? root.formatRate(root.txRate) : "--"

  Process {
    id: statsProcess
    command: [root.pluginDir + "/bin/notch-network-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        if (parts.length !== 2) return
        root.txRate = parseFloat(parts[1]) || 0
        root.ready = true
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statsProcess.running) statsProcess.running = true
  }

  readonly property Component ringContent: Component {
    Text {
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: "↑"
      color: root.ringColor
      font.pixelSize: parent.height * 0.4
      font.bold: true
    }
  }

  readonly property Component cardContent: null
}
