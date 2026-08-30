import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Hover-triggered edge notch: a thin idle strip at the top-right corner
// that expands into a column of rings on hover. Driven by settings.toml
// (a hand-rolled TOML subset, see applySettings below) -- see README.md
// for the full config format and what each ring type shows.
Item {
  id: root
  visible: false

  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string assetsDir: "/usr/share/omarchy/shell/plugins/agents/assets"
  readonly property string pluginDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/plugins/notch"

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

  property var agentIds: []
  property var records: ({})

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

  readonly property var iconFor: ({ "claude": "claude.svg", "codex": "codex.svg", "fireworks": "fireworks.svg" })
  readonly property var colorFor: ({ "claude": "#e8622c", "codex": "#3ecf6e", "fireworks": "#e0c93e" })
  readonly property string cpuColor: "#ff7043"
  readonly property string memoryColor: "#26c6a2"

  // ------------------------------------------------------------ settings

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

  // ------------------------------------------------------------ agents

  readonly property var displayNameFor: ({ "claude": "Claude", "codex": "Codex", "fireworks": "Fireworks" })

  // Never returns null -- always a well-formed object, `available: false`
  // for an id with no usage record yet. See entryFor for why that matters.
  function agentEntry(id) {
    var rec = root.records[id]
    if (!rec) {
      return {
        type: "agent",
        id: id,
        available: false,
        name: id,
        displayName: displayNameFor[id] || id,
        percent: 0,
        known: false,
        limits: [],
        icon: assetsDir + "/" + (iconFor[id] || (id + ".svg")),
        color: colorFor[id] || "#8a8a8a"
      }
    }
    var percent = 0
    var known = false
    if (Array.isArray(rec.limits) && rec.limits.length > 0) {
      percent = Math.max(0, Math.min(1, rec.limits[0].percent || 0))
      known = true
    }
    return {
      type: "agent",
      id: id,
      available: true,
      name: rec.name || id,
      displayName: displayNameFor[id] || rec.name || id,
      percent: percent,
      known: known,
      limits: Array.isArray(rec.limits) ? rec.limits : [],
      icon: assetsDir + "/" + (iconFor[id] || (id + ".svg")),
      color: colorFor[id] || "#8a8a8a"
    }
  }

  // Independent of the ring's own brand color -- how close to the limit
  // matters more here than which agent it is.
  function severityColor(percent) {
    if (percent >= 0.9) return "#e05d5d"
    if (percent >= 0.6) return "#e0c93e"
    return "#3ecf6e"
  }

  // Progressively darker shades of the cpu accent color, so segment and
  // row stay visually paired without needing 3 unrelated colors.
  function cpuSegmentColor(rank) {
    if (rank === 0) return root.cpuColor
    if (rank === 1) return Qt.darker(root.cpuColor, 1.5)
    return Qt.darker(root.cpuColor, 2.2)
  }

  function formatResetTime(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    return Qt.formatDateTime(d, "ddd h:mm AP")
  }

  // ----------------------------------------------------------- weather

  property real weatherTempC: NaN
  property real weatherCode: NaN
  property bool weatherIsDay: true
  property real weatherFeelsLikeC: NaN
  property real weatherHumidity: NaN
  property real weatherWindKmph: NaN
  property string weatherWindDir: ""
  // daily.*[0] in the same Open-Meteo response as the forecast (index 0).
  property real weatherTodayMaxC: NaN
  property real weatherTodayMinC: NaN
  // Next 3 days: [{dayLabel, emoji, maxC, minC}, ...]
  property var weatherForecast: []
  property bool weatherReady: false
  property string weatherLocationQuery: ""
  property real weatherLat: NaN
  property real weatherLon: NaN
  property int weatherGeoRetries: 0
  property int weatherOpenMeteoRetries: 0

  readonly property bool weatherKnown: root.weatherReady && !isNaN(root.weatherTempC)
  readonly property bool weatherWanted: root.configuredItems.indexOf("weather") !== -1

  // code is an Open-Meteo WMO weather code. isDay is only passed for the
  // live icon; forecast days omit it (defaults true, no per-day night
  // state). Only clear/partly-cloudy get a night variant.
  function weatherEmoji(code, isDay) {
    var c = parseInt(String(code || "0"), 10)
    var day = isDay === undefined || isDay
    if (c === 0) return day ? "☀" : "🌙"                       // clear
    if (c === 1 || c === 2) return day ? "⛅" : "🌙"            // mainly clear / partly cloudy
    if (c === 3) return "☁"                                   // overcast
    if (c === 45 || c === 48) return "🌫"                      // fog
    if ([51, 53, 55, 56, 57].indexOf(c) !== -1) return "🌦"    // drizzle
    if ([61, 63, 65, 66, 67, 80, 81, 82].indexOf(c) !== -1) return "🌧" // rain / showers
    if ([71, 73, 75, 77, 85, 86].indexOf(c) !== -1) return "❄" // snow
    if ([95, 96, 99].indexOf(c) !== -1) return "⛈"             // thunderstorm
    return "⛅"
  }

  function weatherConditionText(code) {
    var c = parseInt(String(code || "0"), 10)
    if (c === 0) return "Clear"
    if (c === 1 || c === 2) return "Partly cloudy"
    if (c === 3) return "Cloudy"
    if (c === 45 || c === 48) return "Fog"
    if ([51, 53, 55, 56, 57].indexOf(c) !== -1) return "Drizzle"
    if ([61, 63, 65, 66, 67, 80, 81, 82].indexOf(c) !== -1) return "Rain"
    if ([71, 73, 75, 77, 85, 86].indexOf(c) !== -1) return "Snow"
    if ([95, 96, 99].indexOf(c) !== -1) return "Thunderstorm"
    return "Cloudy"
  }

  function degToCompass(deg) {
    var dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    return dirs[Math.round(deg / 22.5) % 16]
  }

  // daily.* are parallel arrays; index 0 is today (shown elsewhere), so
  // this starts at 1 and takes the next 3.
  function parseForecast(daily) {
    if (!daily || !Array.isArray(daily.time)) return []
    var out = []
    for (var i = 1; i < daily.time.length && out.length < 3; i++) {
      var d = new Date(daily.time[i] + "T00:00:00")
      out.push({
        dayLabel: isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, "ddd"),
        emoji: root.weatherEmoji(daily.weather_code[i]),
        maxC: Math.round(daily.temperature_2m_max[i]),
        minC: Math.round(daily.temperature_2m_min[i])
      })
    }
    return out
  }

  function weatherEntry() {
    return {
      type: "weather",
      id: "weather",
      available: true,
      percent: 0,
      known: root.weatherKnown,
      temp: root.weatherKnown ? Math.round(root.weatherTempC) + "°" : "--",
      tempRawC: root.weatherTempC,
      emoji: root.weatherKnown ? weatherEmoji(root.weatherCode, root.weatherIsDay) : "⛅",
      conditionText: root.weatherKnown ? weatherConditionText(root.weatherCode) : "",
      color: "#5db8e8",
      feelsLikeC: root.weatherFeelsLikeC,
      humidity: root.weatherHumidity,
      windKmph: root.weatherWindKmph,
      windDir: root.weatherWindDir,
      todayMaxC: root.weatherTodayMaxC,
      todayMinC: root.weatherTodayMinC,
      forecast: root.weatherForecast
    }
  }

  // Reuses the location the built-in weather bar widget already writes --
  // no separate picker here. Missing/name-only means IP auto-detect.
  FileView {
    id: weatherLocationFile
    path: home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyWeatherLocation(text())
    onLoadFailed: root.applyWeatherLocation("")
  }

  function applyWeatherLocation(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      root.weatherLocationQuery = (parsed && typeof parsed.name === "string") ? parsed.name : ""
      var lat = parsed ? parseFloat(parsed.latitude) : NaN
      var lon = parsed ? parseFloat(parsed.longitude) : NaN
      root.weatherLat = lat
      root.weatherLon = lon
    } catch (e) {
      root.weatherLocationQuery = ""
      root.weatherLat = NaN
      root.weatherLon = NaN
    }
  }

  // wttr.in / open-meteo can be slow or flaky, especially right after
  // waking with the network still down. Retry a few times before leaving
  // it to the 15-minute refresh timer, same approach as the weather plugin.
  function scheduleGeoRetry() {
    if (root.weatherGeoRetries >= 3) return
    root.weatherGeoRetries++
    geoRetryTimer.restart()
  }

  Timer {
    id: geoRetryTimer
    interval: 2500
    onTriggered: if (!geoProcess.running) geoProcess.running = true
  }

  function scheduleOpenMeteoRetry() {
    if (root.weatherOpenMeteoRetries >= 3) return
    root.weatherOpenMeteoRetries++
    openMeteoRetryTimer.restart()
  }

  Timer {
    id: openMeteoRetryTimer
    interval: 2500
    onTriggered: if (!openMeteoProcess.running) openMeteoProcess.running = true
  }

  // Bootstraps lat/lon from wttr.in when weather.json has none configured
  // -- same path the bar widget takes, so the two agree.
  Process {
    id: geoProcess
    command: ["curl", "-fsS", "--max-time", "5", "https://wttr.in/" + encodeURIComponent(root.weatherLocationQuery) + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var report = JSON.parse(String(text || ""))
          var area = report.nearest_area[0]
          root.weatherGeoRetries = 0
          root.fetchOpenMeteo(parseFloat(area.latitude), parseFloat(area.longitude))
        } catch (e) {
          root.scheduleGeoRetry()
        }
      }
    }
  }

  Process {
    id: openMeteoProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var report = JSON.parse(String(text || ""))
          var current = report.current
          root.weatherTempC = parseFloat(current.temperature_2m)
          root.weatherCode = parseFloat(current.weather_code)
          root.weatherIsDay = parseFloat(current.is_day) !== 0
          root.weatherFeelsLikeC = parseFloat(current.apparent_temperature)
          root.weatherHumidity = parseFloat(current.relative_humidity_2m)
          root.weatherWindKmph = parseFloat(current.wind_speed_10m)
          root.weatherWindDir = isNaN(parseFloat(current.wind_direction_10m)) ? "" : root.degToCompass(parseFloat(current.wind_direction_10m))
          root.weatherTodayMaxC = parseFloat(report.daily.temperature_2m_max[0])
          root.weatherTodayMinC = parseFloat(report.daily.temperature_2m_min[0])
          root.weatherForecast = root.parseForecast(report.daily)
          root.weatherReady = true
          root.weatherOpenMeteoRetries = 0
        } catch (e) {
          root.scheduleOpenMeteoRetry()
        }
      }
    }
  }

  function fetchOpenMeteo(lat, lon) {
    if (isNaN(lat) || isNaN(lon)) {
      root.weatherReady = false
      return
    }
    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,weather_code,is_day"
      + "&forecast_days=4&timezone=auto"
    openMeteoProcess.command = ["curl", "-fsS", "--max-time", "5", url]
    openMeteoProcess.running = true
  }

  function refreshWeather() {
    if (geoProcess.running || openMeteoProcess.running) return
    root.weatherGeoRetries = 0
    root.weatherOpenMeteoRetries = 0
    if (!isNaN(root.weatherLat) && !isNaN(root.weatherLon)) {
      root.fetchOpenMeteo(root.weatherLat, root.weatherLon)
    } else {
      geoProcess.running = true
    }
  }

  Timer {
    interval: 900000
    running: root.weatherWanted
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshWeather()
  }

  // -------------------------------------------------------- cpu / memory

  property real cpuPercent: 0
  property real memPercent: 0
  property real cpuFreqMhz: 0
  property real load1: 0
  property real load5: 0
  property real load15: 0
  property real memTotalKb: 0
  property real memAvailKb: 0
  property real swapTotalKb: 0
  property real swapFreeKb: 0
  // Top 3 processes plus cpuOtherPercent for the rest; normalized the
  // same way as cpuPercent, so they sum close to it (see notch-resource-stats).
  property var cpuTopProcesses: []
  property real cpuOtherPercent: 0
  property bool resourcesReady: false

  readonly property bool resourcesWanted: root.configuredItems.indexOf("cpu") !== -1 || root.configuredItems.indexOf("memory") !== -1

  function resourceEntry(id, label, percent, color) {
    return {
      type: "resource",
      id: id,
      available: true,
      label: label,
      percent: percent / 100,
      known: root.resourcesReady,
      color: color
    }
  }

  function cpuEntry() {
    var e = root.resourceEntry("cpu", "CPU", root.cpuPercent, root.cpuColor)
    e.freqMhz = root.cpuFreqMhz
    e.load1 = root.load1
    e.load5 = root.load5
    e.load15 = root.load15
    e.topProcesses = root.cpuTopProcesses
    e.otherPercent = root.cpuOtherPercent
    return e
  }

  function memoryEntry() {
    var e = root.resourceEntry("memory", "MEM", root.memPercent, root.memoryColor)
    e.usedGb = (root.memTotalKb - root.memAvailKb) / 1048576
    e.totalGb = root.memTotalKb / 1048576
    e.swapUsedGb = (root.swapTotalKb - root.swapFreeKb) / 1048576
    e.swapTotalGb = root.swapTotalKb / 1048576
    e.swapPercent = root.swapTotalKb > 0 ? (root.swapTotalKb - root.swapFreeKb) / root.swapTotalKb : 0
    return e
  }

  Process {
    id: resourceProcess
    command: [root.pluginDir + "/bin/notch-resource-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var parts = (lines[0] || "").trim().split(/\s+/)
        if (parts.length === 10) {
          root.cpuPercent = parseFloat(parts[0]) || 0
          root.memPercent = parseFloat(parts[1]) || 0
          root.load1 = parseFloat(parts[2]) || 0
          root.load5 = parseFloat(parts[3]) || 0
          root.load15 = parseFloat(parts[4]) || 0
          root.cpuFreqMhz = parseFloat(parts[5]) || 0
          root.memTotalKb = parseFloat(parts[6]) || 0
          root.memAvailKb = parseFloat(parts[7]) || 0
          root.swapTotalKb = parseFloat(parts[8]) || 0
          root.swapFreeKb = parseFloat(parts[9]) || 0
          root.resourcesReady = true

          var top = []
          var other = 0
          for (var i = 1; i < lines.length; i++) {
            var line = lines[i]
            if (!line) continue
            var fields = line.split("\t")
            if (fields.length !== 2) continue
            if (fields[0] === "__OTHER__") {
              other = parseFloat(fields[1]) || 0
            } else {
              top.push({ name: fields[0], percent: parseFloat(fields[1]) || 0 })
            }
          }
          root.cpuTopProcesses = top
          root.cpuOtherPercent = other
        }
      }
    }
  }

  function refreshResources() {
    if (!resourceProcess.running) resourceProcess.running = true
  }

  Timer {
    interval: 3000
    running: root.resourcesWanted
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshResources()
  }

  // ------------------------------------------------------------- network

  readonly property string downloadColor: "#42a5f5"
  readonly property string uploadColor: "#ec407a"

  property real networkRxRate: 0
  property real networkTxRate: 0
  property bool networkReady: false

  readonly property bool networkWanted: root.configuredItems.indexOf("download") !== -1 || root.configuredItems.indexOf("upload") !== -1

  function formatRate(bytesPerSec) {
    if (bytesPerSec < 1024) return Math.round(bytesPerSec) + "B/s"
    if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + "K/s"
    return (bytesPerSec / (1024 * 1024)).toFixed(1) + "M/s"
  }

  function networkEntry(id, arrow, rate, color) {
    return {
      type: "network",
      id: id,
      available: true,
      label: arrow,
      value: root.networkReady ? root.formatRate(rate) : "--",
      known: root.networkReady,
      color: color
    }
  }

  function downloadEntry() { return root.networkEntry("download", "↓", root.networkRxRate, root.downloadColor) }
  function uploadEntry() { return root.networkEntry("upload", "↑", root.networkTxRate, root.uploadColor) }

  Process {
    id: networkProcess
    command: [root.pluginDir + "/bin/notch-network-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        if (parts.length === 2) {
          root.networkRxRate = parseFloat(parts[0]) || 0
          root.networkTxRate = parseFloat(parts[1]) || 0
          root.networkReady = true
        }
      }
    }
  }

  function refreshNetwork() {
    if (!networkProcess.running) networkProcess.running = true
  }

  Timer {
    interval: 3000
    running: root.networkWanted
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNetwork()
  }

  // ------------------------------------------------------- combined model

  // Resolves one configuredItems key to its ring data. The Repeater below
  // binds to configuredItems itself (not a per-poll list of resolved
  // entries), and each delegate calls this for its own live data --
  // Repeater recreates every delegate when the model *array reference*
  // changes, even to an equivalent array, which was destroying every
  // ring's HoverHandler (closing any open card) on every data poll.
  function entryFor(key) {
    if (key === "weather") return root.weatherEntry()
    if (key === "cpu") return root.cpuEntry()
    if (key === "memory") return root.memoryEntry()
    if (key === "download") return root.downloadEntry()
    if (key === "upload") return root.uploadEntry()
    return root.agentEntry(key)
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
          model: root.configuredItems

          Column {
            required property string modelData
            readonly property var entry: root.entryFor(modelData)
            visible: entry.available
            spacing: 6
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
                visible: entry.type === "agent" || entry.type === "resource"
                anchors.fill: parent
                ShapePath {
                  strokeWidth: root.ringStroke
                  strokeColor: entry.color
                  fillColor: "transparent"
                  capStyle: ShapePath.RoundCap
                  PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: root.ringSize / 2 - root.ringStroke
                    radiusY: root.ringSize / 2 - root.ringStroke
                    startAngle: -90
                    sweepAngle: entry.known ? 360 * entry.percent : 0
                  }
                }
              }
              Image {
                visible: entry.type === "agent"
                source: entry.type === "agent" ? ("file://" + entry.icon) : ""
                width: root.ringSize * 0.42
                height: width
                anchors.centerIn: parent
                fillMode: Image.PreserveAspectFit
              }
              // font.family pinned: fontconfig's default match for some of
              // these codepoints (clear-sky "☀") resolves to a plain UI
              // font instead of the emoji font.
              Text {
                visible: entry.type === "weather"
                anchors.centerIn: parent
                text: entry.type === "weather" ? entry.emoji : ""
                font.family: "Noto Color Emoji"
                font.pixelSize: root.ringSize * 0.42
              }
              Text {
                visible: entry.type === "resource"
                anchors.centerIn: parent
                text: entry.type === "resource" ? entry.label : ""
                color: "#e6e6e6"
                font.pixelSize: root.ringSize * 0.24
                font.bold: true
              }
              Text {
                visible: entry.type === "network"
                anchors.centerIn: parent
                text: entry.type === "network" ? entry.label : ""
                color: entry.type === "network" ? entry.color : "#e6e6e6"
                font.pixelSize: root.ringSize * 0.4
                font.bold: true
              }

              // Separate from the pill-level HoverHandler -- this one only
              // tracks this ring, for its own detail card.
              HoverHandler {
                id: ringHover
                enabled: entry.type === "agent" || entry.id === "cpu" || entry.id === "memory" || entry.type === "weather"
              }

              // Positioned left of the ring; not clipped to ringBox's
              // bounds, and not part of the input mask (purely
              // informational, no controls).
              Rectangle {
                id: detailCard
                readonly property bool isAgentCard: entry.type === "agent" && entry.limits.length > 0
                readonly property bool isCpuCard: entry.id === "cpu"
                readonly property bool isMemoryCard: entry.id === "memory"
                readonly property bool isWeatherCard: entry.type === "weather" && entry.known
                visible: ringHover.hovered && (isAgentCard || isCpuCard || isMemoryCard || isWeatherCard)
                width: isWeatherCard ? 280 : isCpuCard ? 240 : 220
                height: cardColumn.implicitHeight + 24
                radius: 10
                color: pill.color
                anchors.right: parent.left
                anchors.rightMargin: 26
                anchors.verticalCenter: parent.verticalCenter

                Column {
                  id: cardColumn
                  anchors.centerIn: parent
                  width: parent.width - 24
                  spacing: 10

                  Row {
                    // weather/cpu have their own hero line instead
                    visible: !detailCard.isWeatherCard && !detailCard.isCpuCard
                    spacing: 8
                    Image {
                      visible: entry.type === "agent"
                      source: entry.type === "agent" ? ("file://" + entry.icon) : ""
                      width: 18
                      height: 18
                      anchors.verticalCenter: parent.verticalCenter
                      fillMode: Image.PreserveAspectFit
                    }
                    Text {
                      text: entry.type === "agent" ? (entry.displayName + " Usage")
                        : detailCard.isCpuCard ? "CPU"
                        : detailCard.isMemoryCard ? "Memory"
                        : detailCard.isWeatherCard ? "Weather"
                        : ""
                      color: "#f2f2f2"
                      font.pixelSize: 14
                      font.bold: true
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Item {
                    visible: detailCard.isWeatherCard
                    width: parent.width
                    height: 40
                    Row {
                      anchors.left: parent.left
                      anchors.bottom: parent.bottom
                      spacing: 10
                      Text {
                        text: detailCard.isWeatherCard ? entry.emoji : ""
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 34
                      }
                      Text {
                        text: detailCard.isWeatherCard ? entry.temp : ""
                        color: "#f2f2f2"
                        font.pixelSize: 34
                        font.bold: true
                      }
                    }
                    Text {
                      anchors.right: parent.right
                      anchors.top: parent.top
                      text: detailCard.isWeatherCard ? ("feels " + Math.round(entry.feelsLikeC) + "°") : ""
                      color: "#8a8a8a"
                      font.pixelSize: 12
                    }
                  }

                  Item {
                    id: rangeSlider
                    visible: detailCard.isWeatherCard
                    width: parent.width
                    height: 20
                    readonly property real frac: {
                      var lo = entry.todayMinC, hi = entry.todayMaxC
                      return hi > lo ? Math.max(0, Math.min(1, (entry.tempRawC - lo) / (hi - lo))) : 0.5
                    }

                    Text {
                      id: rangeMinLabel
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: detailCard.isWeatherCard ? Math.round(entry.todayMinC) + "°" : ""
                      color: "#9a9aa5"
                      font.pixelSize: 12
                    }
                    Text {
                      id: rangeMaxLabel
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: detailCard.isWeatherCard ? Math.round(entry.todayMaxC) + "°" : ""
                      color: "#9a9aa5"
                      font.pixelSize: 12
                    }
                    Rectangle {
                      anchors.left: rangeMinLabel.right
                      anchors.leftMargin: 10
                      anchors.right: rangeMaxLabel.left
                      anchors.rightMargin: 10
                      anchors.verticalCenter: parent.verticalCenter
                      height: 4
                      radius: 2
                      color: "#45455a"
                      Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * rangeSlider.frac - width / 2
                      }
                    }
                  }

                  Row {
                    visible: detailCard.isWeatherCard
                    spacing: 8

                    Rectangle {
                      radius: height / 2
                      height: humidityChipText.implicitHeight + 10
                      width: humidityChipText.implicitWidth + 20
                      color: "transparent"
                      border.color: "#45455a"
                      border.width: 1
                      Text {
                        id: humidityChipText
                        anchors.centerIn: parent
                        text: detailCard.isWeatherCard ? (Math.round(entry.humidity) + "% humidity") : ""
                        color: "#e6e6e6"
                        font.pixelSize: 11
                      }
                    }
                    Rectangle {
                      radius: height / 2
                      height: windChipText.implicitHeight + 10
                      width: windChipText.implicitWidth + 20
                      color: "transparent"
                      border.color: "#45455a"
                      border.width: 1
                      Text {
                        id: windChipText
                        anchors.centerIn: parent
                        text: detailCard.isWeatherCard ? (Math.round(entry.windKmph) + " km/h " + entry.windDir) : ""
                        color: "#e6e6e6"
                        font.pixelSize: 11
                      }
                    }
                    Rectangle {
                      radius: height / 2
                      height: conditionChipText.implicitHeight + 10
                      width: conditionChipText.implicitWidth + 20
                      color: "transparent"
                      border.color: "#45455a"
                      border.width: 1
                      Text {
                        id: conditionChipText
                        anchors.centerIn: parent
                        text: detailCard.isWeatherCard ? entry.conditionText : ""
                        color: "#e6e6e6"
                        font.pixelSize: 11
                      }
                    }
                  }

                  Repeater {
                    model: detailCard.isAgentCard ? entry.limits.slice(0, 2) : []

                    Column {
                      width: cardColumn.width
                      spacing: 4

                      Item {
                        width: parent.width
                        height: 16
                        Text {
                          anchors.left: parent.left
                          text: modelData.label || ""
                          color: "#cfcfcf"
                          font.pixelSize: 11
                        }
                        Text {
                          anchors.right: parent.right
                          text: root.formatResetTime(modelData.resetsAt) ? ("Resets " + root.formatResetTime(modelData.resetsAt)) : ""
                          color: "#8a8a8a"
                          font.pixelSize: 10
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: "#333333"
                        Rectangle {
                          width: parent.width * Math.max(0, Math.min(1, modelData.percent || 0))
                          height: parent.height
                          radius: 3
                          color: root.severityColor(modelData.percent || 0)
                        }
                      }

                      Text {
                        text: Math.round((modelData.percent || 0) * 100) + "% Used"
                        color: "#cfcfcf"
                        font.pixelSize: 11
                      }
                    }
                  }

                  Item {
                    visible: detailCard.isCpuCard
                    width: parent.width
                    height: 40
                    Column {
                      anchors.left: parent.left
                      anchors.bottom: parent.bottom
                      spacing: 0
                      Text {
                        text: detailCard.isCpuCard ? Math.round(entry.percent * 100) + "%" : ""
                        color: "#f2f2f2"
                        font.pixelSize: 30
                        font.bold: true
                      }
                      Text {
                        text: "CPU in use"
                        color: "#8a8a8a"
                        font.pixelSize: 11
                      }
                    }
                    Text {
                      id: cpuFreqLabel
                      anchors.right: parent.right
                      anchors.top: parent.top
                      text: detailCard.isCpuCard ? (entry.freqMhz / 1000).toFixed(2) + " GHz" : ""
                      color: "#9a9aa5"
                      font.pixelSize: 11
                    }
                    Text {
                      anchors.right: parent.right
                      anchors.top: cpuFreqLabel.bottom
                      anchors.topMargin: 2
                      text: detailCard.isCpuCard
                        ? (entry.load1.toFixed(2) + " / " + entry.load5.toFixed(2) + " / " + entry.load15.toFixed(2))
                        : ""
                      color: "#9a9aa5"
                      font.pixelSize: 11
                    }
                  }

                  Item {
                    visible: detailCard.isCpuCard
                    width: parent.width
                    height: 8

                    Rectangle {
                      anchors.fill: parent
                      radius: height / 2
                      color: "#333333"
                    }
                    Row {
                      id: cpuSegRow
                      height: parent.height
                      width: parent.width * (detailCard.isCpuCard ? Math.max(0, Math.min(1, entry.percent)) : 0)
                      readonly property real usedSum: {
                        if (!detailCard.isCpuCard) return 0
                        var s = entry.otherPercent
                        for (var i = 0; i < entry.topProcesses.length; i++) s += entry.topProcesses[i].percent
                        return s
                      }

                      Repeater {
                        model: detailCard.isCpuCard ? entry.topProcesses : []
                        Rectangle {
                          width: cpuSegRow.usedSum > 0 ? cpuSegRow.width * (modelData.percent / cpuSegRow.usedSum) : 0
                          height: cpuSegRow.height
                          color: root.cpuSegmentColor(index)
                        }
                      }
                      Rectangle {
                        visible: detailCard.isCpuCard && entry.otherPercent > 0
                        width: cpuSegRow.usedSum > 0 ? cpuSegRow.width * (entry.otherPercent / cpuSegRow.usedSum) : 0
                        height: cpuSegRow.height
                        color: "#555555"
                      }
                    }
                  }

                  // name is the kernel's own truncated comm (15 chars max)
                  Column {
                    visible: detailCard.isCpuCard
                    width: parent.width
                    spacing: 6

                    Repeater {
                      model: detailCard.isCpuCard ? entry.topProcesses : []
                      Item {
                        width: parent.width
                        height: 16
                        Rectangle {
                          width: 8
                          height: 8
                          radius: 2
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          color: root.cpuSegmentColor(index)
                        }
                        Text {
                          anchors.left: parent.left
                          anchors.leftMargin: 14
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.name
                          color: "#e6e6e6"
                          font.pixelSize: 11
                        }
                        Text {
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.percent.toFixed(1) + "%"
                          color: "#e6e6e6"
                          font.pixelSize: 11
                        }
                      }
                    }

                    Item {
                      visible: detailCard.isCpuCard && entry.otherPercent > 0
                      width: parent.width
                      height: 16
                      Rectangle {
                        width: 8
                        height: 8
                        radius: 2
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#555555"
                      }
                      Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Everything else"
                        color: "#9a9a9a"
                        font.pixelSize: 11
                      }
                      Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: detailCard.isCpuCard ? entry.otherPercent.toFixed(1) + "%" : ""
                        color: "#9a9a9a"
                        font.pixelSize: 11
                      }
                    }
                  }

                  Column {
                    visible: detailCard.isMemoryCard
                    width: cardColumn.width
                    spacing: 8

                    Item {
                      width: parent.width
                      height: 16
                      Text {
                        anchors.left: parent.left
                        text: "Used"
                        color: "#cfcfcf"
                        font.pixelSize: 11
                      }
                      Text {
                        anchors.right: parent.right
                        text: detailCard.isMemoryCard ? (entry.usedGb.toFixed(1) + " / " + entry.totalGb.toFixed(1) + " GB") : ""
                        color: "#f2f2f2"
                        font.pixelSize: 11
                      }
                    }
                    Rectangle {
                      width: parent.width
                      height: 6
                      radius: 3
                      color: "#333333"
                      Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, entry.percent || 0))
                        height: parent.height
                        radius: 3
                        color: root.severityColor(entry.percent || 0)
                      }
                    }

                    Item {
                      width: parent.width
                      height: 16
                      visible: detailCard.isMemoryCard && entry.swapTotalGb > 0.05
                      Text {
                        anchors.left: parent.left
                        text: "Swap used"
                        color: "#cfcfcf"
                        font.pixelSize: 11
                      }
                      Text {
                        anchors.right: parent.right
                        text: detailCard.isMemoryCard ? (entry.swapUsedGb.toFixed(1) + " / " + entry.swapTotalGb.toFixed(1) + " GB") : ""
                        color: "#f2f2f2"
                        font.pixelSize: 11
                      }
                    }
                    Rectangle {
                      visible: detailCard.isMemoryCard && entry.swapTotalGb > 0.05
                      width: parent.width
                      height: 6
                      radius: 3
                      color: "#333333"
                      Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, entry.swapPercent || 0))
                        height: parent.height
                        radius: 3
                        color: root.severityColor(entry.swapPercent || 0)
                      }
                    }
                  }

                  Rectangle {
                    visible: detailCard.isWeatherCard && (entry.forecast || []).length > 0
                    width: parent.width
                    height: 1
                    color: "#2a2a2a"
                  }

                  Column {
                    id: forecastRows
                    // entry.forecast only exists on weather entries; this
                    // Column exists in every ring's card, hence the fallback.
                    readonly property var fc: entry.forecast || []
                    visible: detailCard.isWeatherCard && fc.length > 0
                    width: cardColumn.width
                    spacing: 10
                    readonly property real gMin: fc.length > 0
                      ? Math.min.apply(null, fc.map(function(d) { return d.minC }))
                      : 0
                    readonly property real gMax: fc.length > 0
                      ? Math.max.apply(null, fc.map(function(d) { return d.maxC }))
                      : 1
                    readonly property real gSpan: Math.max(1, gMax - gMin)

                    Repeater {
                      model: forecastRows.fc

                      Item {
                        width: forecastRows.width
                        height: 20

                        Text {
                          id: rowDay
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          width: 28
                          text: modelData.dayLabel
                          color: "#e6e6e6"
                          font.pixelSize: 12
                        }
                        Text {
                          id: rowIcon
                          anchors.left: rowDay.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.emoji
                          font.family: "Noto Color Emoji"
                          font.pixelSize: 15
                        }
                        Text {
                          id: rowMin
                          anchors.left: rowIcon.right
                          anchors.leftMargin: 8
                          anchors.verticalCenter: parent.verticalCenter
                          width: 24
                          text: Math.round(modelData.minC) + "°"
                          color: "#9a9aa5"
                          font.pixelSize: 12
                        }
                        Text {
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          width: 28
                          horizontalAlignment: Text.AlignRight
                          text: Math.round(modelData.maxC) + "°"
                          color: "#e6e6e6"
                          font.pixelSize: 12
                        }
                        Item {
                          id: rowBar
                          anchors.left: rowMin.right
                          anchors.leftMargin: 8
                          anchors.right: parent.right
                          anchors.rightMargin: 36
                          anchors.verticalCenter: parent.verticalCenter
                          height: 6

                          Rectangle {
                            x: rowBar.width * ((modelData.minC - forecastRows.gMin) / forecastRows.gSpan)
                            width: Math.max(4, rowBar.width * ((modelData.maxC - modelData.minC) / forecastRows.gSpan))
                            height: parent.height
                            radius: height / 2
                            color: "#8b7fd6"
                          }
                        }
                      }
                    }
                  }
                }

                // Rotated square centered on the card's edge: half hidden
                // under the card, half pokes out as a pointer. Must stay
                // a child of detailCard so "parent" resolves to the card.
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
              text: entry.type === "weather" ? entry.temp
                : entry.type === "network" ? entry.value
                : (entry.known ? Math.round(entry.percent * 100) + "%" : "--")
              color: "#e6e6e6"
              font.pixelSize: root.size.percentFont
            }
          }
        }
      }
    }
  }
}
