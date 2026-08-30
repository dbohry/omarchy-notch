import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Hover-triggered edge notch. Collapsed: a small pill hugging the top-right
// corner. Hovering it expands a vertical stack of ring meters, one per AI
// agent usage record already written by omarchy.agents' collectors.
Item {
  id: root
  visible: false

  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string assetsDir: "/usr/share/omarchy/shell/plugins/agents/assets"

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

  readonly property int collapsedW: 10
  readonly property int collapsedH: 90
  readonly property int expandedW: 84
  readonly property int ringSize: 60
  readonly property int rowGap: 14
  readonly property int topMargin: 46
  readonly property int rightMargin: 10

  readonly property var iconFor: ({ "claude": "claude.svg", "codex": "codex.svg", "fireworks": "fireworks.svg" })
  readonly property var colorFor: ({ "claude": "#e8622c", "codex": "#3ecf6e", "fireworks": "#e0c93e" })

  function agentModel() {
    var out = []
    for (var i = 0; i < agentIds.length; i++) {
      var id = agentIds[i]
      var rec = records[id]
      if (!rec) continue
      var percent = 0
      var known = false
      if (Array.isArray(rec.limits) && rec.limits.length > 0) {
        percent = Math.max(0, Math.min(1, rec.limits[0].percent || 0))
        known = true
      }
      out.push({
        id: id,
        name: rec.name || id,
        percent: percent,
        known: known,
        icon: assetsDir + "/" + (iconFor[id] || (id + ".svg")),
        color: colorFor[id] || "#8a8a8a"
      })
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

    // Only the notch/pill rectangle accepts pointer input; everything else
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
      height: root.fullscreenActive ? 0 : (root.expanded ? (root.rowGap + (root.ringSize + root.rowGap) * agentColumn.count + 56) : root.collapsedH)

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
        anchors.topMargin: root.rowGap
        spacing: root.rowGap
        property int count: repeater.count

        Repeater {
          id: repeater
          model: root.agentModel()

          Column {
            spacing: 4
            Item {
              width: root.ringSize
              height: root.ringSize
              anchors.horizontalCenter: parent.horizontalCenter

              Shape {
                id: track
                anchors.fill: parent
                ShapePath {
                  strokeWidth: 4
                  strokeColor: "#333333"
                  fillColor: "transparent"
                  capStyle: ShapePath.RoundCap
                  PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: root.ringSize / 2 - 3
                    radiusY: root.ringSize / 2 - 3
                    startAngle: -90
                    sweepAngle: 360
                  }
                }
              }
              Shape {
                anchors.fill: parent
                ShapePath {
                  strokeWidth: 4
                  strokeColor: modelData.color
                  fillColor: "transparent"
                  capStyle: ShapePath.RoundCap
                  PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: root.ringSize / 2 - 3
                    radiusY: root.ringSize / 2 - 3
                    startAngle: -90
                    sweepAngle: modelData.known ? 360 * modelData.percent : 0
                  }
                }
              }
              Image {
                source: "file://" + modelData.icon
                width: root.ringSize * 0.4
                height: width
                anchors.centerIn: parent
                fillMode: Image.PreserveAspectFit
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.known ? Math.round(modelData.percent * 100) + "%" : "--"
              color: "#e6e6e6"
              font.pixelSize: 11
            }
          }
        }

        Rectangle {
          visible: root.expanded
          width: 28
          height: 28
          radius: 14
          color: "#222222"
          anchors.horizontalCenter: parent.horizontalCenter
          Text {
            anchors.centerIn: parent
            text: "⚙"
            color: "#cccccc"
            font.pixelSize: 14
          }
          MouseArea {
            anchors.fill: parent
            onClicked: Quickshell.execDetached(["omarchy-shell", "omarchy.agents", "open"])
          }
        }
      }
    }
  }
}
