.pragma library

// The openHAB brand mark. Draws the logo the way the trademark holders drew
// it — a ring open at the lower-left and a swoosh crossing through the gap —
// rather than an approximation, so a 16px bar slot reads as openHAB and not as
// a generic status ring.
//
// Source: the canonical square openHAB mark (the official SVG kept in this
// project's artwork, also carried as openhab.svg). The two `d` strings below
// are that artwork verbatim except the ring's trailing `z` — the artwork ends
// its ring back at (16,2) without an explicit close, and the `z` only makes
// the implicit SVG closure explicit for the canvas replay. Outer ring radius
// 14, inner 11.708, on a 28-unit edge-to-edge viewBox — so the shape's
// proportions are the brand's own, not a redraw. Distributed under the
// openHAB trademark policy; this file keeps only the geometry and tints it
// with the theme at draw time.
//
// The Mark.js contract is pure geometry: official SVG path `d` strings parsed
// into absolute commands (arcs expanded to cubic segments) and fitted into a
// square of a requested size. OpenHabIcon.qml replays the commands on a
// Canvas. No QML types and no side effects beyond the module-level parse, so
// the numbers are testable outside the shell.

// ------------------------------------------------------------------ artwork

// A single closed subpath: an outer circle from the top, a short jog down to
// the inner circle, most of the way around the inner circle back, and a
// second jog out to the closing arc — the squared notch opening at the
// lower-left is the logo's gap. The artwork's `d` string returns to its start
// without an explicit `z`; SVG fills implicitly close that, and the trailing
// `z` below makes the closure explicit for the canvas replay (no visible
// difference, both end at (16,2)).
var RING_PATH =
  "M16 2A14 14 0 1 1 5.431 25.162" +
  "l.495-.5.359-.359.36-.36.36-.36.015-.015" +
  "a11.708 11.708 0 1 0-2.5-5.03" +
  "l-.78.782-1.04 1.045" +
  "A13.994 13.994 0 0 1 16 2z"

// The swoosh. A single closed subpath shaped like a bent ribbon: it leaves
// the lower-left of the mark, climbs toward the upper-right into a pointed
// tip, and folds back along the ring's inner edge.
var SWOOSH_PATH =
  "M3.449 21.989 14.4 11.025l1.6-1.6 1.6 1.6 8.087 8.087" +
  "-.012.041-.16.47-.181.459-.2.448-.224.437-.2.354" +
  "L16 12.62 4.613 24.016" +
  "a13 13 0 0 1-1.164-2.028Z"

// Outer ring diameter as a fraction of the icon box. The canonical artwork's
// ring runs edge-to-edge on its 28-unit viewBox, so the mark fills the box.
var DIAMETER_FRACTION = 1.0

// ------------------------------------------------------------------ parsing

