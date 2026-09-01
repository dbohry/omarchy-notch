import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "items"

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

  Theme { id: theme }

  // Shared pollers, handed to items as host.sysStats / host.netStats. Each
  // stays idle until an item subscribes, and only ticks fast while the pill
  // is open -- nothing is on screen when it's closed.
  readonly property alias sysStats: sysStatsPoller
  readonly property alias netStats: netStatsPoller

  SysStats {
    id: sysStatsPoller
    pluginDir: root.pluginDir
    fast: root.expanded
  }
  NetStats {
    id: netStatsPoller
    pluginDir: root.pluginDir
    fast: root.expanded
  }

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
  // event -- going fullscreen without a focus change left it stale. Only
  // the events that can change window geometry or fullscreen state need a
  // refresh; the rest (workspace ticks, mouse crossings) would just be two
  // wasted IPC round-trips.
  readonly property var geometryEvents: ["fullscreen", "activewindow", "activewindowv2",
    "openwindow", "closewindow", "movewindow", "movewindowv2", "resizewindow",
    "changefloatingmode", "workspace", "workspacev2", "focusedmon"]

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.geometryEvents.indexOf(event.name) === -1) return
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
  readonly property int expandedW: size.ringSize + 26
  // Clears not just the bar but the first ring's hover card above it.
  readonly property int topMargin: 90
  // 0, not a small inset -- a nonzero value reads as nesting against a
  // maximized window's border instead of the monitor's actual edge.
  readonly property int rightMargin: 0

  // Only used when settings.toml is missing or has no [items] section.
  readonly property var defaultItems: ["claude", "weather", "cpu", "memory"]
  property var configuredItems: defaultItems

  FileView {
    id: settingsFile
    path: root.pluginDir + "/settings.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySettings(text())
    onLoadFailed: root.configuredItems = root.defaultItems
  }

  // Same TOML subset shell.toml/colors.toml use elsewhere in Omarchy.
  // Encounter order of `true` entries under [items] becomes render order.
  function applySettings(content) {
    var items = []
    var sizeValue = ""
    var section = ""
    var sawItemsSection = false
    var lines = String(content || "").split("\n")
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
    root.configuredItems = sawItemsSection ? items : root.defaultItems
    root.sizeKey = root.sizePresets.hasOwnProperty(sizeValue) ? sizeValue : "medium"
  }

  // id -> absolute file:// url. Unmatched ids fall back to items/agent.qml,
  // which is what makes arbitrary agent ids work with zero registration.
  property var itemTypePaths: ({})
  property bool itemTypesReady: false

  Process {
    running: true
    command: ["find", root.itemsDir, "-maxdepth", "1", "-name", "*.qml"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var map = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var path = lines[i].trim()
          var name = path.slice(path.lastIndexOf("/") + 1, -4)
          // Item ids are lowercase; anything else in items/ is a shared
          // helper type (Theme, SysStats, ...) or the _template.
          if (!path || !/^[a-z]/.test(name)) continue
          map[name] = "file://" + path
        }
        root.itemTypePaths = map
        root.itemTypesReady = true
      }
    }
  }

  function itemSourceFor(id) {
    return root.itemTypePaths[id] || root.itemTypePaths["agent"] || ""
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
      color: theme.cardBg
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: root.topMargin
      anchors.rightMargin: root.rightMargin
      width: root.expanded ? root.expandedW : root.collapsedW
      height: root.expanded ? (itemColumn.implicitHeight + root.size.padTop + root.size.padBottom) : root.collapsedH
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
        id: itemColumn
        visible: root.expanded
        opacity: root.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.size.padTop
        spacing: root.size.rowGap

        Repeater {
          // Held empty until item discovery finishes so delegates never
          // try to load a source before itemSourceFor() has real data.
          model: root.itemTypesReady ? root.configuredItems : []

          Column {
            id: itemDelegate
            required property string modelData
            spacing: 6
            visible: !!itemObj && itemObj.available !== false

            Loader {
              id: itemLoader
              // Excluded from Column layout (0-size, invisible) -- this
              // only holds the data-provider object, nothing to show.
              visible: false
              Component.onCompleted: setSource(root.itemSourceFor(itemDelegate.modelData), {
                itemId: itemDelegate.modelData,
                host: root
              })
            }
            readonly property var itemObj: itemLoader.item

            Item {
              id: ringBox
              width: root.size.ringSize
              height: width
              anchors.horizontalCenter: parent.horizontalCenter

              Ring {
                thickness: root.size.ringStroke
                stroke: theme.trackBg
              }
              Ring {
                visible: !!itemObj && !!itemObj.showArc
                thickness: root.size.ringStroke
                stroke: itemObj ? itemObj.ringColor : theme.textMuted
                fraction: (itemObj && itemObj.known) ? itemObj.percent : 0
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
              color: theme.textPrimary
              font.pixelSize: root.size.percentFont
            }
          }
        }
      }
    }
  }
}
