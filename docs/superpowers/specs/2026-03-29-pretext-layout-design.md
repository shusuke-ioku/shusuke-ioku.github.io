# Pretext Optimal Line Breaking — Design Spec

**Date:** 2026-03-29
**Status:** Approved

## Problem

The portfolio site uses CSS `text-wrap: pretty` with justified text and hyphenation. CSS line breaking is greedy (breaks line-by-line without considering the paragraph as a whole), which produces suboptimal results — uneven spacing, poor break choices, and visible "rivers" of whitespace in justified text.

## Solution

Replace CSS-driven line breaking with JavaScript-powered **Knuth-Plass optimal paragraph layout**, using `@chenglou/pretext` for text measurement. This produces globally optimal break points that minimize total "badness" across all lines in a paragraph.

## Scope

All prose paragraphs site-wide: `#quarto-document-content p` elements. Does not apply to card text, publication metadata, or other non-prose elements.

## Architecture

### Components

**Single file: `scripts/pretext-layout.js`**

Contains three logical parts:

1. **Measurement layer** — Uses `@chenglou/pretext`'s `prepare()` and `walkLineRanges()` APIs to measure text segments via canvas. Handles mixed-width characters (Japanese text in teaching/research sections, emoji, etc.) correctly.

2. **Knuth-Plass breaking algorithm** — Takes measured segments and container width, returns optimal break points:
   - Tokenizes paragraph into boxes (word segments), glue (stretchable/shrinkable spaces), and penalties (possible break points)
   - For each feasible break point, computes adjustment ratio (how much glue must stretch/compress)
   - Scores breaks with demerits function: `(1 + badness + penalty)^2`
   - Dynamic programming finds the break sequence minimizing total demerits
   - Final line is left-aligned (standard typographic practice)

3. **DOM integration** — Selects paragraphs, applies computed breaks, handles resize:
   - On `DOMContentLoaded`: processes all target paragraphs
   - Stores original text content for re-layout
   - Inserts `<br>` tags at computed break points
   - Wraps justified lines in spans with `text-align: justify`
   - Last line of each paragraph left-aligned
   - Debounced resize handler (~150ms) re-runs breaking when container width changes

### Knuth-Plass Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `tolerance` | 3 | Max acceptable badness before forced break |
| `hyphenPenalty` | 50 | Cost of hyphenating (discourages but allows) |
| `linePenalty` | 10 | Base cost per line break |

### Measurement Details

The site uses Inconsolata (monospace), but Japanese text and potential emoji break the equal-width assumption. pretext's canvas-based measurement handles all of these correctly via `prepare(text, font)`.

Measurement results are cached per paragraph. On resize, only the breaking algorithm re-runs with the new width — `prepare()` is not called again.

## FOUC Prevention

1. CSS rule: `#quarto-document-content p { visibility: hidden }`
2. After JS layout completes: flip to `visibility: visible`
3. No-JS fallback via `<noscript><style>` block restores visibility and keeps existing CSS wrapping

## CSS Changes

**Remove from `styles.css`:**
- `text-wrap: pretty` from `#quarto-document-content p`
- `text-align: justify` and `text-justify: inter-word` from the desktop media query
- Hyphenation rules (`hyphens: auto`, `hyphenate-limit-chars`) — JS handles breaking

**Add to `styles.css`:**
- `#quarto-document-content p { visibility: hidden }` for FOUC prevention

**Keep unchanged:**
- Font, size, line-height, letter-spacing
- All card, publication, and talk styling
- Responsive layout and media queries (other than the justify rules)

**No-JS fallback (in page template):**
```html
<noscript><style>
  #quarto-document-content p {
    visibility: visible !important;
    text-wrap: pretty;
    text-align: justify;
    hyphens: auto;
  }
</style></noscript>
```

## Quarto Integration

In `_quarto.yml`, add the script via `include-after-body` so it executes after page content is rendered.

## Dependency

`@chenglou/pretext` — bundled directly into `scripts/pretext-layout.js` (no CDN, no runtime dependency). This keeps the static site self-contained.

## Performance

- `prepare()`: ~19ms for 500 texts (one-time on page load)
- Knuth-Plass per paragraph: negligible (pure arithmetic over cached measurements)
- Total page load impact: <50ms for all paragraphs
- Resize re-layout: cheaper since measurement is cached, only breaking re-runs

## Resize Handling

- Debounce resize events at ~150ms
- Skip re-layout if container width unchanged (height-only changes)
- Re-run Knuth-Plass on all paragraphs with new width
- Re-render break points in DOM

## Text Remains Selectable

pretext is used only for measurement. Text stays as normal HTML — `<br>` tags for line breaks, `<span>` wrappers for justification. Fully selectable, copyable, and accessible.

## Files Changed

| File | Change |
|------|--------|
| `scripts/pretext-layout.js` | New — measurement, Knuth-Plass, DOM integration |
| `styles.css` | Remove CSS wrapping/justify rules, add FOUC prevention |
| `_quarto.yml` | Add script include |
