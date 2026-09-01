import QtQuick

// CPU ring. Numbers come from the host's shared SysStats poll.
Item {
  id: root
  visible: false

  property string itemId: ""
  property var host: null

  readonly property var stats: root.host ? root.host.sysStats : null
  Component.onCompleted: if (root.stats) root.stats.users++
  Component.onDestruction: if (root.stats) root.stats.users--

  readonly property color accent: "#ff7043"

  readonly property bool available: true
  readonly property bool known: root.stats ? root.stats.ready : false
  readonly property real percent: root.stats ? root.stats.cpuPercent / 100 : 0
  readonly property bool showArc: true
  readonly property color ringColor: root.accent
  readonly property string bottomLabel: root.known ? (Math.round(root.percent * 100) + "%") : "--"

  readonly property string freqLabel: root.stats ? ((root.stats.cpuFreqMhz / 1000).toFixed(2) + " GHz") : ""
  readonly property string loadLabel: root.stats
    ? (root.stats.load1.toFixed(2) + " / " + root.stats.load5.toFixed(2) + " / " + root.stats.load15.toFixed(2))
    : ""

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
      width: parent.width
      spacing: 10

      CardHeader {
        width: parent.width
        title: "CPU"
        value: Math.round(root.percent * 100) + "%"
        caption: "CPU in use"
        notes: [root.freqLabel, root.loadLabel]
      }

      ProcBreakdown {
        width: parent.width
        accent: root.accent
        processes: root.stats ? root.stats.cpuProcesses : []
        otherPercent: root.stats ? root.stats.cpuOther : 0
        fillFraction: root.percent
      }
    }
  }
}
