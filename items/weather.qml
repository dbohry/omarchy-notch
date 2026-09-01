import QtQuick
import Quickshell
import Quickshell.Io

// wttr.in bootstraps lat/lon from the location the built-in weather bar
// widget already writes (no separate picker here); Open-Meteo supplies the
// live reading + 4-day forecast. Missing/name-only location means IP
// auto-detect via wttr.in.
Item {
  id: root
  visible: false

  property string itemId: ""
  property var host: null

  readonly property string home: Quickshell.env("HOME") || ""

  property real tempC: NaN
  property real code: NaN
  property bool isDay: true
  property real feelsLikeC: NaN
  property real humidity: NaN
  property real windKmph: NaN
  property string windDir: ""
  // daily.*[0] in the same Open-Meteo response as the forecast (index 0).
  property real todayMaxC: NaN
  property real todayMinC: NaN
  // Next 3 days: [{dayLabel, emoji, maxC, minC}, ...]
  property var forecast: []
  property bool ready: false
  property string locationQuery: ""
  property real lat: NaN
  property real lon: NaN

  readonly property bool available: true
  readonly property bool known: root.ready && !isNaN(root.tempC)
  readonly property real percent: 0
  readonly property bool showArc: false
  readonly property color ringColor: "#5db8e8"
  readonly property string bottomLabel: root.known ? (Math.round(root.tempC) + "°") : "--"

  // Open-Meteo WMO weather codes. `night` is the after-dark variant, only
  // meaningful for the live reading -- forecast days have no day/night state.
  readonly property var conditions: [
    { codes: [0],                        emoji: "☀",  night: "🌙", text: "Clear" },
    { codes: [1, 2],                     emoji: "⛅", night: "🌙", text: "Partly cloudy" },
    { codes: [3],                        emoji: "☁",  text: "Cloudy" },
    { codes: [45, 48],                   emoji: "🌫", text: "Fog" },
    { codes: [51, 53, 55, 56, 57],       emoji: "🌦", text: "Drizzle" },
    { codes: [61, 63, 65, 66, 67, 80, 81, 82], emoji: "🌧", text: "Rain" },
    { codes: [71, 73, 75, 77, 85, 86],   emoji: "❄",  text: "Snow" },
    { codes: [95, 96, 99],               emoji: "⛈", text: "Thunderstorm" }
  ]

  function condition(c) {
    var code = parseInt(String(c || "0"), 10)
    for (var i = 0; i < root.conditions.length; i++) {
      if (root.conditions[i].codes.indexOf(code) !== -1) return root.conditions[i]
    }
    return { emoji: "⛅", text: "Cloudy" }
  }

  function weatherEmoji(c, day) {
    var m = root.condition(c)
    return (day === undefined || day || !m.night) ? m.emoji : m.night
  }

  function degToCompass(deg) {
    var dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    return dirs[Math.round(deg / 22.5) % 16]
  }

  // daily.* are parallel arrays; index 0 is today (shown in the hero row),
  // so this starts at 1 and takes the next 3.
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

  FileView {
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyLocation(text())
    onLoadFailed: root.applyLocation("")
  }

  function applyLocation(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      root.locationQuery = (parsed && typeof parsed.name === "string") ? parsed.name : ""
      root.lat = parsed ? parseFloat(parsed.latitude) : NaN
      root.lon = parsed ? parseFloat(parsed.longitude) : NaN
    } catch (e) {
      root.locationQuery = ""
      root.lat = NaN
      root.lon = NaN
    }
  }

  // wttr.in / open-meteo can be slow or flaky, especially right after waking
  // with the network still down. Each Retry gives up after 3 attempts and
  // leaves it to the 15-minute refresh timer.
  Retry {
    id: geoRetry
    onTriggered: if (!geoProcess.running) geoProcess.running = true
  }

  Retry {
    id: openMeteoRetry
    onTriggered: if (!openMeteoProcess.running) openMeteoProcess.running = true
  }

  Process {
    id: geoProcess
    command: ["curl", "-fsS", "--max-time", "5", "https://wttr.in/" + encodeURIComponent(root.locationQuery) + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var area = JSON.parse(String(text || "")).nearest_area[0]
          geoRetry.reset()
          root.fetchOpenMeteo(parseFloat(area.latitude), parseFloat(area.longitude))
        } catch (e) {
          geoRetry.schedule()
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
          root.tempC = parseFloat(current.temperature_2m)
          root.code = parseFloat(current.weather_code)
          root.isDay = parseFloat(current.is_day) !== 0
          root.feelsLikeC = parseFloat(current.apparent_temperature)
          root.humidity = parseFloat(current.relative_humidity_2m)
          root.windKmph = parseFloat(current.wind_speed_10m)
          root.windDir = isNaN(parseFloat(current.wind_direction_10m)) ? "" : root.degToCompass(parseFloat(current.wind_direction_10m))
          root.todayMaxC = parseFloat(report.daily.temperature_2m_max[0])
          root.todayMinC = parseFloat(report.daily.temperature_2m_min[0])
          root.forecast = root.parseForecast(report.daily)
          root.ready = true
          openMeteoRetry.reset()
        } catch (e) {
          openMeteoRetry.schedule()
        }
      }
    }
  }

  function fetchOpenMeteo(la, lo) {
    if (isNaN(la) || isNaN(lo)) {
      root.ready = false
      return
    }
    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(la))
      + "&longitude=" + encodeURIComponent(String(lo))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,weather_code,is_day"
      + "&forecast_days=4&timezone=auto"
    openMeteoProcess.command = ["curl", "-fsS", "--max-time", "5", url]
    openMeteoProcess.running = true
  }

  function refresh() {
    if (geoProcess.running || openMeteoProcess.running) return
    geoRetry.reset()
    openMeteoRetry.reset()
    if (!isNaN(root.lat) && !isNaN(root.lon)) {
      root.fetchOpenMeteo(root.lat, root.lon)
    } else {
      geoProcess.running = true
    }
  }

  Timer {
    interval: 900000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  readonly property Component ringContent: Component {
    // font.family pinned: fontconfig's default match for some of these
    // codepoints (clear-sky "☀") resolves to a plain UI font instead
    // of the emoji font.
    Text {
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.known ? root.weatherEmoji(root.code, root.isDay) : "⛅"
      font.family: "Noto Color Emoji"
      font.pixelSize: parent.height * 0.42
    }
  }

  readonly property int cardWidth: 280

  readonly property var chips: [
    Math.round(root.humidity) + "% humidity",
    Math.round(root.windKmph) + " km/h " + root.windDir,
    root.condition(root.code).text
  ]

  readonly property Component cardContent: Component {
    Column {
      id: cardColumn
      width: parent.width
      spacing: 10

      Theme { id: theme }

      Item {
        width: parent.width
        height: 40
        Row {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          spacing: 10
          Text {
            text: root.known ? root.weatherEmoji(root.code, root.isDay) : "⛅"
            font.family: "Noto Color Emoji"
            font.pixelSize: 34
          }
          Text {
            text: root.bottomLabel
            color: theme.textPrimary
            font.pixelSize: 34
            font.bold: true
          }
        }
        Text {
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.known ? ("feels " + Math.round(root.feelsLikeC) + "°") : ""
          color: theme.textMuted
          font.pixelSize: 12
        }
      }

      Item {
        id: rangeSlider
        width: parent.width
        height: 20
        readonly property real frac: {
          var lo = root.todayMinC, hi = root.todayMaxC
          return hi > lo ? Math.max(0, Math.min(1, (root.tempC - lo) / (hi - lo))) : 0.5
        }

        Text {
          id: rangeMinLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: Math.round(root.todayMinC) + "°"
          color: theme.textFaint
          font.pixelSize: 12
        }
        Text {
          id: rangeMaxLabel
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: Math.round(root.todayMaxC) + "°"
          color: theme.textFaint
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
          color: theme.borderColor
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

      Flow {
        width: cardColumn.width
        spacing: 8

        Repeater {
          model: root.chips

          Rectangle {
            radius: height / 2
            height: chipText.implicitHeight + 10
            width: chipText.implicitWidth + 20
            color: "transparent"
            border.color: theme.borderColor
            border.width: 1
            Text {
              id: chipText
              anchors.centerIn: parent
              text: modelData
              color: theme.textSecondary
              font.pixelSize: 11
            }
          }
        }
      }

      Rectangle {
        visible: root.forecast.length > 0
        width: parent.width
        height: 1
        color: theme.divider
      }

      Column {
        id: forecastRows
        visible: root.forecast.length > 0
        width: cardColumn.width
        spacing: 10
        readonly property real gMin: root.forecast.length > 0
          ? Math.min.apply(null, root.forecast.map(function(d) { return d.minC }))
          : 0
        readonly property real gMax: root.forecast.length > 0
          ? Math.max.apply(null, root.forecast.map(function(d) { return d.maxC }))
          : 1
        readonly property real gSpan: Math.max(1, gMax - gMin)

        Repeater {
          model: root.forecast

          Item {
            width: forecastRows.width
            height: 20

            Text {
              id: rowDay
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 28
              text: modelData.dayLabel
              color: theme.textSecondary
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
              color: theme.textFaint
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: 28
              horizontalAlignment: Text.AlignRight
              text: Math.round(modelData.maxC) + "°"
              color: theme.textSecondary
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
  }
}
