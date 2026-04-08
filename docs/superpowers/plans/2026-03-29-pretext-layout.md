# Pretext Optimal Line Breaking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace CSS greedy line breaking with Knuth-Plass optimal paragraph layout for all prose paragraphs, using canvas-based measurement (inspired by @chenglou/pretext).

**Architecture:** A single JavaScript file (`scripts/pretext-layout.js`) implements: (1) canvas-based word measurement, (2) Knuth-Plass optimal breaking via dynamic programming over box-glue-penalty items, (3) DOM integration that inserts `<br>` at computed break points while preserving inline elements (links, emphasis). On page load + resize, paragraphs are re-laid out. CSS hides paragraphs until JS completes, with a `<noscript>` fallback.

**Tech Stack:** Vanilla JavaScript (ES6+), Canvas `measureText()` API, Quarto static site

**Note on pretext:** We use the same measurement approach as `@chenglou/pretext` (canvas-based glyph measurement) but implement Knuth-Plass optimal breaking on top, which pretext does not offer. This avoids adding npm/bundler tooling to the static Quarto site while achieving better results than both CSS and pretext's greedy breaking.

---

### Task 1: Knuth-Plass Algorithm + Tests

**Files:**
- Create: `scripts/pretext-layout.js`
- Create: `scripts/test-knuth-plass.mjs`

- [ ] **Step 1: Write the test file**

Create `scripts/test-knuth-plass.mjs` with tests for tokenization and optimal breaking:

```js
import assert from 'node:assert'
import { readFileSync } from 'node:fs'

// Load the script (it exposes PretextLayout global in browser, module.exports in Node)
// We eval it since it's an IIFE with conditional exports
const code = readFileSync(new URL('./pretext-layout.js', import.meta.url), 'utf-8')
const module_ = { exports: {} }
const fn = new Function('module', 'exports', 'document', 'window', code)
fn(module_, module_.exports, undefined, undefined)
const { tokenize, computeBreaks, buildLines } = module_.exports

// Mock measurer: each character = 10px, space = 10px
function mockMeasure(text) {
  return text.length * 10
}

// --- tokenize ---

{
  const items = tokenize('Hello world foo', mockMeasure)
  // Expect: box("Hello"), glue, box("world"), glue, box("foo"), final glue, final penalty
  assert.strictEqual(items.filter(i => i.type === 'box').length, 3)
  assert.strictEqual(items.filter(i => i.type === 'box')[0].width, 50) // "Hello" = 5 chars * 10
  assert.strictEqual(items.filter(i => i.type === 'box')[1].width, 50) // "world" = 5 chars * 10
  assert.strictEqual(items.filter(i => i.type === 'box')[2].width, 30) // "foo" = 3 chars * 10
  console.log('PASS: tokenize produces correct boxes')
}

// --- computeBreaks: single line (all fits) ---

{
  const items = tokenize('Hi there', mockMeasure)
  // "Hi"=20 + space=10 + "there"=50 = 80px. Line width 200 → fits in one line.
  const breaks = computeBreaks(items, 200)
  // Only the forced final break
  assert.strictEqual(breaks.length, 1)
  console.log('PASS: single line needs no break')
}

// --- computeBreaks: two lines ---

{
  const items = tokenize('The quick brown fox jumps', mockMeasure)
  // Widths: The(30) quick(50) brown(50) fox(30) jumps(50)
  // Spaces: 10 each
  // Line width: 120px
  // Greedy: "The quick" = 30+10+50 = 90 ✓, "brown fox" = 50+10+30 = 90 ✓, "jumps" = 50 ✓ → 3 lines
  // Optimal might differ — the key is it produces valid output
  const breaks = computeBreaks(items, 120)
  const lines = buildLines(items, breaks)
  // All words should be present
  assert.strictEqual(lines.join(' '), 'The quick brown fox jumps')
  // Each line should fit within 120px (approximately — glue can stretch)
  for (let i = 0; i < lines.length - 1; i++) {
    assert.ok(mockMeasure(lines[i]) <= 140, `Line "${lines[i]}" too wide`)
  }
  console.log('PASS: multi-line breaking produces valid output')
}

// --- computeBreaks: optimal vs greedy ---

{
  // This tests that Knuth-Plass makes better global decisions.
  // Words: aaa(30) bb(20) cc(20) ddddd(50) ee(20) ff(20)
  // Line width: 80px, space width: 10px
  // Greedy: "aaa bb cc" = 30+10+20+10+20 = 90 → too wide
  //         "aaa bb" = 30+10+20 = 60 ✓
  //         "cc ddddd" = 20+10+50 = 80 ✓ (exact!)
  //         "ee ff" = 20+10+20 = 50 ✓
  //         → lines: ["aaa bb", "cc ddddd", "ee ff"] badness: 60/80=ok, 80/80=perfect, 50/80=loose
  // Optimal might prefer: ["aaa bb cc", ...] if tolerance allows stretch
  const items = tokenize('aaa bb cc ddddd ee ff', mockMeasure)
  const breaks = computeBreaks(items, 80)
  const lines = buildLines(items, breaks)
  assert.ok(lines.length >= 2 && lines.length <= 4, `Expected 2-4 lines, got ${lines.length}`)
  assert.strictEqual(lines.join(' '), 'aaa bb cc ddddd ee ff')
  console.log('PASS: optimal breaking with varied word lengths')
}

// --- buildLines ---

{
  const items = tokenize('one two three four', mockMeasure)
  const breaks = computeBreaks(items, 80)
  const lines = buildLines(items, breaks)
  assert.ok(Array.isArray(lines))
  assert.ok(lines.length > 0)
  assert.strictEqual(lines.join(' '), 'one two three four')
  console.log('PASS: buildLines reconstructs text correctly')
}

console.log('\nAll tests passed!')
```

