import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Hover-triggered edge notch: thin idle strip at the top-right corner,
// expands into a column of rings on hover. Generic host only -- every
// ring type lives in its own items/*.qml file, see items/_template.qml
// for the contract.
Item {
  id: root
  visible: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string pluginDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/plugins/notch"
  readonly property string itemsDir: pluginDir + "/items"

  property bool expanded: false

  // Hyprland's fullscreen flag misses borderless-fullscreen windows (a
  // game/video sized to the monitor but not a real xdg-shell fullscreen
  // request), so this also checks geometry. Matters beyond the popup:
  // any visible layer-shell surface here blocks direct-scanout for
  // whatever's fullscreen under it, capping its framerate.
  readonly property var activeToplevel: Hyprland.activeToplevel
  readonly property var activeMonitor: activeToplevel ? activeToplevel.monitor : null
  // Percentage tolerance, not fixed pixels: absorbs gaps_out/border_size
  // insetting a maximized window from the true monitor edge.
  readonly property bool borderlessFullscreen: {
    if (!activeToplevel || !activeMonitor) return false
    var ipc = activeToplevel.lastIpcObject
    if (!ipc || !ipc.size || !ipc.at) return false
    var tolW = activeMonitor.width * 0.03
    var tolH = activeMonitor.height * 0.03
    return Math.abs(ipc.size[0] - activeMonitor.width) <= tolW
      && Math.abs(ipc.size[1] - activeMonitor.height) <= tolH
      && Math.abs(ipc.at[0] - activeMonitor.x) <= tolW
      && Math.abs(ipc.at[1] - activeMonitor.y) <= tolH
  }
  readonly property bool trueFullscreen: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.hasFullscreen
  readonly property bool fullscreenActive: trueFullscreen || borderlessFullscreen
  onFullscreenActiveChanged: if (fullscreenActive) root.expanded = false

  // Quickshell doesn't refresh cached toplevel state on every Hyprland
  // event -- going fullscreen without a focus change left it stale.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      Hyprland.refreshToplevels()
      Hyprland.refreshWorkspaces()
    }
  }

  // Only the open pill scales with size; the collapsed strip below is a
  // fixed edge trigger regardless.
  readonly property var sizePresets: ({
    small:  { ringSize: 38, ringStroke: 3, rowGap: 10, padTop: 10, padBottom: 9,  percentFont: 9 },
    medium: { ringSize: 50, ringStroke: 4, rowGap: 14, padTop: 14, padBottom: 12, percentFont: 11 },
    large:  { ringSize: 64, ringStroke: 5, rowGap: 18, padTop: 18, padBottom: 16, percentFont: 13 }
  })
  property string sizeKey: "medium"
  readonly property var size: sizePresets[sizeKey] || sizePresets.medium

  readonly property int collapsedW: 8
  readonly property int collapsedH: 70
  readonly property int ringSize: size.ringSize
  readonly property int ringStroke: size.ringStroke
  readonly property int rowGap: size.rowGap
  readonly property int pillPadTop: size.padTop
  readonly property int pillPadBottom: size.padBottom
  readonly property int expandedW: ringSize + 26
  // Clears not just the bar but the first ring's hover card above it.
  readonly property int topMargin: 90
  // 0, not a small inset -- a nonzero value reads as nesting against a
  // maximized window's border instead of the monitor's actual edge.
  readonly property int rightMargin: 0

  function defaultItems() {
    return root.agentIds.concat(["weather", "cpu", "memory", "download", "upload"])
  }

  property var configuredItems: defaultItems()

  FileView {
    id: settingsFile
    path: root.pluginDir + "/settings.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySettings(text())
    onLoadFailed: root.configuredItems = root.defaultItems()
  }

  // Same TOML subset shell.toml/colors.toml use elsewhere in Omarchy.
  // Encounter order of `true` entries under [items] becomes render order.
  function applySettings(content) {
    var text = String(content || "")
    var items = []
    var sizeValue = ""
    var section = ""
    var sawItemsSection = false
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/^\s+|\s+$/g, "")
      if (!line || line.charAt(0) === "#") continue
      var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
      if (sectionMatch) {
        section = sectionMatch[1]
        if (section === "items") sawItemsSection = true
        continue
      }
      if (section === "items") {
        var boolKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(true|false)\s*(#.*)?$/)
        if (boolKv && boolKv[2] === "true") items.push(boolKv[1])
      } else if (section === "") {
        // Must appear before any [section] -- TOML sections are sticky
        // to end of file, so "size" after [items] would silently fail.
        var sizeKv = line.match(/^size\s*=\s*["']?([A-Za-z]+)["']?\s*(#.*)?$/)
        if (sizeKv) sizeValue = sizeKv[1]
      }
    }
    root.configuredItems = sawItemsSection ? items : root.defaultItems()
    root.sizeKey = root.sizePresets.hasOwnProperty(sizeValue) ? sizeValue : "medium"
  }

  // Only used to seed defaultItems() when settings.toml has no [items]
  // section yet -- each agent item (items/agent.qml) watches its own
  // usage record independently, this is not a live data registry.
  property var agentIds: []

  Process {
    id: listProcess
    running: true
    command: ["find", root.usageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var ids = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (name.slice(-5) === ".json") ids.push(name.slice(0, -5))
        }
        ids.sort()
        root.agentIds = ids
      }
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: listProcess.running = true
  }

  // id -> absolute file:// url. Unmatched ids fall back to items/agent.qml.
  property var itemTypePaths: ({})
  property bool itemTypesReady: false

  Process {
    id: itemTypesProcess
    running: true
    command: ["find", root.itemsDir, "-maxdepth", "1", "-name", "*.qml"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var map = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var path = lines[i].trim()
          if (!path) continue
          var slash = path.lastIndexOf("/")
          var name = slash === -1 ? path : path.slice(slash + 1)
          if (name.slice(-4) !== ".qml") continue
          if (name.charAt(0) === "_") continue
          if (name === "Theme.qml") continue
          map[name.slice(0, -4)] = "file://" + path
        }
        root.itemTypePaths = map
        root.itemTypesReady = true
      }
    }
  }

  function itemSourceFor(id) {
    if (root.itemTypePaths.hasOwnProperty(id)) return root.itemTypePaths[id]
    if (root.itemTypePaths.hasOwnProperty("agent")) return root.itemTypePaths["agent"]
    return ""
  }

  PanelWindow {
    id: panel
    // Whole surface withdrawn during fullscreen, not just the pill hidden
    // -- see fullscreenActive above for why.
    visible: !root.fullscreenActive
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    WlrLayershell.namespace: "notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Only the pill accepts pointer input; the rest passes clicks through.
    mask: Region {
      item: pill
    }

    Rectangle {
      id: pill
      color: "#111111"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: root.topMargin
      anchors.rightMargin: root.rightMargin
      visible: !root.fullscreenActive
      width: root.fullscreenActive ? 0 : (root.expanded ? root.expandedW : root.collapsedW)
      height: root.fullscreenActive ? 0 : (root.expanded ? (agentColumn.implicitHeight + root.pillPadTop + root.pillPadBottom) : root.collapsedH)
      radius: width / 2  // right side stays flush with the edge, see below
      topRightRadius: 0
      bottomRightRadius: 0

      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      HoverHandler {
        enabled: !root.fullscreenActive
        onHoveredChanged: root.expanded = hovered && !root.fullscreenActive
      }

      Column {
        id: agentColumn
        visible: root.expanded
        opacity: root.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.pillPadTop
        spacing: root.rowGap

        Repeater {
          // Held empty until item discovery finishes so delegates never
          // try to load a source before itemSourceFor() has real data.
          model: root.itemTypesReady ? root.configuredItems : []

          Column {
            id: itemDelegate
            required property string modelData
            spacing: 6

            Loader {
              id: itemLoader
              // Excluded from Column layout (0-size, invisible) -- this
              // only holds the data-provider object, nothing to show.
              visible: false
              Component.onCompleted: setSource(root.itemSourceFor(itemDelegate.modelData), { itemId: itemDelegate.modelData })
            }
            readonly property var itemObj: itemLoader.item
            readonly property bool itemAvailable: !!itemObj && itemObj.available !== false
            visible: itemAvailable

            Item {
              id: ringBox
              width: root.ringSize
              height: root.ringSize
              anchors.horizontalCenter: parent.horizontalCenter

              Shape {
                anchors.fill: parent
                ShapePath {
                  strokeWidth: root.ringStroke
                  strokeColor: "#333333"
                  fillColor: "transparent"
                  capStyle: ShapePath.RoundCap
                  PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: root.ringSize / 2 - root.ringStroke
                    radiusY: root.ringSize / 2 - root.ringStroke
                    startAngle: -90
                    sweepAngle: 360
                  }
                }
              }
              Shape {
                visible: !!itemObj && !!itemObj.showArc
                anchors.fill: parent
                ShapePath {
                  strokeWidth: root.ringStroke
                  strokeColor: itemObj ? itemObj.ringColor : "#8a8a8a"
                  fillColor: "transparent"
                  capStyle: ShapePath.RoundCap
                  PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: root.ringSize / 2 - root.ringStroke
                    radiusY: root.ringSize / 2 - root.ringStroke
                    startAngle: -90
                    sweepAngle: (itemObj && itemObj.known) ? 360 * itemObj.percent : 0
                  }
                }
              }

              Loader {
                anchors.fill: parent
                sourceComponent: itemObj ? itemObj.ringContent : null
              }

              // Separate from the pill-level HoverHandler -- this one
              // only tracks this ring, for its own detail card.
              HoverHandler {
                id: ringHover
                enabled: !!itemObj && !!itemObj.cardContent
              }

              // Positioned left of the ring; not clipped to ringBox's
              // bounds, and not part of the input mask (purely
              // informational, no controls).
              Rectangle {
                id: detailCard
                visible: ringHover.hovered && !!itemObj && !!itemObj.cardContent
                width: itemObj && itemObj.cardWidth ? itemObj.cardWidth : 220
                height: (cardLoader.item ? cardLoader.item.implicitHeight : 0) + 24
                radius: 10
                color: pill.color
                clip: true
                anchors.right: parent.left
                anchors.rightMargin: 26
                anchors.verticalCenter: parent.verticalCenter

                Loader {
                  id: cardLoader
                  anchors.centerIn: parent
                  width: parent.width - 24
                  sourceComponent: itemObj ? itemObj.cardContent : null
                }

                // Rotated square centered on the card's edge: half
                // hidden under the card, half pokes out as a pointer.
                // Must stay a child of detailCard so "parent" resolves
                // to the card.
                Rectangle {
                  width: 16
                  height: 16
                  color: detailCard.color
                  rotation: 45
                  x: parent.width - width / 2
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: itemObj ? itemObj.bottomLabel : ""
              color: "#e6e6e6"
              font.pixelSize: root.size.percentFont
            }
          }
        }
      }
    }
  }
}
