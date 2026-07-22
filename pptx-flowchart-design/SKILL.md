---
name: pptx-flowchart-design
description: |
  Use when authoring a flowchart, workflow diagram, or decision tree in a .pptx
  slide via python-pptx — especially anything with decision diamonds, retry
  loops, or multiple flow directions that must fit on a single 16:9 slide.
  Distills lessons from real slide-building sessions: OOXML gotchas that
  trigger PowerPoint "repair" prompts, arrow-styling patterns that keep the
  visual language consistent, layout principles that use the full canvas, and
  safe editing patterns that don't corrupt the file.
triggers:
  - build flowchart pptx
  - workflow diagram slide
  - flowchart python-pptx
  - decision tree slide
---

# Flowchart Design for PPTX

Building a flowchart in a .pptx slide via python-pptx is deceptively easy to
get wrong. Symbols crowd, arrows look mismatched, PowerPoint asks to repair
the file, and iteration overwrites your own work. This skill collects the
non-obvious lessons.

## Design plan comes first (never skip)

Before code, sketch a compact plan in ~4 lines:

- **Palette** — 4-6 named hex values with roles. Pick colors from the deck's
  existing slides so the flowchart lands as part of the deck, not a foreign
  object. Reserve ONE accent color for decisions AND retry paths so the eye
  learns that orange (or whatever) means "branch / recover."
- **Type** — Georgia serif for action labels, Calibri sans for eyebrows and
  step markers, italics reserved for decisions. Don't mix in a third face.
- **Layout** — grid of rows and columns with fixed center coordinates. Every
  shape is placed by its center; sizes are constants. Reflows become one-line
  edits.
- **Flow direction** — for a 16:9 slide with 6+ nodes, mix directions
  (serpentine): Row 1 flows L→R, drops down, Row 2 flows R→L, drops down,
  Row 3 mixed. Single-direction flows (all L→R or all top-down) leave half
  the canvas empty and force every symbol to shrink.

## Reuse the deck's node style

If other slides in the deck already use a card style (e.g., a colored top
strip + white body), reuse that treatment for the flowchart's action nodes,
just shrunk to node size. Same colored header meaning, same body font, same
border. This makes the flowchart read as continuation of the deck rather than
a standalone diagram.

Decisions are the exception: they should look *different* from actions.
Convention: unfilled diamonds outlined in the accent color, italic accent
text, small "◆ · ROUTE" or "◆ · CHECK" letter-spaced marker above.

Terminals (start / end): same card grammar as actions, but distinct fill
colors (brand for start, success color for end). Keeps everything on one
visual system.

## Grid layout (3 × 3 for a full 16:9)

Slide dimensions: `13.33″ × 7.5″`. Reserve `~2.0″` at the top for eyebrow +
title + subtitle. That leaves `~5.5″` for the diagram.

```
COL_L = 2.15″   COL_M = 6.665″   COL_R = 11.18″   (column centers)
ROW_1 = 2.80″   ROW_2 = 4.60″    ROW_3 = 6.30″    (row centers)
```

Node sizes stay constant across the diagram:

```
CARD_W = 2.55″   CARD_H = 0.85″    (colored header 0.28 + body 0.57)
DIA_W  = 2.90″   DIA_H  = 0.85″    (decisions — same H so rows align)
```

Never stretch a symbol to fit. If it doesn't fit, drop a node, merge two,
or move to a different column — the sizes are constants.

## Coordinates must be integer EMU

**Any float coordinate in the OOXML makes PowerPoint prompt to "repair" the
file.** python-pptx's `Inches()` and `Emu()` accept floats and pass them
through; arithmetic like `Inches(2) / 2` returns a float, and it silently
becomes `"3406140.0"` in the XML. This is the single most common cause of a
"repair" prompt on a script-generated deck.

Fix with a coercion helper at the top of every script:

```python
from pptx.util import Emu

def E(v):
    """Coerce any coordinate to integer EMU. Use everywhere."""
    return Emu(int(v))
```

Then wrap every coordinate passed to `add_shape`, `add_textbox`,
`add_connector`, `add_line`, and arrowhead helpers: `E(x)`, `E(y)`, `E(w)`,
`E(h)`. If a script produces a repair prompt, grep the extracted slide XMLs
for float coordinates:

```bash
python3 -c "
import re, glob
for f in glob.glob('ppt/slides/*.xml'):
    xml = open(f).read()
    floats = re.findall(r'\"(\d+\.\d+)\"', xml)
    if floats: print(f, floats[:5])
"
```

## Arrows — one style everywhere

Two rules keep arrows visually consistent:

1. **Every line uses the same weight.** Pick one (`Pt(1.25)` is a good
   default) and use it for main flow, decisions, and retry paths. Only the
   **color** varies (deck-navy for main, accent for retry).
