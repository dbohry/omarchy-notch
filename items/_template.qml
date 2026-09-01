import QtQuick

// Copy this file to items/<your-id>.qml (no leading underscore -- files
// starting with "_" are ignored by discovery) and add `<your-id> = true`
// under [items] in settings.toml. No changes to Panel.qml needed.
//
// The host loads exactly one instance of this file per configured id that
// doesn't match a more specific items/*.qml file, sets `itemId`, and reads
// the properties below. Everything else (background ring circle, hover
// wiring, card chrome/position, pill expand/collapse) is drawn by the host.
Item {
  id: root
  visible: false

  // Set by the host after load. Matches the key used in
  // settings.toml [items] -- e.g. "weather", or an id the host didn't
  // recognize as a built-in file (falls back to items/agent.qml).
  property string itemId: ""

  // false hides the ring entirely (e.g. no data yet).
  property bool available: true

  // 0..1. Only matters if showArc is true.
  property real percent: 0
  // Arc stays flat at 0 sweep until this is true (e.g. "no data yet").
  property bool known: false
  // Most items draw their own ring content (see ringContent below) and
  // leave the host's progress arc off. Set true to get the arc (like
  // cpu/memory/agent).
  property bool showArc: false
  readonly property color ringColor: "#8a8a8a"

  // Small text under the ring, e.g. "72%" or "3°" or "1.2M/s".
  readonly property string bottomLabel: root.itemId

  // Drawn inside the ring circle (ringSize x ringSize, set by the host).
  // The root element of this Component must size itself relative to its
  // own parent (anchors.fill: parent, then fractions of width/height) --
  // it has no access to Panel.qml's properties.
  readonly property Component ringContent: Component {
    Item {
      anchors.fill: parent
      Text {
        anchors.centerIn: parent
        text: "•"
        color: root.ringColor
        font.pixelSize: parent.height * 0.4
        font.bold: true
      }
    }
  }

  // Hover detail card body. Return null (the default) for no card at all.
  // Width comes from cardWidth; height is this Component's implicitHeight
  // + 24. Include your own title/header row -- the host draws no title.
  readonly property Component cardContent: null
  readonly property int cardWidth: 220
}
