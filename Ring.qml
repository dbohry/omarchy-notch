import QtQuick
import QtQuick.Shapes

// One circular arc filling its parent, starting at 12 o'clock. Used twice per
// item: once for the grey track, once for the item's own progress.
Shape {
  id: root
  property real thickness: 3
  property color stroke: "#333333"
  // 0..1 of the full circle.
  property real fraction: 1

  anchors.fill: parent

  ShapePath {
    strokeWidth: root.thickness
    strokeColor: root.stroke
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    PathAngleArc {
      centerX: root.width / 2
      centerY: root.height / 2
      radiusX: root.width / 2 - root.thickness
      radiusY: root.height / 2 - root.thickness
      startAngle: -90
      sweepAngle: 360 * root.fraction
    }
  }
}