- [ ] **Step 2: Write the main script with algorithm**

Create `scripts/pretext-layout.js`:

```js
// scripts/pretext-layout.js
// Knuth-Plass optimal paragraph line-breaking
// Uses canvas measureText() for glyph measurement (same approach as @chenglou/pretext)

var PretextLayout = (function () {
  'use strict'

  // ============ Configuration ============

  var CONFIG = {
    tolerance: 3,
    linePenalty: 10,
    selector: '#quarto-document-content p',
    skipSelectors: ['.misc-card', '.pub-abstract', '.pub-entry'],
    debounceMs: 150,
    minWords: 4
  }

  // ============ Tokenizer ============
  // Converts text into box-glue-penalty items for Knuth-Plass

  function tokenize(text, measureFn) {
    var items = []
    var spaceWidth = measureFn(' ')
    var regex = /(\S+)|(\s+)/g
    var match

    while ((match = regex.exec(text)) !== null) {
      if (match[2]) {
        items.push({
          type: 'glue',
          width: spaceWidth,
          stretch: spaceWidth * 0.5,
          shrink: spaceWidth * 0.33,
          pos: match.index
        })
      } else {
        items.push({
          type: 'box',
          width: measureFn(match[1]),
          text: match[1],
          pos: match.index,
          len: match[1].length
        })
      }
    }

    // Finishing glue (infinitely stretchable) + forced break
    var end = text.length
    items.push({ type: 'glue', width: 0, stretch: 1e6, shrink: 0, pos: end })
    items.push({ type: 'penalty', width: 0, penalty: -1e6, pos: end })

    return items
  }

  // ============ Knuth-Plass Optimal Breaking ============

  function computeBreaks(items, lineWidth) {
    var tol = CONFIG.tolerance
    var lp = CONFIG.linePenalty

    var active = [{
      idx: 0, line: 0,
      sumW: 0, sumY: 0, sumZ: 0,
      dem: 0, prev: null
    }]

    var W = 0, Y = 0, Z = 0

    for (var i = 0; i < items.length; i++) {
      var it = items[i]

      if (it.type === 'box') {
        W += it.width
      }

      // Legal breakpoint: at penalty (not infinite), or at glue preceded by box
      var canBreak =
        (it.type === 'penalty' && it.penalty < 1e6) ||
        (it.type === 'glue' && i > 0 && items[i - 1].type === 'box')

      if (canBreak) {
        var next = []
        var bestNode = null
        var bestDem = Infinity

        for (var j = 0; j < active.length; j++) {
          var a = active[j]
          var cw = W - a.sumW
          var r

          if (cw < lineWidth) {
            var stretch = Y - a.sumY
            r = stretch > 0 ? (lineWidth - cw) / stretch : 1e6
          } else if (cw > lineWidth) {
            var shrink = Z - a.sumZ
            r = shrink > 0 ? (lineWidth - cw) / shrink : -1e6
          } else {
            r = 0
          }

          // Keep active if not hopelessly compressed
          if (r >= -1) next.push(a)

          // Feasible break
          if (r >= -1 && r <= tol) {
            var bad = 100 * Math.pow(Math.abs(r), 3)
            var pen = it.type === 'penalty' ? it.penalty : 0
            var d

            if (pen >= 0) {
              d = Math.pow(lp + bad + pen, 2)
            } else if (pen > -1e6) {
              d = Math.pow(lp + bad, 2) - pen * pen
            } else {
              d = Math.pow(lp + bad, 2)
            }

            d += a.dem

            if (d < bestDem) {
              bestDem = d
              bestNode = {
                idx: i, line: a.line + 1,
                sumW: W, sumY: Y, sumZ: Z,
                dem: d, prev: a
              }
            }
          }
        }

        if (bestNode) next.push(bestNode)
        if (next.length > 0) active = next
      }

      if (it.type === 'glue') {
        W += it.width
        Y += it.stretch
        Z += it.shrink
      }
    }

    // Best ending node — trace back for breakpoints
    var best = active[0]
    for (var k = 1; k < active.length; k++) {
      if (active[k].dem < best.dem) best = active[k]
    }

    var breaks = []
    while (best.prev) {
      breaks.unshift(best.idx)
      best = best.prev
    }
    return breaks
  }

  // ============ Build Lines from Breaks ============

  function buildLines(items, breaks) {
    var lines = []
    var lineWords = []

    var breakSet = {}
    for (var b = 0; b < breaks.length; b++) breakSet[breaks[b]] = true

    for (var i = 0; i < items.length; i++) {
      if (items[i].type === 'box') {
        lineWords.push(items[i].text)
      }
      if (breakSet[i] && lineWords.length > 0) {
        lines.push(lineWords.join(' '))
        lineWords = []
      }
    }
    if (lineWords.length > 0) lines.push(lineWords.join(' '))

    return lines
  }

  // ============ Canvas Measurement ============

  var _ctx = null

  function initMeasurer() {
    var canvas = document.createElement('canvas')
    _ctx = canvas.getContext('2d')
    var style = getComputedStyle(document.body)
    _ctx.font = style.fontSize + ' ' + style.fontFamily
  }

  function measure(text) {
    return _ctx.measureText(text).width
  }

  // ============ DOM Integration ============

  var originals = new Map()

  function getTextNodes(node) {
    var nodes = []
    var walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT)
    while (walker.nextNode()) nodes.push(walker.currentNode)
    return nodes
  }

  // Build mapping: normalized char position → { textNode, rawOffset }
  function buildCharMap(paragraph) {
    var textNodes = getTextNodes(paragraph)
    var map = []
    var normPos = 0
    var started = false
    var prevWasSpace = false

    for (var t = 0; t < textNodes.length; t++) {
      var raw = textNodes[t].textContent
      for (var i = 0; i < raw.length; i++) {
        var isSpace = /\s/.test(raw[i])

        if (!started) {
          if (isSpace) continue
          started = true
        }

        if (isSpace) {
          if (!prevWasSpace) {
            map[normPos] = { node: textNodes[t], offset: i }
            normPos++
          }
          prevWasSpace = true
        } else {
          map[normPos] = { node: textNodes[t], offset: i }
          normPos++
          prevWasSpace = false
        }
      }
    }

    return map
  }

  function insertBreaksIntoDOM(paragraph, breakPositions) {
    var charMap = buildCharMap(paragraph)

    // Group breaks by text node
    var nodeBreaks = new Map()
    for (var i = 0; i < breakPositions.length; i++) {
      var entry = charMap[breakPositions[i]]
      if (!entry) continue
      if (!nodeBreaks.has(entry.node)) nodeBreaks.set(entry.node, [])
      nodeBreaks.get(entry.node).push(entry.offset)
    }

    // For each text node with breaks, split and insert <br>
    nodeBreaks.forEach(function (offsets, node) {
      offsets.sort(function (a, b) { return a - b })

      var raw = node.textContent
      var parent = node.parentNode
      var frag = document.createDocumentFragment()
      var lastIdx = 0

      for (var j = 0; j < offsets.length; j++) {
        var offset = offsets[j]

        // Text before this break point
        var before = raw.substring(lastIdx, offset)
        // Trim trailing whitespace from the line
        before = before.replace(/\s+$/, '')
        if (before) frag.appendChild(document.createTextNode(before))

        frag.appendChild(document.createElement('br'))

        // Skip whitespace after the break
        var wsEnd = offset
        while (wsEnd < raw.length && /\s/.test(raw[wsEnd])) wsEnd++
        lastIdx = wsEnd
      }

      // Remaining text after last break
      var remaining = raw.substring(lastIdx)
      if (remaining) frag.appendChild(document.createTextNode(remaining))

      parent.replaceChild(frag, node)
    })
  }

  function shouldProcess(p) {
    for (var i = 0; i < CONFIG.skipSelectors.length; i++) {
      if (p.closest(CONFIG.skipSelectors[i])) return false
    }
    var text = p.textContent.trim()
    if (text.split(/\s+/).length < CONFIG.minWords) return false
    return true
  }

  function layoutParagraph(p, containerWidth) {
    // Save original DOM on first pass
    if (!originals.has(p)) {
      originals.set(p, p.cloneNode(true))
    } else {
      // Restore original before re-layout
      var orig = originals.get(p)
      p.innerHTML = orig.innerHTML
    }

    // Normalize: collapse whitespace, trim
    var normText = p.textContent.replace(/\s+/g, ' ').trim()
    if (normText.split(' ').length < CONFIG.minWords) {
      p.style.visibility = 'visible'
      return
    }

    var items = tokenize(normText, measure)
    var breaks = computeBreaks(items, containerWidth)

    // Get character positions of break points (skip the forced final break)
    var breakPositions = []
    for (var i = 0; i < breaks.length - 1; i++) {
      breakPositions.push(items[breaks[i]].pos)
    }

    if (breakPositions.length === 0) {
      p.style.visibility = 'visible'
      return
    }

    insertBreaksIntoDOM(p, breakPositions)
    p.style.textAlign = 'justify'
    p.style.visibility = 'visible'
  }

  function layoutAll() {
    initMeasurer()
    var paragraphs = document.querySelectorAll(CONFIG.selector)
    for (var i = 0; i < paragraphs.length; i++) {
      var p = paragraphs[i]
      if (!shouldProcess(p)) {
        p.style.visibility = 'visible'
        continue
      }
      var width = p.clientWidth
      if (width > 0) layoutParagraph(p, width)
    }
  }

  // ============ Resize ============

  var resizeTimer
  var lastWidth = 0

  function onResize() {
    var main = document.querySelector('main')
    if (!main) return
    var w = main.clientWidth
    if (w === lastWidth) return
    lastWidth = w
    clearTimeout(resizeTimer)
    resizeTimer = setTimeout(layoutAll, CONFIG.debounceMs)
  }

  // ============ Init ============

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function () {
      document.fonts.ready.then(function () {
        layoutAll()
        var main = document.querySelector('main')
        if (main) lastWidth = main.clientWidth
        window.addEventListener('resize', onResize)
      })
    })
  }

  return { tokenize: tokenize, computeBreaks: computeBreaks, buildLines: buildLines }
})()

// Node.js export for testing
if (typeof module !== 'undefined' && module.exports) {
  module.exports = PretextLayout
}
```

