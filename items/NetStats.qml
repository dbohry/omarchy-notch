import QtQuick
import Quickshell.Io

// Single shared poll of bin/notch-network-stats, reachable as host.netStats.
Item {
  id: root
  visible: false

  property string pluginDir: ""
  property bool fast: false
  property int users: 0

  property bool ready: false
  property real rxRate: 0
  property real txRate: 0

  Process {
    id: statsProcess
    command: [root.pluginDir + "/bin/notch-network-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        if (parts.length !== 2) return
        root.rxRate = parseFloat(parts[0]) || 0
        root.txRate = parseFloat(parts[1]) || 0
        root.ready = true
      }
    }
  }

  onFastChanged: if (root.fast && root.users > 0 && !statsProcess.running) statsProcess.running = true

  Timer {
    running: root.users > 0
    interval: root.fast ? 3000 : 30000
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statsProcess.running) statsProcess.running = true
  }
}
