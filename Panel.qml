import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Hover-triggered edge notch. Collapsed: a small pill hugging the top-right
// corner. Hovering it expands a vertical stack of ring meters -- one per AI
// agent usage record already written by omarchy.agents' collectors, plus an
// optional weather ring.
//
// What renders is driven entirely by ~/.config/omarchy/plugins/notch/settings.json:
//
//   { "items": ["claude", "codex", "fireworks", "weather"], "size": "medium" }
//
// "items" is an ordered list (render order = list order), one ring each:
//   - an agent id ("claude" / "codex" / "fireworks" / ...) -- whatever
//     omarchy.agents has written a usage record for
//   - "weather"   the weather ring
//
// An entry with no matching data (an agent id with no usage record yet, or
// an unrecognized string) is silently skipped rather than erroring. Missing
// or unparseable settings.json falls back to every known agent plus weather
// so the notch still does something useful out of the box. Edits hot-reload
// -- no restart needed to see a settings.json change.
//
// "size" is "small" | "medium" | "large" (default "medium" if omitted or
// unrecognized) -- scales ring size, spacing, and the collapsed pill.
Item {
  id: root
  visible: false

  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string assetsDir: "/usr/share/omarchy/shell/plugins/agents/assets"
  readonly property string pluginDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/plugins/notch"

  property bool expanded: false

  // Hyprland's own "fullscreen" flag only fires for a true xdg-shell
  // fullscreen request. Games running borderless-fullscreen (and some
  // browsers' fullscreen video) are just a plain window sized to the
  // monitor, so that flag stays false -- checked with `hyprctl activewindow -j`
  // against a borderless game and it reported "fullscreen": 0. Comparing
  // the active window's geometry to its monitor's resolution catches both
  // cases, and matters beyond hiding the popup: any visible layer-shell
  // surface here, even fully transparent, blocks Hyprland's direct-scanout
  // path for whatever fullscreen client is under it, which is what capped
  // an Overwatch session at ~72fps instead of 144fps with this plugin on.
  readonly property var activeToplevel: Hyprland.activeToplevel
  readonly property var activeMonitor: activeToplevel ? activeToplevel.monitor : null
  // Percentage tolerance, not a fixed pixel count: Omarchy's default
  // gaps_out (10) + border_size (2) inset a merely-maximized window a few
  // px from the true monitor edges on every side, which a tight pixel
  // tolerance missed entirely. 3% of a 3840x2160 monitor is ~115x65px --
  // comfortably absorbs any reasonable gaps/border config while still
  // excluding a normal, non-maximized window.
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

  // Quickshell doesn't refresh a toplevel's cached geometry/fullscreen state
  // for every Hyprland event -- going fullscreen on a window that was
  // already focused (no focus change involved) left lastIpcObject and
  // hasFullscreen stale, so the notch never disappeared for fullscreen
  // video in an already-focused browser tab. Forcing a refresh on every
  // raw IPC event closes that gap.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      Hyprland.refreshToplevels()
      Hyprland.refreshWorkspaces()
    }
  }

  property var agentIds: []
  property var records: ({})

  // "medium" is the size this plugin shipped with -- the numbers below are
  // exactly its old fixed values. "small"/"large" scale everything ring-
  // related by roughly -25%/+30%; position (topMargin/rightMargin) and the
  // collapsed hover strip stay close to constant since those aren't really
  // a "size" the user is choosing, just the edge trigger.
  readonly property var sizePresets: ({
    small:  { ringSize: 38, ringStroke: 3, rowGap: 10, padTop: 10, padBottom: 9,  collapsedW: 8,  collapsedH: 70,  percentFont: 9 },
    medium: { ringSize: 50, ringStroke: 4, rowGap: 14, padTop: 14, padBottom: 12, collapsedW: 10, collapsedH: 90,  percentFont: 11 },
    large:  { ringSize: 64, ringStroke: 5, rowGap: 18, padTop: 18, padBottom: 16, collapsedW: 12, collapsedH: 110, percentFont: 13 }
  })
  property string sizeKey: "medium"
  readonly property var size: sizePresets[sizeKey] || sizePresets.medium

  readonly property int collapsedW: size.collapsedW
  readonly property int collapsedH: size.collapsedH
  readonly property int ringSize: size.ringSize
  readonly property int ringStroke: size.ringStroke
  readonly property int rowGap: size.rowGap
  readonly property int pillPadTop: size.padTop
  readonly property int pillPadBottom: size.padBottom
  readonly property int expandedW: ringSize + 26
  readonly property int topMargin: 46
  readonly property int rightMargin: 10

  readonly property var iconFor: ({ "claude": "claude.svg", "codex": "codex.svg", "fireworks": "fireworks.svg" })
  readonly property var colorFor: ({ "claude": "#e8622c", "codex": "#3ecf6e", "fireworks": "#e0c93e" })

  // ------------------------------------------------------------ settings

  // Every currently-known agent plus weather -- used only when
  // settings.json is missing or unparseable, so the notch still does
  // something useful before it's been configured.
  function defaultItems() {
    return root.agentIds.concat(["weather"])
  }

  property var configuredItems: defaultItems()

  FileView {
    id: settingsFile
    path: root.pluginDir + "/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySettings(text())
    onLoadFailed: root.configuredItems = root.defaultItems()
  }

  function applySettings(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      root.configuredItems = Array.isArray(parsed.items) ? parsed.items : root.defaultItems()
      root.sizeKey = root.sizePresets.hasOwnProperty(parsed.size) ? parsed.size : "medium"
    } catch (e) {
      console.warn("notch", "bad settings.json, using defaults", e)
      root.configuredItems = root.defaultItems()
      root.sizeKey = "medium"
    }
  }

  // ------------------------------------------------------------ agents

  function agentEntry(id) {
    var rec = root.records[id]
    if (!rec) return null
    var percent = 0
    var known = false
    if (Array.isArray(rec.limits) && rec.limits.length > 0) {
      percent = Math.max(0, Math.min(1, rec.limits[0].percent || 0))
      known = true
    }
    return {
      type: "agent",
      id: id,
      name: rec.name || id,
      percent: percent,
      known: known,
      icon: assetsDir + "/" + (iconFor[id] || (id + ".svg")),
      color: colorFor[id] || "#8a8a8a"
    }
  }

  // ----------------------------------------------------------- weather

  property real weatherTempC: NaN
  property string weatherCode: ""
  property bool weatherReady: false
  property string weatherLocationQuery: ""

  readonly property bool weatherKnown: root.weatherReady && !isNaN(root.weatherTempC)
  readonly property bool weatherWanted: root.configuredItems.indexOf("weather") !== -1

  function weatherEmoji(code) {
    var c = parseInt(String(code || "0"), 10)
    if (c === 113) return "☀"           // clear
    if (c === 116) return "⛅"           // partly cloudy
    if (c === 119 || c === 122) return "☁" // cloudy/overcast
    if (c === 143 || c === 248 || c === 260) return "🌫" // fog
    if ([200, 386, 389, 392, 395].indexOf(c) !== -1) return "⛈" // thunder
    if ([182, 185, 281, 284, 311, 314, 317, 320, 329, 332, 335, 338, 350, 362, 365, 371, 374, 377].indexOf(c) !== -1) return "❄" // snow
    if ([176, 179, 227, 230, 263, 266, 293, 296, 299, 302, 305, 308, 323, 326, 353, 356, 359, 368].indexOf(c) !== -1) return "🌧" // rain
    return "⛅"
  }

  function weatherEntry() {
    return {
      type: "weather",
      id: "weather",
      percent: 0,
      known: root.weatherKnown,
      temp: root.weatherKnown ? Math.round(root.weatherTempC) + "°" : "--",
      emoji: root.weatherKnown ? weatherEmoji(root.weatherCode) : "⛅",
      color: "#5db8e8"
    }
  }

  // Reuses the location the built-in weather bar widget already has
  // configured (same file it writes to) so there's no separate location
  // picker to build here -- if it's unset this queries wttr.in with no
  // location, which auto-detects by IP the same way that widget falls back.
  FileView {
    id: weatherLocationFile
    path: home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyWeatherLocation(text())
    onLoadFailed: root.weatherLocationQuery = ""
  }

  function applyWeatherLocation(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      root.weatherLocationQuery = (parsed && typeof parsed.name === "string") ? parsed.name : ""
    } catch (e) {
      root.weatherLocationQuery = ""
    }
  }

  Process {
    id: weatherProcess
    command: ["curl", "-fsS", "--max-time", "5", "https://wttr.in/" + encodeURIComponent(root.weatherLocationQuery) + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var report = JSON.parse(String(text || ""))
          var current = report.current_condition[0]
          root.weatherTempC = parseFloat(current.temp_C)
          root.weatherCode = current.weatherCode
          root.weatherReady = true
        } catch (e) {
          root.weatherReady = false
        }
      }
    }
  }

  function refreshWeather() {
    if (!weatherProcess.running) weatherProcess.running = true
  }

  Timer {
    interval: 900000
    running: root.weatherWanted
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshWeather()
  }

  // ------------------------------------------------------- combined model

  // Walks configuredItems in order, resolving each entry (a specific agent
  // id, or "weather") to at most one ring. Anything unrecognized, or an
  // agent id with no usage record yet, is skipped rather than erroring.
  function itemsModel() {
    var out = []
    for (var i = 0; i < root.configuredItems.length; i++) {
      var key = root.configuredItems[i]
      if (key === "weather") {
        out.push(root.weatherEntry())
      } else {
        var single = root.agentEntry(key)
        if (single) out.push(single)
      }
    }
    return out
  }

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

  Instantiator {
    model: root.agentIds
    delegate: Item {
      id: watcher
      required property var modelData
      visible: false

      FileView {
        path: root.usageDir + "/" + watcher.modelData + ".json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
          try {
            var parsed = JSON.parse(String(text() || ""))
            var next = {}
            for (var k in root.records) next[k] = root.records[k]
            next[watcher.modelData] = parsed
            root.records = next
          } catch (e) {
            console.warn("notch", "bad usage record", watcher.modelData, e)
          }
        }
      }
    }
  }

  PanelWindow {
    id: panel
    // Withdraw the layer-shell surface entirely during fullscreen -- not
    // just the pill's hit region -- so Hyprland has nothing else to
    // composite over the fullscreen client and can keep direct scanout
    // (the path that gets a fullscreen game to full refresh rate). Any
    // visible surface here, even fully transparent, forces the compositor
    // onto the slower composited path for the whole output.
    visible: !root.fullscreenActive
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    WlrLayershell.namespace: "notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Only the pill's bounding box accepts pointer input; everything else
    // in this full-height transparent window passes clicks through.
    mask: Region {
      item: pill
    }

    Rectangle {
      id: pill
      radius: width / 2
      color: "#111111"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: root.topMargin
      anchors.rightMargin: root.rightMargin
      visible: !root.fullscreenActive
      // Collapse to zero size (not just hidden) while a window is fullscreen
      // so the layer-shell mask leaves no hoverable/clickable region there.
      width: root.fullscreenActive ? 0 : (root.expanded ? root.expandedW : root.collapsedW)
      height: root.fullscreenActive ? 0 : (root.expanded ? (agentColumn.implicitHeight + root.pillPadTop + root.pillPadBottom) : root.collapsedH)

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
          model: root.itemsModel()

          Column {
            spacing: 6
            Item {
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
                visible: modelData.type === "agent"
                anchors.fill: parent
                ShapePath {
                  strokeWidth: root.ringStroke
                  strokeColor: modelData.color
                  fillColor: "transparent"
                  capStyle: ShapePath.RoundCap
                  PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: root.ringSize / 2 - root.ringStroke
                    radiusY: root.ringSize / 2 - root.ringStroke
                    startAngle: -90
                    sweepAngle: modelData.known ? 360 * modelData.percent : 0
                  }
                }
              }
              // Same layout for both: an icon centered in the ring, a value
              // below it. Agents get their brand mark and a percent; weather
              // gets a condition emoji and the temperature. Weather's ring
              // stays a static outline since it has no meaningful percent.
              Image {
                visible: modelData.type === "agent"
                source: modelData.type === "agent" ? ("file://" + modelData.icon) : ""
                width: root.ringSize * 0.42
                height: width
                anchors.centerIn: parent
                fillMode: Image.PreserveAspectFit
              }
              // Weather has no svg mark, so its "icon" is the condition
              // emoji, sized to roughly match the agent icons' footprint.
              Text {
                visible: modelData.type === "weather"
                anchors.centerIn: parent
                text: modelData.type === "weather" ? modelData.emoji : ""
                font.pixelSize: root.ringSize * 0.42
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.type === "weather" ? modelData.temp : (modelData.known ? Math.round(modelData.percent * 100) + "%" : "--")
              color: "#e6e6e6"
              font.pixelSize: root.size.percentFont
            }
          }
        }
      }
    }
  }
}