2. **Use native OOXML `tailEnd` triangles, not MSO_SHAPE arrows.** Separate
   MSO_SHAPE.RIGHT_ARROW / DOWN_ARROW shapes look chunky against thin lines,
   and their size doesn't scale with line weight.

Helper for a native arrowhead on any connector:

```python
from lxml import etree
from pptx.oxml.ns import qn
from pptx.enum.shapes import MSO_CONNECTOR
from pptx.util import Pt

LINE_W = Pt(1.25)   # ONE weight for the whole diagram

def add_segment(slide, x1, y1, x2, y2, *, color, arrow=False):
    ln = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
                                    E(x1), E(y1), E(x2), E(y2))
    ln.line.color.rgb = color
    ln.line.width = LINE_W
    if arrow:
        lnEl = ln.line._get_or_add_ln()
        tail = lnEl.find(qn("a:tailEnd"))
        if tail is None:
            tail = etree.SubElement(lnEl, qn("a:tailEnd"))
        tail.set("type", "triangle")
        tail.set("w", "med")
        tail.set("len", "med")
    return ln
```

**Multi-segment paths** (elbows, retry loops): draw as a chain of straight
segments, but only put `arrow=True` on the **final segment**. That way the
retry loop looks like a single connector with one arrowhead, matching the
straight arrows on the main flow.

```python
# retry loop: right → up → left, arrowhead only on final left segment
add_segment(s, diag_right, ROW_3, loop_x,      ROW_3, color=ORANGE)
add_segment(s, loop_x,      ROW_3, loop_x,     ROW_2, color=ORANGE)
add_segment(s, loop_x,      ROW_2, prep_right, ROW_2, color=ORANGE, arrow=True)
```

## Retry lanes: consolidate

If the workflow has multiple decisions that all funnel into a retry step,
route them into a **single** callout with **one** loop-back path — don't
draw parallel retry lanes for each failure branch. Parallel loops force the
eye to trace multiple arrows and quickly turn into visual noise.

```
CHECK 1 ──NO──┐
              ├──→ [Diagnose · repair · pivot] ──loop──→ Prepare
CHECK 2 ──NO──┘
```

One retry story, told once.

## Editing an existing pptx safely

python-pptx has **no slide-delete API**, and rolling your own with
`prs.slides._sldIdLst.remove(...)` + `part.drop_rel(...)` leaves orphaned
slide parts in the zip. The next slide you add gets the same filename and
you get a corrupted deck (`UserWarning: Duplicate name: ppt/slides/slideN.xml`)
that PowerPoint can't open at all.

**Safe patterns:**

- **Rebuild a slide's contents in place** — find the slide by text, remove
  all its shapes from `spTree`, then re-add shapes. The slide part stays; no
  orphans:

  ```python
  def clear_slide(slide):
      spTree = slide.shapes._spTree
      for shape in list(slide.shapes):
          spTree.remove(shape._element)

  def slide_has_text(slide, needle):
      for sh in slide.shapes:
          if sh.has_text_frame and needle in sh.text_frame.text:
              return True
      return False

  target = next(s for s in prs.slides if slide_has_text(s, "MY MARKER"))
  clear_slide(target)
  # ... rebuild target ...
  ```

- **Insert a new slide at position N** — `add_slide()` puts it last, then
  move it via `_sldIdLst`:

  ```python
  s = prs.slides.add_slide(prs.slide_layouts[6])
  # ... populate s ...
  xml_slides = prs.slides._sldIdLst
  new_el = list(xml_slides)[-1]
  xml_slides.remove(new_el)
  xml_slides.insert(N - 1, new_el)   # 0-indexed
  ```

- **DON'T call `part.drop_rel(rId)`.** Even though the API accepts it, it
  desyncs the zip and leaves orphaned slide XML parts. Instead: leave the
  slide in place and either clear its shapes to blank it, or accept the
  extra slide.

**Repairing a corrupted pptx** (if a prior script produced one): unzip,
edit `ppt/presentation.xml` to drop bogus `<p:sldId ... r:id="rIdN"/>`
entries, drop matching `<Relationship Id="rIdN" .../>` from
`ppt/_rels/presentation.xml.rels`, rezip.

## Text on shapes — the frame boilerplate

Every time you add text on a shape, four things:

```python
def label_shape(shape, text, *, size=12, bold=True, color=NAVY,
                font="Georgia", italic=False, align=PP_ALIGN.CENTER):
    tf = shape.text_frame
    tf.margin_left = Emu(40000)          # tight but not zero
    tf.margin_right = Emu(40000)
    tf.margin_top = Emu(15000)
    tf.margin_bottom = Emu(15000)
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE  # so text centers vertically
    # ... write runs ...
```

