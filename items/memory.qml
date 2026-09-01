import QtQuick
import Quickshell.Io

// Memory ring. Usage numbers come from the host's shared SysStats poll; the
// only thing this file fetches itself is the DIMM clock speed, which is fixed
// for the boot and so read once, not on the poll.
Item {
  id: root
  visible: false

  property string itemId: ""
  property var host: null

  readonly property var stats: root.host ? root.host.sysStats : null
  Component.onCompleted: if (root.stats) root.stats.users++
  Component.onDestruction: if (root.stats) root.stats.users--

  readonly property color accent: "#26c6a2"

  readonly property bool available: true
  readonly property bool known: root.stats ? root.stats.ready : false
  readonly property real percent: root.stats ? root.stats.memPercent / 100 : 0
  readonly property bool showArc: true
  readonly property color ringColor: root.accent
  readonly property string bottomLabel: root.known ? (Math.round(root.percent * 100) + "%") : "--"

  readonly property real usedGb: root.stats ? (root.stats.memTotalKb - root.stats.memAvailKb) / 1048576 : 0
  readonly property real totalGb: root.stats ? root.stats.memTotalKb / 1048576 : 0
  readonly property real swapUsedGb: root.stats ? (root.stats.swapTotalKb - root.stats.swapFreeKb) / 1048576 : 0
  readonly property real swapTotalGb: root.stats ? root.stats.swapTotalKb / 1048576 : 0
  readonly property real swapPercent: (root.stats && root.stats.swapTotalKb > 0)
    ? (root.stats.swapTotalKb - root.stats.swapFreeKb) / root.stats.swapTotalKb
    : 0

  // inxi is an optional package -- notch-resource-stats deliberately avoids
  // extra deps, so a missing binary just leaves this label blank.
  property string speedLabel: ""

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
      width: parent.width
      spacing: 10

      CardHeader {
        width: parent.width
        title: "Memory"
        value: Math.round(root.percent * 100) + "%"
        caption: "Memory in use"
        notes: root.speedLabel ? [root.speedLabel] : []
      }

      LabeledBar {
        width: parent.width
        label: "Used"
        detail: root.usedGb.toFixed(1) + " / " + root.totalGb.toFixed(1) + " GB"
        fraction: root.percent
      }

      LabeledBar {
        visible: root.swapTotalGb > 0.05
        width: parent.width
        label: "Swap used"
        detail: root.swapUsedGb.toFixed(1) + " / " + root.swapTotalGb.toFixed(1) + " GB"
        fraction: root.swapPercent
      }

      ProcBreakdown {
        width: parent.width
        accent: root.accent
        processes: root.stats ? root.stats.memProcesses : []
        otherPercent: root.stats ? root.stats.memOther : 0
        fillFraction: root.percent
      }
    }
  }
}