- [ ] **Step 3: Run tests**

Run: `node scripts/test-knuth-plass.mjs`

Expected output:
```
PASS: tokenize produces correct boxes
PASS: single line needs no break
PASS: multi-line breaking produces valid output
PASS: optimal breaking with varied word lengths
PASS: buildLines reconstructs text correctly

All tests passed!
```

- [ ] **Step 4: Commit**

```bash
git add scripts/pretext-layout.js scripts/test-knuth-plass.mjs
git commit -m "feat: implement Knuth-Plass optimal line breaking algorithm

Canvas-based word measurement and dynamic programming over
box-glue-penalty items. Includes DOM integration with inline
element preservation and debounced resize handling."
```

---

### Task 2: CSS Changes

**Files:**
- Modify: `styles.css:212-230` (prose alignment section)
- Modify: `styles.css:416-424` (misc card override)

- [ ] **Step 1: Remove CSS text-wrapping rules, add FOUC prevention**

In `styles.css`, replace the prose alignment section (lines 212-230):

**Before:**
```css
#quarto-document-content p {
  text-wrap: pretty;
}

@media (min-width: 48rem) {
  #quarto-document-content p {
    text-align: justify;
    text-justify: inter-word;
    -webkit-hyphens: auto;
    -ms-hyphens: auto;
    hyphens: auto;
  }

  @supports (hyphenate-limit-chars: 7) {
    #quarto-document-content p {
      hyphenate-limit-chars: 7;
    }
  }
}
```

