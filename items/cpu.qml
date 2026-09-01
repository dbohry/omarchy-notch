import QtQuick
import Quickshell
import Quickshell.Io

// Polls bin/notch-resource-stats independently of items/memory.qml (which
// polls the same script on its own timer) -- two cheap process spawns
// instead of sharing state between two otherwise-unrelated items.
Item {
  id: root
  visible: false

  property string itemId: ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/plugins/notch"

  readonly property color cpuColor: "#ff7043"

  property real cpuPercent: 0
  property real cpuFreqMhz: 0
  property real load1: 0
  property real load5: 0
  property real load15: 0
  // Top 3 processes plus otherPercent for the rest; normalized so they
  // sum close to cpuPercent (see notch-resource-stats).
  property var topProcesses: []
  property real otherPercent: 0
  property bool ready: false

  readonly property bool available: true
  readonly property real percent: root.cpuPercent / 100
  readonly property bool known: root.ready
  readonly property bool showArc: true
  readonly property color ringColor: root.cpuColor
  readonly property string bottomLabel: root.known ? (Math.round(root.cpuPercent) + "%") : "--"

  function severityColor(pct) {
    if (pct >= 0.9) return "#e05d5d"
    if (pct >= 0.6) return "#e0c93e"
    return "#3ecf6e"
  }

  // Progressively darker shades of the accent color, so segment and row
  // stay visually paired without needing 3 unrelated colors.
  function segmentColor(rank) {
    if (rank === 0) return root.cpuColor
    if (rank === 1) return Qt.darker(root.cpuColor, 1.5)
    return Qt.darker(root.cpuColor, 2.2)
  }

  Process {
    id: statsProcess
    command: [root.pluginDir + "/bin/notch-resource-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var parts = (lines[0] || "").trim().split(/\s+/)
        if (parts.length !== 10) return
        root.cpuPercent = parseFloat(parts[0]) || 0
        root.load1 = parseFloat(parts[2]) || 0
        root.load5 = parseFloat(parts[3]) || 0
        root.load15 = parseFloat(parts[4]) || 0
        root.cpuFreqMhz = parseFloat(parts[5]) || 0
        root.ready = true

        var top = []
        var other = 0
        for (var i = 1; i < lines.length; i++) {
          var line = lines[i]
          if (!line || line === "---MEM---") break
          var fields = line.split("\t")
          if (fields.length !== 2) continue
          if (fields[0] === "__OTHER__") {
            other = parseFloat(fields[1]) || 0
          } else {
            top.push({ name: fields[0], percent: parseFloat(fields[1]) || 0 })
          }
        }
        root.topProcesses = top
        root.otherPercent = other
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
      text: "CPU"
      color: "#e6e6e6"
      font.pixelSize: parent.height * 0.24
      font.bold: true
    }
  }

  readonly property int cardWidth: 240

  readonly property Component cardContent: Component {
    Column {
      id: cardColumn
      width: parent.width
      spacing: 10

      Theme { id: theme }

      Row {
        spacing: 8
        Text {
          text: "CPU"
          color: theme.textPrimary
          font.pixelSize: 14
          font.bold: true
        }
      }

      Item {
        width: parent.width
        height: 40
        Column {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          spacing: 0
          Text {
            text: Math.round(root.percent * 100) + "%"
            color: theme.textPrimary
            font.pixelSize: 30
            font.bold: true
          }
          Text {
            text: "CPU in use"
            color: theme.textMuted
            font.pixelSize: 11
          }
        }
        Text {
          id: freqLabel
          anchors.right: parent.right
          anchors.top: parent.top
          text: (root.cpuFreqMhz / 1000).toFixed(2) + " GHz"
          color: theme.textFaint
          font.pixelSize: 11
        }
        Text {
          anchors.right: parent.right
          anchors.top: freqLabel.bottom
          anchors.topMargin: 2
          text: root.load1.toFixed(2) + " / " + root.load5.toFixed(2) + " / " + root.load15.toFixed(2)
          color: theme.textFaint
          font.pixelSize: 11
        }
      }

      Item {
        width: parent.width
        height: 8

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: theme.trackBg
        }
        Row {
          id: segRow
          height: parent.height
          width: parent.width * Math.max(0, Math.min(1, root.percent))
          readonly property real usedSum: {
            var s = root.otherPercent
            for (var i = 0; i < root.topProcesses.length; i++) s += root.topProcesses[i].percent
            return s
          }

          Repeater {
            model: root.topProcesses
            Rectangle {
              width: segRow.usedSum > 0 ? segRow.width * (modelData.percent / segRow.usedSum) : 0
              height: segRow.height
              color: root.segmentColor(index)
            }
          }
          Rectangle {
            visible: root.otherPercent > 0
            width: segRow.usedSum > 0 ? segRow.width * (root.otherPercent / segRow.usedSum) : 0
            height: segRow.height
            color: "#555555"
          }
        }
      }

      // name is the kernel's own truncated comm (15 chars max)
      Column {
        width: parent.width
        spacing: 6

        Repeater {
          model: root.topProcesses
          Item {
            width: parent.width
            height: 16
            Rectangle {
              width: 8
              height: 8
              radius: 2
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: root.segmentColor(index)
            }
            Text {
              anchors.left: parent.left
              anchors.leftMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: "#e6e6e6"
              font.pixelSize: 11
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.percent.toFixed(1) + "%"
              color: "#e6e6e6"
              font.pixelSize: 11
            }
          }
        }

        Item {
          visible: root.otherPercent > 0
          width: parent.width
          height: 16
          Rectangle {
            width: 8
            height: 8
            radius: 2
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: "#555555"
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "Everything else"
            color: "#9a9a9a"
            font.pixelSize: 11
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.otherPercent.toFixed(1) + "%"
            color: "#9a9a9a"
            font.pixelSize: 11
          }
        }
      }
    }
  }
}
