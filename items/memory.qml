import QtQuick
import Quickshell
import Quickshell.Io

// Polls bin/notch-resource-stats independently of items/cpu.qml (see
// that file's comment) -- two cheap process spawns instead of sharing
// state between two otherwise-unrelated items.
Item {
  id: root
  visible: false

  property string itemId: ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/plugins/notch"

  readonly property color memoryColor: "#26c6a2"

  property real memPercent: 0
  property real memTotalKb: 0
  property real memAvailKb: 0
  property real swapTotalKb: 0
  property real swapFreeKb: 0
  property var topProcesses: []
  property real otherPercent: 0
  property bool ready: false
  // RAM speed is fixed for the boot, so this is looked up once, not on
  // the 3s poll. inxi is an optional package -- notch-resource-stats
  // deliberately avoids extra deps, so a missing binary just leaves the
  // label blank.
  property string speedLabel: ""

  readonly property bool available: true
  readonly property real percent: root.memPercent / 100
  readonly property bool known: root.ready
  readonly property bool showArc: true
  readonly property color ringColor: root.memoryColor
  readonly property string bottomLabel: root.known ? (Math.round(root.memPercent) + "%") : "--"

  readonly property real usedGb: (root.memTotalKb - root.memAvailKb) / 1048576
  readonly property real totalGb: root.memTotalKb / 1048576
  readonly property real swapUsedGb: (root.swapTotalKb - root.swapFreeKb) / 1048576
  readonly property real swapTotalGb: root.swapTotalKb / 1048576
  readonly property real swapPercent: root.swapTotalKb > 0 ? (root.swapTotalKb - root.swapFreeKb) / root.swapTotalKb : 0

  function severityColor(pct) {
    if (pct >= 0.9) return "#e05d5d"
    if (pct >= 0.6) return "#e0c93e"
    return "#3ecf6e"
  }

  function segmentColor(rank) {
    if (rank === 0) return root.memoryColor
    if (rank === 1) return Qt.darker(root.memoryColor, 1.5)
    return Qt.darker(root.memoryColor, 2.2)
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
        root.memPercent = parseFloat(parts[1]) || 0
        root.memTotalKb = parseFloat(parts[6]) || 0
        root.memAvailKb = parseFloat(parts[7]) || 0
        root.swapTotalKb = parseFloat(parts[8]) || 0
        root.swapFreeKb = parseFloat(parts[9]) || 0
        root.ready = true

        var top = []
        var other = 0
        var inMem = false
        for (var i = 1; i < lines.length; i++) {
          var line = lines[i]
          if (!line) continue
          if (line === "---MEM---") { inMem = true; continue }
          if (!inMem) continue
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

  Process {
    running: true
    command: ["inxi", "-m", "-c0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = String(text || "").match(/speed:\s*([0-9]+)\s*MT\/s/i)
        root.speedLabel = m ? (m[1] + " MT/s") : ""
      }
    }
  }

  readonly property Component ringContent: Component {
    Text {
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: "MEM"
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
          text: "Memory"
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
            text: "Memory in use"
            color: theme.textMuted
            font.pixelSize: 11
          }
        }
        Text {
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.speedLabel
          color: theme.textFaint
          font.pixelSize: 11
        }
      }

      Column {
        width: cardColumn.width
        spacing: 8

        Item {
          width: parent.width
          height: 16
          Text {
            anchors.left: parent.left
            text: "Used"
            color: theme.textSecondary
            font.pixelSize: 11
          }
          Text {
            anchors.right: parent.right
            text: root.usedGb.toFixed(1) + " / " + root.totalGb.toFixed(1) + " GB"
            color: theme.textPrimary
            font.pixelSize: 11
          }
        }
        Rectangle {
          width: parent.width
          height: 6
          radius: 3
          color: theme.trackBg
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.percent))
            height: parent.height
            radius: 3
            color: root.severityColor(root.percent)
          }
        }

        Item {
          width: parent.width
          height: 16
          visible: root.swapTotalGb > 0.05
          Text {
            anchors.left: parent.left
            text: "Swap used"
            color: theme.textSecondary
            font.pixelSize: 11
          }
          Text {
            anchors.right: parent.right
            text: root.swapUsedGb.toFixed(1) + " / " + root.swapTotalGb.toFixed(1) + " GB"
            color: theme.textPrimary
            font.pixelSize: 11
          }
        }
        Rectangle {
          visible: root.swapTotalGb > 0.05
          width: parent.width
          height: 6
          radius: 3
          color: theme.trackBg
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.swapPercent))
            height: parent.height
            radius: 3
            color: root.severityColor(root.swapPercent)
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
}
