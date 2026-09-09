// Node tests for Mark.js: the official openHAB mark geometry, parsed and
// fitted into an icon box.
// Run: node tests/test_mark.js

const fs = require("fs")
const path = require("path")
const vm = require("vm")

function load(name) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8")
    .replace(/^\.pragma library\s*\n?/, "")
  const sandbox = { Qt: undefined, console: { log: () => {}, warn: () => {} } }
  vm.createContext(sandbox)
  vm.runInContext(source, sandbox)
  return sandbox
}

const M = load("Mark.js")

let passed = 0
let failed = 0
function check(name, cond, detail) {
  if (cond) { passed++; console.log("ok   - " + name) }
  else { failed++; console.log("FAIL - " + name + (detail ? " :: " + detail : "")) }
}

// --- path parsing
const ring = M.parsePath(M.RING_PATH)
const swoosh = M.parsePath(M.SWOOSH_PATH)

check("ring parses into commands", ring.length >= 15, "len=" + ring.length)
check("swoosh parses into commands", swoosh.length > 5, "len=" + swoosh.length)
check("ring starts with a move", ring[0].op === "M")
check("ring closes with a z", ring[ring.length - 1].op === "Z")
check("ring contains cubics", ring.some(o => o.op === "C"))
check("ring contains its notch jog (lines)", ring.some(o => o.op === "L"))
check("swoosh closes with a z", swoosh[swoosh.length - 1].op === "Z")
check("no NaN in ring coords", ring.every(o =>
  ["x", "y", "x1", "y1", "x2", "y2"].every(k => o[k] === undefined || isFinite(o[k]))))
check("no NaN in swoosh coords", swoosh.every(o =>
  ["x", "y", "x1", "y1", "x2", "y2"].every(k => o[k] === undefined || isFinite(o[k]))))

// --- geometry in a 16px box
const geo = M.geometry(16)
check("geometry has two subpaths", geo.length === 2)

function flat(geo) {
  return geo.reduce((a, s) => a.concat(s), [])
}
function bbox(ops) {
  const arr = flat(ops).filter(o => o.op !== "Z")
  const pts = []
  let cur = null
  arr.forEach(o => {
    if (o.op === "M" || o.op === "L") {
      pts.push([o.x, o.y])
      cur = { x: o.x, y: o.y }
    } else if (o.op === "C") {
      // sample the on-curve bezier; control points hull may bulge up to ~14%
      // past a circular arc, so measure the curve itself
      const p0 = cur || { x: o.x, y: o.y }
      for (let i = 0; i <= 512; i++) {
        const t = i / 512, u = 1 - t
        pts.push([
          u*u*u*p0.x + 3*u*u*t*o.x1 + 3*u*t*t*o.x2 + t*t*t*o.x,
          u*u*u*p0.y + 3*u*u*t*o.y1 + 3*u*t*t*o.y2 + t*t*t*o.y
        ])
      }
      cur = { x: o.x, y: o.y }
    }
  })
  const xs = pts.map(p => p[0])
  const ys = pts.map(p => p[1])
  return { minX: Math.min(...xs), maxX: Math.max(...xs), minY: Math.min(...ys), maxY: Math.max(...ys) }
}

const box = bbox(geo)
check("mark forms a square", Math.abs((box.maxX - box.minX) - (box.maxY - box.minY)) < 0.5,
  box.maxX - box.minX + "x" + (box.maxY - box.minY))
check("mark is centered", Math.abs(box.minX - (16 - box.maxX)) < 0.5 && Math.abs(box.minY - (16 - box.maxY)) < 0.5,
  "mins " + box.minX + "," + box.minY)
check("mark diameter ~full box like official art", Math.abs((box.maxX - box.minX) - 16) < 0.5,
  "diam=" + (box.maxX - box.minX))
// The official square art runs the ring edge-to-edge on its 192px canvas
// (outer diameter 191.962); the mimic must too. The artwork's arcs are not
// perfect concentric circles (their centers are manually fudged), and the
// arc→cubic approximation can overshoot by a fraction of a pixel, so allow a
// hair of slack on each side — the point is "touches the walls", not "padded".
check("mark fills the box edge-to-edge like official art",
  box.minX > -0.05 && box.minY > -0.05 && box.maxX < 16.05 && box.maxY < 16.05 &&
  Math.abs(box.minX - 0) < 0.05 && Math.abs(box.maxX - 16) < 0.05 &&
  Math.abs(box.minY - 0) < 0.05 && Math.abs(box.maxY - 16) < 0.05,
  JSON.stringify(box))

// The ring's wall: the geometry bbox spans the ring's outer radius (scale so
// that box is the outer diameter). The inner circle of the ring sits at ~0.84
// of the outer radius in the official artwork, so the wall is ~16% of it.
function distancesTo(center, ops) {
  return ops.filter(o => o.op === "M" || o.op === "L").map(o =>
    Math.hypot(o.x - center.x, o.y - center.y))
}
const ringGeo = geo[0]
const c = { x: box.minX + (box.maxX - box.minX) / 2, y: box.minY + (box.maxY - box.minY) / 2 }
const dists = distancesTo(c, ringGeo)
const outerR = Math.max(...dists)
const innerR = Math.min(...dists)
check("ring wall is ~16% of radius", (outerR - innerR) / outerR > 0.12 && (outerR - innerR) / outerR < 0.22,
  "wall=" + ((outerR - innerR) / outerR).toFixed(3))

// The swoosh enters through the ring's opening: it must not sit outside the
// ring's outer diameter.
const ringBox = bbox([ringGeo])
const swooshGeo = geo[1]
const swooshBox = bbox([swooshGeo])
check("swoosh stays within the ring", swooshBox.minX >= ringBox.minX && swooshBox.maxX <= ringBox.maxX &&
  swooshBox.minY >= ringBox.minY && swooshBox.maxY <= ringBox.maxY,
  JSON.stringify(swooshBox) + " vs " + JSON.stringify(ringBox))

// --- determinism
check("geometry is deterministic", JSON.stringify(geo) === JSON.stringify(M.geometry(16)))
check("bigger box scales linearly", (M.geometry(32)[0][0].x - 0) === 2 * (geo[0][0].x - 0))

console.log("\npython-style summary: %d passed, %d failed", passed, failed)
process.exit(failed ? 1 : 0)