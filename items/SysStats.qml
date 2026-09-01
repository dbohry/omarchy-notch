import QtQuick
import Quickshell.Io

// Single shared poll of bin/notch-resource-stats. The host owns one instance
// and hands it to items as `host.sysStats`; items/cpu.qml and
// items/memory.qml both read it, so the script's /proc sweep runs once per
// tick instead of once per item.
Item {
  id: root
  visible: false

  property string pluginDir: ""
  // Fast while the pill is open, slow while collapsed -- the rings aren't on
  // screen then, the slow tick only keeps values warm for the next hover.
  property bool fast: false
  // Bumped by each item that reads this (see items/_template.qml). Nothing
  // subscribed means nothing polled, so a disabled item costs nothing.
  property int users: 0

  property bool ready: false

  property real cpuPercent: 0
  property real cpuFreqMhz: 0
  property real load1: 0
  property real load5: 0
  property real load15: 0
  // Top 3 processes as [{name, percent}], plus cpuOther for the rest;
  // normalized so they sum close to cpuPercent (see notch-resource-stats).
  property var cpuProcesses: []
  property real cpuOther: 0

  property real memPercent: 0
  property real memTotalKb: 0
  property real memAvailKb: 0
  property real swapTotalKb: 0
  property real swapFreeKb: 0
  property var memProcesses: []
  property real memOther: 0

  Process {
    id: statsProcess
    command: [root.pluginDir + "/bin/notch-resource-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var head = (lines[0] || "").trim().split(/\s+/)
        if (head.length !== 10) return
        root.cpuPercent = parseFloat(head[0]) || 0
        root.memPercent = parseFloat(head[1]) || 0
        root.load1 = parseFloat(head[2]) || 0
        root.load5 = parseFloat(head[3]) || 0
        root.load15 = parseFloat(head[4]) || 0
        root.cpuFreqMhz = parseFloat(head[5]) || 0
        root.memTotalKb = parseFloat(head[6]) || 0
        root.memAvailKb = parseFloat(head[7]) || 0
        root.swapTotalKb = parseFloat(head[8]) || 0
        root.swapFreeKb = parseFloat(head[9]) || 0

        // Two "<name>\t<pct>" blocks split by a ---MEM--- line, each ending
        // in one __OTHER__ row for everything outside the top 3.
        var cpuTop = [], memTop = [], cpuOther = 0, memOther = 0, inMem = false
        for (var i = 1; i < lines.length; i++) {
          var line = lines[i]
          if (!line) continue
          if (line === "---MEM---") { inMem = true; continue }
          var f = line.split("\t")
          if (f.length !== 2) continue
          var pct = parseFloat(f[1]) || 0
          if (f[0] === "__OTHER__") {
            if (inMem) memOther = pct; else cpuOther = pct
          } else {
            (inMem ? memTop : cpuTop).push({ name: f[0], percent: pct })
          }
        }
        root.cpuProcesses = cpuTop
        root.cpuOther = cpuOther
        root.memProcesses = memTop
        root.memOther = memOther
        root.ready = true
      }
    }
  }

  // Don't make the first hover wait out a slow tick.
  onFastChanged: if (root.fast && root.users > 0 && !statsProcess.running) statsProcess.running = true

  Timer {
    running: root.users > 0
    interval: root.fast ? 3000 : 30000
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statsProcess.running) statsProcess.running = true
  }
}