// Split a path `d` string into tokens: command letters and numbers. SVG
// numbers may be sign-led, plain (`16`), decimal (`14.4`), or dot-led
// decimals like `.495` / `-.5`, and may abut each other (`1.6-1.6`,
// `1-1.164-2.028`) — so tokenizing on whitespace is not enough.
function tokenizePath(d) {
  var tokens = []
  var re = /[a-zA-Z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g
  var hit
  while ((hit = re.exec(d)) !== null) tokens.push(hit[0])
  return tokens
}

function angleBetween(ux, uy, vx, vy) {
  return Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
}

// Expand one SVG elliptical-arc command into cubic segments. Returns an array
// of { x1, y1, x2, y2, x, y } absolute control/end points. Each returned
// object also carries `extent` — the exact on-arc extreme box of its piece
// (analytic, computed from the arc geometry; bezier control hulls bulge ~14%
// past a circle and would poison the fit-to-box scale).
function arcToCubics(x1, y1, rx, ry, phiDeg, largeArc, sweep, x2, y2) {
  // Degenerate start == end: the command draws nothing.
  if (x1 === x2 && y1 === y2) return []

  var phi = phiDeg * Math.PI / 180
  var cosPhi = Math.cos(phi)
  var sinPhi = Math.sin(phi)
  rx = Math.abs(rx)
  ry = Math.abs(ry)

  var x1p = cosPhi * (x1 - x2) / 2 + sinPhi * (y1 - y2) / 2
  var y1p = -sinPhi * (x1 - x2) / 2 + cosPhi * (y1 - y2) / 2

  // Correct radii if they are too small for the endpoints (spec F.6.6).
  var lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
  if (lambda > 1) {
    rx *= Math.sqrt(lambda)
    ry *= Math.sqrt(lambda)
  }

  var sign = largeArc === sweep ? -1 : 1
  var denom = rx * rx * y1p * y1p + ry * ry * x1p * x1p
  var coef = denom === 0 ? 0 : sign * Math.sqrt(Math.max(0,
    (rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p) / denom))
  var cxp = coef * rx * y1p / ry
  var cyp = coef * -ry * x1p / rx

  var cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2
  var cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2

  var theta1 = angleBetween(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
  var deltaTheta = angleBetween((x1p - cxp) / rx, (y1p - cyp) / ry,
    (-x1p - cxp) / rx, (-y1p - cyp) / ry)
  if (!sweep && deltaTheta > 0) deltaTheta -= 2 * Math.PI
  if (sweep && deltaTheta < 0) deltaTheta += 2 * Math.PI

  // Split into segments of at most 90 degrees.
  var segs = Math.max(1, Math.ceil(Math.abs(deltaTheta) / (Math.PI / 2)))
  var step = deltaTheta / segs
  var out = []

  function point(t) {
    var qx = rx * Math.cos(t)
    var qy = ry * Math.sin(t)
    return { x: cx + qx * cosPhi - qy * sinPhi, y: cy + qx * sinPhi + qy * cosPhi }
  }

  function derivative(t) {
    var dx = -rx * Math.sin(t)
    var dy = ry * Math.cos(t)
    return { x: dx * cosPhi - dy * sinPhi, y: dx * sinPhi + dy * cosPhi }
  }

  // Exact on-arc bounding box of the angle span [t1, t2] (t2 > t1, ≤ 90°).
  // A circular piece is x=cx+rx·cos(t), y=cy+ry·sin(t), so the only places x
  // or y can turn around are at t∈{0,π} (x) and t∈{π/2,3π/2} (y) — check
  // those angles plus the endpoints, allowing the full-turn offsets. The same
  // critical points survive a rotation freely because the rotation only mixes
  // axes; for a genuinely elliptical piece (rx≠ry) fall back to dense sampling.
  function segmentExtents(t1, t2) {
    var lo = Math.min(t1, t2)
    var hi = Math.max(t1, t2)
    var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity

    function take(t) {
      var p = point(t)
      if (p.x < minX) minX = p.x
      if (p.x > maxX) maxX = p.x
      if (p.y < minY) minY = p.y
      if (p.y > maxY) maxY = p.y
    }

    function takeCritical(t) {
      // the candidate angle t, shifted by a full turn to land in [lo, hi]
      var first = Math.ceil((lo - t) / (2 * Math.PI))
      var c = t + first * 2 * Math.PI
      if (c <= hi) take(c)
    }

    take(t1)
    take(t2)
    if (rx === ry) {
      takeCritical(0)
      takeCritical(Math.PI)
      takeCritical(Math.PI / 2)
      takeCritical(3 * Math.PI / 2)
    } else {
      var STEPS = 512
      for (var s = 1; s < STEPS; s++) take(t1 + (t2 - t1) * s / STEPS)
    }
    return { minX: minX, minY: minY, maxX: maxX, maxY: maxY }
  }

  for (var s = 0; s < segs; s++) {
    var t1 = theta1 + s * step
    var t2 = theta1 + (s + 1) * step
    var alpha = 4 / 3 * Math.tan((t2 - t1) / 4)
    var p0 = point(t1)
    var p3 = point(t2)
    var d1 = derivative(t1)
    var d2 = derivative(t2)
    var c1 = { x: p0.x + alpha * d1.x, y: p0.y + alpha * d1.y }
    var c2 = { x: p3.x - alpha * d2.x, y: p3.y - alpha * d2.y }
    out.push({ x1: c1.x, y1: c1.y, x2: c2.x, y2: c2.y, x: p3.x, y: p3.y,
      extent: segmentExtents(t1, t2) })
  }
  return out
}

// Parse an SVG path into absolute command objects. Supports the commands the
// artwork uses: m/M, l/L, c/C, a/A (arcs expanded to cubic segments each ≤
// 90°), and z/Z — with the SVG rule that extra coordinate pairs repeat the
// current command. Returns an array of
//   { op: "M"|"L", x, y }
//   { op: "C", x1, y1, x2, y2, x, y, extent? }
//   { op: "Z" }
function parsePath(d) {
  var ops = []
  var x = 0
  var y = 0
  var startX = 0
  var startY = 0
  var cmd = ""
  var args = []
  var tokens = tokenizePath(d)

  function apply() {
    var relative = cmd === cmd.toLowerCase()
    var i = 0
    if (cmd === "m" || cmd === "M") {
      var first = true
      while (i + 1 < args.length) {
        var mx = args[i]
        var my = args[i + 1]
        i += 2
        if (relative) { x += mx; y += my } else { x = mx; y = my }
        if (first) {
          ops.push({ op: "M", x: x, y: y })
          startX = x
          startY = y
          first = false
        } else {
          ops.push({ op: "L", x: x, y: y })
        }
      }
    } else if (cmd === "l" || cmd === "L") {
      while (i + 1 < args.length) {
        var lx = args[i]
        var ly = args[i + 1]
        i += 2
        if (relative) { x += lx; y += ly } else { x = lx; y = ly }
        ops.push({ op: "L", x: x, y: y })
      }
    } else if (cmd === "c" || cmd === "C") {
      while (i + 5 < args.length) {
        var op = { op: "C" }
        if (relative) {
          op.x1 = x + args[i]
          op.y1 = y + args[i + 1]
          op.x2 = x + args[i + 2]
          op.y2 = y + args[i + 3]
          x += args[i + 4]
          y += args[i + 5]
        } else {
          op.x1 = args[i]
          op.y1 = args[i + 1]
          op.x2 = args[i + 2]
          op.y2 = args[i + 3]
          x = args[i + 4]
          y = args[i + 5]
        }
        op.x = x
        op.y = y
        ops.push(op)
        i += 6
      }
    } else if (cmd === "a" || cmd === "A") {
      while (i + 6 < args.length) {
        var rx = args[i]
        var ry = args[i + 1]
        var phiDeg = args[i + 2]
        var largeArc = args[i + 3] !== 0
        var sweep = args[i + 4] !== 0
        var ax = args[i + 5]
        var ay = args[i + 6]
        i += 7
        var endX = relative ? x + ax : ax
        var endY = relative ? y + ay : ay
        var cubics = arcToCubics(x, y, rx, ry, phiDeg, largeArc, sweep, endX, endY)
        for (var cb = 0; cb < cubics.length; cb++) {
          var c = cubics[cb]
          ops.push({ op: "C", x1: c.x1, y1: c.y1, x2: c.x2, y2: c.y2, x: c.x, y: c.y, extent: c.extent })
        }
        x = endX
        y = endY
      }
    } else if (cmd === "z" || cmd === "Z") {
      ops.push({ op: "Z", x: startX, y: startY })
      x = startX
      y = startY
    }
    args = []
  }

  for (var t = 0; t < tokens.length; t++) {
    var token = tokens[t]
    if (/[a-zA-Z]/.test(token)) {
      if (cmd !== "") apply()
      cmd = token
    } else {
      args.push(parseFloat(token))
    }
  }
  if (cmd !== "") apply()
  return ops
}

// ------------------------------------------------------------------- bounds

function ringBounds() {
  var minX = null
  var minY = null
  var maxX = null
  var maxY = null

  function take(x, y) {
    if (minX === null || x < minX) minX = x
    if (minY === null || y < minY) minY = y
    if (maxX === null || x > maxX) maxX = x
    if (maxY === null || y > maxY) maxY = y
  }

  // The bounds drive the fit-to-box scale, so they must measure the curve the
  // canvas actually paints. Control points of an arc's cubic segments bulge up
  // to ~14% outside a circle, which would shrink the whole mark; arc segments
  // therefore carry their exact on-arc extreme box (`extent`) instead.
  MARK_SUBPATHS.forEach(function (sub) {
    sub.forEach(function (op) {
      if (op.op === "M" || op.op === "L") {
        take(op.x, op.y)
      } else if (op.op === "C") {
        if (op.extent) {
          take(op.extent.minX, op.extent.minY)
          take(op.extent.maxX, op.extent.maxY)
        } else {
          take(op.x1, op.y1)
          take(op.x2, op.y2)
          take(op.x, op.y)
        }
      }
    })
  })
  return { minX: minX, minY: minY, maxX: maxX, maxY: maxY }
}

// Parsed once at module load; OpenHabIcon.qml and the tests both consume it.
var MARK_SUBPATHS = [parsePath(RING_PATH), parsePath(SWOOSH_PATH)]
var MARK_BOUNDS = ringBounds()

// ------------------------------------------------------------------ scaling

// The two subpaths fitted into a square of `size` pixels, origin at top-left.
// The ring's outer diameter spans DIAMETER_FRACTION of the box, centered.
function geometry(size) {
  var span = Math.max(
    MARK_BOUNDS.maxX - MARK_BOUNDS.minX,
    MARK_BOUNDS.maxY - MARK_BOUNDS.minY
  )
  var scale = (DIAMETER_FRACTION * size) / span
  var centerX = (MARK_BOUNDS.minX + MARK_BOUNDS.maxX) / 2
  var centerY = (MARK_BOUNDS.minY + MARK_BOUNDS.maxY) / 2
  var half = size / 2

  function map(x, y) {
    return { x: (x - centerX) * scale + half, y: (y - centerY) * scale + half }
  }

  return MARK_SUBPATHS.map(function (sub) {
    return sub.map(function (op) {
      if (op.op === "M" || op.op === "L") {
        var p = map(op.x, op.y)
        return { op: op.op, x: p.x, y: p.y }
      }
      if (op.op === "C") {
        var c1 = map(op.x1, op.y1)
        var c2 = map(op.x2, op.y2)
        var e = map(op.x, op.y)
        return { op: "C", x1: c1.x, y1: c1.y, x2: c2.x, y2: c2.y, x: e.x, y: e.y }
      }
      return { op: "Z", x: sub[0].x, y: sub[0].y }
    })
  })
}