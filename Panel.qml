import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "items"

// Hover-triggered edge notch. Ring types live in items/*.qml, see
// items/_template.qml for the contract.
Item {
  id: root
  visible: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string pluginDir: configHome + "/omarchy/plugins/notch"
  readonly property string itemsDir: pluginDir + "/items"
  // Outside pluginDir so a plugin update (git pull / reinstall) never touches it.
  readonly property string userSettingsPath: configHome + "/notch/settings.toml"

  property bool expanded: false

  Theme { id: theme }

  // Handed to items as host.sysStats / host.netStats / host.agentUsage.
  readonly property alias sysStats: sysStatsPoller
  readonly property alias netStats: netStatsPoller
  readonly property alias agentUsage: agentUsagePoller

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
  AgentUsage {
    id: agentUsagePoller
  }

  // Hyprland's fullscreen flag misses borderless-fullscreen windows, so this
  // also checks geometry against a tolerance (absorbs gaps_out/border_size).
  readonly property var activeToplevel: Hyprland.activeToplevel
  readonly property var activeMonitor: activeToplevel ? activeToplevel.monitor : null
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
  onFullscreenActiveChanged: if (fullscreenActive) { root.expanded = false; root.configOpen = false }

  // Quickshell doesn't refresh cached toplevel state on its own; only
  // refresh on events that can change geometry/fullscreen state.
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
  readonly property int topMargin: 90  // clears the first ring's hover card too
  readonly property int rightMargin: 0  // nonzero reads as nested, not flush

  readonly property var defaultItems: ["claude", "weather", "cpu", "memory"]
  property var allItems: []
  readonly property var configuredItems: root.allItems.filter(function(it) { return it.enabled }).map(function(it) { return it.id })

  property string defaultsContent: ""
  property bool defaultsLoaded: false
  property bool userSettingsMissing: false

  FileView {
    id: defaultsFile
    path: root.pluginDir + "/settings.default.toml"
    printErrors: false
    onLoaded: {
      root.defaultsContent = text()
      root.defaultsLoaded = true
      if (root.userSettingsMissing) root.applySettings(root.defaultsContent)
    }
  }

  FileView {
    id: settingsFile
    path: root.userSettingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.userSettingsMissing = false
      root.applySettings(text())
    }
    onLoadFailed: {
      root.userSettingsMissing = true
      root.applySettings(root.defaultsLoaded ? root.defaultsContent : "")
    }
  }

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
        if (boolKv) items.push({ id: boolKv[1], enabled: boolKv[2] === "true" })
      } else if (section === "") {
        // size= must appear before any [section] -- TOML sections are sticky.
        var sizeKv = line.match(/^size\s*=\s*["']?([A-Za-z]+)["']?\s*(#.*)?$/)
        if (sizeKv) sizeValue = sizeKv[1]
      }
    }
    root.allItems = sawItemsSection ? items : root.defaultItems.map(function(id) { return { id: id, enabled: true } })
    root.sizeKey = root.sizePresets.hasOwnProperty(sizeValue) ? sizeValue : "medium"
    root.mergeDiscoveredItems()
  }

  function mergeDiscoveredItems() {
    if (!root.itemTypesReady) return
    var known = {}
    for (var i = 0; i < root.allItems.length; i++) known[root.allItems[i].id] = true
    var extra = []
    var ids = Object.keys(root.itemTypePaths)
    for (var j = 0; j < ids.length; j++) {
      // "agent" is the fallback template, not a selectable item on its own.
      if (ids[j] === "agent" || known[ids[j]]) continue
      extra.push({ id: ids[j], enabled: false })
    }
    if (extra.length > 0) root.allItems = root.allItems.concat(extra)
  }

  property bool configOpen: false
  // pillHover.hovered doesn't change when configOpen toggles on its own
  // (e.g. clicking the gear while already hovering), so re-derive here too.
  onConfigOpenChanged: root.expanded = (pillHover.hovered || root.configOpen) && !root.fullscreenActive
  property string pendingSettingsText: ""

  // Trigger line is the rings' bottom edge, not pill.height -- that also
  // changes when revealed, and anchoring the trigger to it would flicker.
  readonly property real gearRevealZone: 34
  readonly property real contentBottom: root.size.padTop + itemColumn.implicitHeight
  readonly property bool gearNearBottom: pillHover.hovered && pillHover.point.position.y > (root.contentBottom - root.gearRevealZone)
  readonly property bool gearRevealed: root.gearNearBottom || root.configOpen

  function toggleItem(id) {
    root.allItems = root.allItems.map(function(it) {
      return it.id === id ? { id: it.id, enabled: !it.enabled } : it
    })
    root.persistSettings()
  }

  function moveItem(id, delta) {
    var idx = -1
    for (var i = 0; i < root.allItems.length; i++) if (root.allItems[i].id === id) { idx = i; break }
    var swapIdx = idx + delta
    if (idx < 0 || swapIdx < 0 || swapIdx >= root.allItems.length) return
    var copy = root.allItems.slice()
    var tmp = copy[idx]
    copy[idx] = copy[swapIdx]
    copy[swapIdx] = tmp
    root.allItems = copy
    root.persistSettings()
  }

  function setSizeKey(key) {
    if (!root.sizePresets.hasOwnProperty(key)) return
    root.sizeKey = key
    root.persistSettings()
  }

  function persistSettings() {
    var lines = ["size = \"" + root.sizeKey + "\"", "", "[items]"]
    for (var i = 0; i < root.allItems.length; i++) {
      lines.push(root.allItems[i].id + " = " + (root.allItems[i].enabled ? "true" : "false"))
    }
    var text = lines.join("\n") + "\n"
    if (root.userSettingsMissing) {
      // First write: the file (and maybe ~/.config/notch itself) doesn't
      // exist yet -- make sure the directory is there before writing.
      root.pendingSettingsText = text
      mkdirProcess.running = true
    } else {
      root.writeSettingsText(text)
    }
  }

  function writeSettingsText(text) {
    settingsFile.setText(text)
    root.userSettingsMissing = false
    // Apply immediately rather than waiting on the file-watch round trip --
    // that watch has proven unreliable for this path.
    root.applySettings(text)
  }

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.configHome + "/notch"]
    onExited: root.writeSettingsText(root.pendingSettingsText)
  }

  // id -> absolute file:// url. Unmatched ids fall back to items/agent.qml.
  property var itemTypePaths: ({})
  property bool itemTypesReady: false
  onItemTypesReadyChanged: root.mergeDiscoveredItems()

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
          // Lowercase = item; capitalized = shared helper type (Theme, ...).
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

  Timer {
    id: panelRecreateTimer
    interval: 300
    onTriggered: {
      panelLoader.active = false
      Qt.callLater(function() { panelLoader.active = true })
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() { panelRecreateTimer.restart() }
  }

  Loader {
    id: panelLoader
    active: true
    sourceComponent: panelComponent
  }

  Component {
    id: panelComponent

  PanelWindow {
    id: panel
    visible: !root.fullscreenActive
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    WlrLayershell.namespace: "notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Unlike the hover-only detail cards below, the popover needs real
    // clicks -- collapses to 0x0 when closed, so it's a no-op mask then.
    mask: Region {
      Region { item: pill }
      Region { item: settingsPanel.popover }
    }

    Rectangle {
      id: pill
      color: theme.cardBg
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: root.topMargin
      anchors.rightMargin: root.rightMargin
      width: root.expanded ? root.expandedW : root.collapsedW
      height: root.expanded
        ? (root.contentBottom + root.size.padBottom + (root.gearRevealed ? (root.size.rowGap + settingsPanel.glyphSize) : 0))
        : root.collapsedH
      radius: width / 2  // right side stays flush with the screen edge
      topRightRadius: 0
      bottomRightRadius: 0

      Behavior on width { NumberAnimation { duration: 160; easing.type: root.expanded ? Easing.OutCubic : Easing.InCubic } }
      Behavior on height { NumberAnimation { duration: 160; easing.type: root.expanded ? Easing.OutCubic : Easing.InCubic } }

      HoverHandler {
        id: pillHover
        enabled: !root.fullscreenActive
        // Stay expanded while the settings popover is open, even once the
        // pointer leaves the pill for the popover (outside pill's bounds).
        onHoveredChanged: root.expanded = (hovered || root.configOpen) && !root.fullscreenActive
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
          // Empty until discovery finishes, so no delegate loads a bad source.
          model: root.itemTypesReady ? root.configuredItems : []

          Column {
            id: itemDelegate
            required property string modelData
            spacing: 6
            visible: !!itemObj && itemObj.available !== false

            Loader {
              id: itemLoader
              visible: false  // data-provider only, nothing to show
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

              HoverHandler {
                id: ringHover
                enabled: !!itemObj && !!itemObj.cardContent
              }

              // Not part of the input mask -- informational only.
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

                // Must stay a child of detailCard so "parent" resolves right.
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

      // Sibling of itemColumn, not a child -- pill.height above only
      // reserves its slot while revealed, so resizing the pill is the slide.
      SettingsPanel {
        id: settingsPanel
        visible: root.expanded
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.size.padBottom
        host: root
      }
    }
  }

  }
}