**After:**
```css
#quarto-document-content p {
  visibility: hidden;
}
```

Also update the misc-card paragraph override (lines 416-424). Remove the now-unnecessary justify/hyphens overrides:

**Before:**
```css
#quarto-document-content .misc-card p {
  margin-bottom: 0.7rem;
  color: #555;
  text-align: left;
  text-justify: auto;
  -webkit-hyphens: none;
  -ms-hyphens: none;
  hyphens: none;
}
```

**After:**
```css
#quarto-document-content .misc-card p {
  margin-bottom: 0.7rem;
  color: #555;
  visibility: visible;
}
```

- [ ] **Step 2: Commit**

```bash
git add styles.css
git commit -m "style: replace CSS text wrapping with FOUC prevention for JS layout"
```

---

### Task 3: Quarto Integration

**Files:**
- Modify: `_quarto.yml`

- [ ] **Step 1: Add script and noscript fallback to _quarto.yml**

Add `include-after-body` with the script and a `<noscript>` fallback under `format.html`:

**Before:**
```yaml
format:
  html:
    theme: cosmo
    css: styles.css
    toc: false
    code-copy: true
    mainfont: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
```

**After:**
```yaml
format:
  html:
    theme: cosmo
    css: styles.css
    toc: false
    code-copy: true
    mainfont: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
    include-after-body:
      text: |
        <script src="scripts/pretext-layout.js"></script>
        <noscript><style>
          #quarto-document-content p {
            visibility: visible !important;
            text-wrap: pretty;
          }
          @media (min-width: 48rem) {
            #quarto-document-content p {
              text-align: justify;
              text-justify: inter-word;
              hyphens: auto;
            }
          }
        </style></noscript>
```

