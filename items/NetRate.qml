import QtQuick

// Shared body of the download/upload rings: same shape, different direction.
Item {
  id: root
  visible: false

  property string itemId: ""
  property var host: null

  property bool upload: false  // false = download, true = upload
  property string glyph: "↓"
  property color ringColor: "#8a8a8a"

  readonly property var stats: root.host ? root.host.netStats : null
  Component.onCompleted: if (root.stats) root.stats.users++
  Component.onDestruction: if (root.stats) root.stats.users--

  readonly property real rate: root.stats ? (root.upload ? root.stats.txRate : root.stats.rxRate) : 0

  readonly property bool available: true
  readonly property bool known: root.stats ? root.stats.ready : false
  readonly property real percent: 0
  readonly property bool showArc: false
  readonly property string bottomLabel: root.known ? root.formatRate(root.rate) : "--"
  readonly property Component cardContent: null

  function formatRate(bytesPerSec) {
    if (bytesPerSec < 1024) return Math.round(bytesPerSec) + "B/s"
    if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + "K/s"
    return (bytesPerSec / (1024 * 1024)).toFixed(1) + "M/s"
  }

  readonly property Component ringContent: Component {
    Text {
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.glyph
      color: root.ringColor
      font.pixelSize: parent.height * 0.4
      font.bold: true
    }
  }
}
