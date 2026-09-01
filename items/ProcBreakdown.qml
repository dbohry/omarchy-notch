import QtQuick

// Stacked "top 3 processes + everything else" bar with its legend, shared by
// the cpu and memory cards. Drop it into a card Column and hand it a process
// list from host.sysStats.
Column {
  id: root

  // Ring/accent color; each row gets a progressively darker shade of it.
  property color accent: "#8a8a8a"
  // [{name, percent}], already sorted, at most 3 (see notch-resource-stats).
  property var processes: []
  property real otherPercent: 0
  // 0..1 overall utilization -- how much of the track the bar fills.
  property real fillFraction: 0

  spacing: 10

  Theme { id: theme }

  // One row list drives both the bar segments and the legend, so the two can
  // never disagree. `name` is the kernel's own truncated comm (15 chars max).
  readonly property var rows: {
    var out = []
    for (var i = 0; i < root.processes.length; i++) {
      out.push({
        name: root.processes[i].name,
        percent: root.processes[i].percent,
        color: theme.rankColor(root.accent, i),
        muted: false
      })
    }
    if (root.otherPercent > 0) {
      out.push({ name: "Everything else", percent: root.otherPercent, color: theme.otherColor, muted: true })
    }
    return out
  }
  readonly property real rowSum: {
    var s = 0
    for (var i = 0; i < root.rows.length; i++) s += root.rows[i].percent
    return s
  }

  Item {
    width: parent.width
    height: 8

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: theme.trackBg
    }
    Row {
      id: segRow
      height: parent.height
      width: parent.width * Math.max(0, Math.min(1, root.fillFraction))

      Repeater {
        model: root.rows
        Rectangle {
          width: root.rowSum > 0 ? segRow.width * (modelData.percent / root.rowSum) : 0
          height: segRow.height
          color: modelData.color
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: 6

    Repeater {
      model: root.rows

      Item {
        width: parent.width
        height: 16
        Rectangle {
          width: 8
          height: 8
          radius: 2
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          color: modelData.color
        }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.name
          color: modelData.muted ? theme.textMuted : theme.textPrimary
          font.pixelSize: 11
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.percent.toFixed(1) + "%"
          color: modelData.muted ? theme.textMuted : theme.textPrimary
          font.pixelSize: 11
        }
      }
    }
  }
}