- [ ] **Step 2: Add scripts directory to Quarto resources**

In `_quarto.yml`, add scripts to project resources so they're copied to `_site/`:

**Before:**
```yaml
project:
  type: website
  output-dir: _site
  resources:
    - .nojekyll
```

**After:**
```yaml
project:
  type: website
  output-dir: _site
  resources:
    - .nojekyll
    - scripts/pretext-layout.js
```

- [ ] **Step 3: Commit**

```bash
git add _quarto.yml
git commit -m "build: integrate pretext-layout.js into Quarto site"
```

---

### Task 4: Verify and Fix

- [ ] **Step 1: Run Quarto preview**

```bash
cd "/Users/shusukeioku/Dropbox/My Mac (Shusukes-MacBook-Air.local)/Documents/Project/_portfolio"
quarto preview
```

Open the local preview in browser. Check:
- Index page: about text paragraphs are justified with optimal breaks, links and emphasis preserved
- Research page: abstracts are skipped (inside `.pub-entry`), any free paragraphs are optimized
- Misc page: card text is skipped (inside `.misc-card`), visible immediately
- Resize the browser window: paragraphs re-layout smoothly after debounce

- [ ] **Step 2: Fix any issues found during testing**

Common issues to check:
- FOUC: paragraphs should not flash unstyled before JS kicks in
- Inline elements: links in about text should remain clickable
- Short paragraphs (< 4 words): should be visible immediately without optimization
- Mobile: paragraphs should still be optimized at narrow widths

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "fix: address issues found during manual testing"
```

(Only if fixes were needed.)
