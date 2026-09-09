// Node regression guard: catch QML dotted references to undefined identifiers
// — the class of bug that broke the entity rows (EntityRow.qml used
// `sliderSlot.implicitHeight` with no `sliderSlot` anywhere, which qmllint
// does not flag because the unresolved qs.* imports mask id resolution).
// Run: node tests/test_qml_ids.js
//
// Extraction is deliberately permissive: anything in the file that could
// legally introduce a name counts as declared (ids, properties, aliases,
// functions and their parameters, `var` locals, import aliases). A dotted
// access to a name that is neither declared nor a known Qt/qs/JS builtin is
// an error. Strings and comments are stripped before analysis so prose never
// registers as code; line numbers are preserved via newline-keeping
// replacement.

const fs = require("fs")
const path = require("path")

const ROOT = path.join(__dirname, "..")

// Names QML, QtQuick, qs.Commons or plain JS provide without a declaration in
// the file. Only the names actually accessed with a following dot belong here.
const BUILTINS = {
  // QML/QtQuick context, built-in types used as namespaces, JS globals.
  anchors: true, parent: true, children: true, contentItem: true, window: true,
  font: true, text: true, this: true, console: true, Date: true,
  Qt: true, Math: true, Number: true, String: true, Object: true, JSON: true,
  Style: true, Color: true, Border: true, Component: true, Loader: true,
  Repeater: true, Instantiator: true, Timer: true, Connections: true,
  Binding: true, Behavior: true, State: true, Transition: true,
  PropertyAnimation: true, Quickshell: true, ListModel: true,
  Item: true, Rectangle: true, Column: true, Row: true, Text: true,
  TextEdit: true, MouseArea: true, Flickable: true, ScrollView: true,
  ScrollBar: true, Canvas: true, Font: true, Frame: true,
  // Injected by the shell into plugin root objects.
  bar: true, shell: true,
  // Provided by `import Quickshell.Wayland` directly (no alias) for the
  // dotless settings overlay surface.
  WlrLayershell: true, WlrLayer: true, WlrKeyboardFocus: true,
  ExclusionMode: true,
  // Selection-mode / view locals injected by Qt delegate machinery.
  modelData: true, index: true, model: true, loop: true,
}

// Replace string literals with `""` (they cannot span lines in QML) and then
// strip `//` and `/* */` comments, keeping newlines so reported line numbers
// still point at the real source. Import statements are parsed from the raw
// source instead (below): they carry their string module path, which this
// step otherwise removes.
function sanitize(source) {
  let s = source
    .replace(/"[^"\n]*"/g, '""')
    .replace(/'[^'\n]*'/g, '""')
  s = s.replace(/\/\/[^\n]*/g, "")
  s = s.replace(/\/\*[\s\S]*?\*\//g, function (m) {
    return m.replace(/[^\n]/g, " ")
  })
  return s
}

// Import aliases come from the raw text: `import "X.js" as X` needs its string
// path to parse, which sanitize() erases. Nothing else here can carry a
// comment or string on the same line, so a fresh whole-file regex is safe.
function declaredImports(raw) {
  const names = {}
  const re = /\bimport\s+(?:["'][^"']+["']|qs\.\w+)\s+as\s+([A-Za-z_][A-Za-z0-9_]*)/g
  let m
  while ((m = re.exec(raw)) !== null) names[m[1]] = true
  return names
}

function declaredNames(source) {
  const names = {}

  const add = (n) => { if (n) names[n] = true }

  const idRe = /\bid\s*:\s*([A-Za-z_][A-Za-z0-9_]*)/g
  const propRe = /\b(?:readonly\s+|static\s+)?(?:default\s+|required\s+)?property\s+[A-Za-z_][A-Za-z0-9_]*(?:\s*<[^>]*>)?\s+([A-Za-z_][A-Za-z0-9_]*)/g
  const aliasRe = /\balias\s+([A-Za-z_][A-Za-z0-9_]*)/g
  const fnRe = /\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)/g
  const varRe = /\b(?:var|let|const)\s+([A-Za-z_][A-Za-z0-9_]*)/g

  let m
  while ((m = idRe.exec(source)) !== null) add(m[1])
  while ((m = propRe.exec(source)) !== null) add(m[1])
  while ((m = aliasRe.exec(source)) !== null) add(m[1])
  while ((m = fnRe.exec(source)) !== null) {
    add(m[1])
    m[2].split(",").forEach(function (part) {
      part = part.trim()
      if (!part) return
      // `QString text`, `text`, `itemName = "x"`: last bare word is the name.
      const bare = part.match(/[A-Za-z_][A-Za-z0-9_]*\s*$/)
      if (bare) add(bare[0])
    })
  }
  while ((m = varRe.exec(source)) !== null) add(m[1])

  return names
}

function flaggedReferences(source, rawSource) {
  const declared = declaredNames(source)
  // Module aliases come from the pre-sanitise text (their string import URI
  // is stripped otherwise), merged into the same name space.
  const imports = declaredImports(rawSource)
  const flag = []
  const re = /\b([A-Za-z_][A-Za-z0-9_]*)\s*\./g
  let m
  while ((m = re.exec(source)) !== null) {
    // Skip import lines (`import qs.Ui` would otherwise read as a `qs.` use).
    const lineStart = source.lastIndexOf("\n", m.index) + 1
    if (/^\s*import\b/.test(source.slice(lineStart, m.index))) continue
    const name = m[1]
    // A token that trails a dot is the member of the preceding base object
    // (`oh.rows.count`: `rows` is `oh`'s member, not a bare id); only the
    // first token of a chain has to resolve.
    if (/\.\s*$/.test(source.slice(0, m.index))) continue
    if (declared[name] || imports[name] || BUILTINS[name]) continue
    const line = source.slice(0, m.index).split("\n").length
    flag.push({ name: name, line: line })
  }
  return flag
}

const files = fs.readdirSync(ROOT).filter(function (f) {
  return /\.qml$/i.test(f)
})

let passed = 0
let failed = 0
function check(name, cond, detail) {
  if (cond) { passed++; console.log("ok   - " + name) }
  else { failed++; console.log("FAIL - " + name + (detail ? " :: " + detail : "")) }
}

files.forEach(function (file) {
  const raw = fs.readFileSync(path.join(ROOT, file), "utf8")
  const source = sanitize(raw)
  const flags = flaggedReferences(source, raw)
  if (flags.length === 0) {
    check(file + " has no undeclared dotted references", true)
  } else {
    const detail = flags.map(function (f) { return f.name + "@" + f.line }).join(", ")
    check(file + " has no undeclared dotted references", false, detail)
  }
})

// The regression that started this check: a reference to an id that never
// exists anywhere in the plugin must be caught.
{
  const raw = "import QtQuick\nItem {\n  id: row\n  implicitHeight: Math.max(glyph.implicitHeight, sliderSlot.implicitHeight)\n}"
  const source = sanitize(raw)
  check("regression: catching a synthetic sliderSlot", flaggedReferences(source, raw).length > 0)
}

console.log("\npython-style summary: %d passed, %d failed", passed, failed)
process.exit(failed ? 1 : 0)