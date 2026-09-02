import QtQuick

// Copy to items/<your-id>.qml (lowercase first letter) and add
// `<your-id> = true` under [items] in ~/.config/notch/settings.toml. No Panel.qml edits
// needed. The host sets `itemId`/`host` and reads the properties below;
// everything else (ring circle, hover, card chrome) is drawn by the host.
Item {
  id: root
  visible: false

  // Set by the host: itemId matches the [items] key in settings. host is
  // the Panel.qml root -- host.pluginDir, host.usageDir, host.expanded,
  // and the shared pollers host.sysStats / host.netStats / host.agentUsage
  // (items/SysStats.qml, items/NetStats.qml, items/AgentUsage.qml), which
  // only run while subscribed:
  //   Component.onCompleted: host.sysStats.users++
  //   Component.onDestruction: host.sysStats.users--
  property string itemId: ""
  property var host: null

  // Read by the host. false hides the ring entirely.
  readonly property bool available: true

  readonly property real percent: 0  // 0..1, only matters if showArc
  readonly property bool known: false  // arc stays flat until true
  readonly property bool showArc: false  // false: draw your own ringContent
  readonly property color ringColor: "#8a8a8a"

  readonly property string bottomLabel: root.itemId  // e.g. "72%", "3°"

  // Must size itself relative to its own parent (ringSize x ringSize) --
  // no access to Panel.qml's properties.
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

  // Hover detail card body; null = no card. Include your own title row --
  // the host draws no chrome. items/ has ready-made pieces to drop in
  // (same-directory types, no import needed): Theme, CardHeader, LabeledBar,
  // ProcBreakdown.
  readonly property Component cardContent: null
  readonly property int cardWidth: 220
}
