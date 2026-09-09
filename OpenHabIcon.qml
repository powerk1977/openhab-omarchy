import QtQuick
import qs.Commons
import "Mark.js" as Mark

// The openHAB mark, drawn rather than rasterised from an SVG: the bar slot is
// about 16px and Qt's SVG renderer smears strokes at that size.
//
// The two fills come from the official mark's geometry (see Mark.js): a ring
// open at the lower-left and a swoosh crossing through the opening. It takes
// one color so it tracks the bar foreground / dim / urgent token like every
// other bar icon instead of carrying the brand palette.
Canvas {
    id: root

    property real iconSize: Style.font.icon
    property color color: Color.foreground

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    antialiasing: true

    onColorChanged: root.requestPaint()
    onIconSizeChanged: root.requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var size = width;
        if (size <= 0)
            return;
        ctx.fillStyle = root.color;
        var subpaths = Mark.geometry(size);
        for (var i = 0; i < subpaths.length; i++) {
            var sub = subpaths[i];
            ctx.beginPath();
            for (var j = 0; j < sub.length; j++) {
                var op = sub[j];
                if (op.op === "M") {
                    ctx.moveTo(op.x, op.y);
                } else if (op.op === "L") {
                    ctx.lineTo(op.x, op.y);
                } else if (op.op === "C") {
                    ctx.bezierCurveTo(op.x1, op.y1, op.x2, op.y2, op.x, op.y);
                } else {
                    ctx.closePath();
                }
            }
            ctx.fill();
        }
    }
}