Skipping `margin` or `vertical_anchor` gives text that hugs the top edge or
overflows the shape. Zero margins push text against the border and look
cramped — `40000 EMU ≈ 0.04″` is a good default.

**Letter-spacing on eyebrows** (small caps look) via OOXML directly:

```python
r = p.add_run()
r.text = "AGENT WORKFLOW"
r.font.size = Pt(13)
r.font.bold = True
rPr = r._r.get_or_add_rPr()
rPr.set("spc", "200")   # hundredths of a point → 2.0pt tracking
```

## Verify visually before delivering

python-pptx and LibreOffice sometimes disagree with PowerPoint on rendering.
Render the pptx to JPGs and eyeball them before claiming the slide is done:

```bash
soffice --headless --convert-to pdf --outdir /tmp/thumbs deck.pptx
pdftoppm -r 100 -jpeg /tmp/thumbs/deck.pdf /tmp/thumbs/slide
# then Read /tmp/thumbs/slide-N.jpg
```

Common issues to look for in the render:
- Text overflow past shape bounds (fix: shrink label, widen shape, or split)
- Arrowheads pointing wrong direction (line endpoint order matters)
- Symbols cropped at slide edge (fix: bring closer to center, don't shrink)
- Retry paths crossing other lines (fix: route through a farther lane)

## When told "the flowchart looks cramped / ugly"

Diagnose in this order:

1. **Too many competing lanes** — parallel retry paths, side annotations,
   route chips all fighting for the right margin. Consolidate to one lane.
2. **Diamonds squashed** — decision shapes need `~30% wider than tall`. If
   yours are square-ish, they look like flat rectangles at slide zoom.
3. **Left half empty, right half packed** — you have a one-direction flow
   pushed into one half. Adopt serpentine layout.
4. **Node sizes vary** — action rects at one size, "combined action + check"
   at another. Standardize sizes; if that means dropping a node, drop it.
5. **Left annotations + right annotations + top annotations** — too many
   satellites. Pick one side for step markers, leave the others quiet.
6. **Font/weight variety** — Georgia + Calibri + Consolas + italic +
   letter-spaced + bold, all fighting. Pair two faces, reserve italic for
   decisions, use letter-spacing only on eyebrows.

## Skeleton to copy

```python
from pptx import Presentation
from pptx.util import Inches, Emu, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn
from lxml import etree

# --- palette (from deck) ---
BG = RGBColor(0xF4, 0xF6, 0xF9); NAVY = RGBColor(0x1B, 0x2A, 0x41)
TEAL = RGBColor(0x0C, 0x85, 0x99); ORANGE = RGBColor(0xE6, 0x77, 0x00)
GREEN = RGBColor(0x2F, 0x9E, 0x44); WHITE = RGBColor(0xFF, 0xFF, 0xFF)

LINE_W = Pt(1.25)

def E(v): return Emu(int(v))

# --- open, locate target slide, clear it ---
prs = Presentation("deck.pptx")
target = next(s for s in prs.slides
              if any(sh.has_text_frame and "MARKER" in sh.text_frame.text
                     for sh in s.shapes))
for shape in list(target.shapes):
    target.shapes._spTree.remove(shape._element)

# --- background + rail ---
# ... (as above) ...

# --- grid ---
COL_L, COL_M, COL_R = Inches(2.15), Inches(6.665), Inches(11.18)
ROW_1, ROW_2, ROW_3 = Inches(2.80), Inches(4.60), Inches(6.30)
CARD_W, CARD_H = Inches(2.55), Inches(0.85)

# --- helpers: phase_card, decision, add_segment (as above) ---

# --- build serpentine flow ---
# Row 1 L→R: START → INTAKE → TIER?
# Drop through chip row
# Row 2 R→L: PREPARE ← EXECUTE ← CHECK?
# Row 3: DELIVER (YES) + DIAGNOSE (NO) + retry loop back to PREPARE

prs.save("deck.pptx")
```

## Anti-patterns

- Building a flowchart out of MSO_SHAPE.RIGHT_ARROW blocks. Use lines +
  native OOXML tailEnd, always.
- Different node widths per row "because that's what fits." Choose ONE
  width, drop or merge nodes to make it work.
- A left-side annotation column for phase names + a right-side retry lane +
  chip fanouts off the tier diamond, all at once. Pick one satellite lane.
- Serif italic for main labels. Serif italic reads as decoration or code —
  keep it for decision labels only.
- Trying to make the script idempotent by removing + re-adding slides.
  Rebuild in place with `clear_slide`. If you must delete, unzip and repair
  the XML by hand.
