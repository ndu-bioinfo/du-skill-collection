---
name: pptx-slide-design
description: |
  Use when authoring or editing a .pptx deck via python-pptx, or when
  reviewing one for style. Distills general slide-styling craft — type
  sizes and hierarchy, palette discipline, card patterns, safe editing of
  existing decks, and OOXML gotchas — that apply to any deck, not just
  flowcharts. Pair with pptx-flowchart-design when a slide contains a
  workflow diagram.
triggers:
  - build pptx deck
  - style pptx slide
  - python-pptx design
  - powerpoint styling
---

# PPTX Slide Design

Building slides via python-pptx is not the same as writing text into an editor.
Every shape, color, coordinate, and font size is code — which means it either
looks considered or it looks generated. This skill collects the patterns and
rules that reliably move a scripted deck out of the "generated" bucket.

## Design plan first (never skip)

Before writing shape code, sketch a compact plan in ~4 lines:

- **Palette** — 4-6 hex values with named roles. Whole deck, not per slide.
- **Type** — 2-3 typefaces with intended use per size tier.
- **Layout** — grid concept (rows/columns), margins, brand rail.
- **The job of each slide** — one sentence per slide describing its one
  message; if you can't state it in a sentence, the slide is doing too much.

Ad-hoc styling drifts across slides. A plan gives every slide the same
foundation.

## Type — sizes are the #1 issue

**Legibility floor: 14pt for body text.** Sub-14pt reads as "too small" in
conference rooms and on shared thumbnails. Every scripted deck defaults to
tiny type — check your sizes twice before shipping.

Hierarchy table:

| Role                      | Range     |
| ------------------------- | --------- |
| Cover title               | 44–60 pt  |
| Slide title               | 26–32 pt  |
| Subtitle / lead paragraph | 15–18 pt  |
| Body / card content       | 14–16 pt  |
| Small labels (eyebrow, step marker, tag) | 11–13 pt |
| Stat numbers / KPI hero   | 44–64 pt  |
| Footnotes / disclaimers   | 10–11 pt  |

Rule of thumb: **title ≥ 2.5× body size.** If body is 15pt, title should
be 30pt+. Flat hierarchy reads as underdesigned.

**Type pairing (default that just works):**

- **Georgia** (serif) — editorial titles, card body labels
- **Calibri** (sans) — eyebrows, ALL-CAPS labels, metadata, footnotes
- **Reserve italics for one purpose** — callouts, or decision labels, or
  quotes. Don't mix italic uses in one deck; it collapses hierarchy.

**Letter-spacing** on ALL-CAPS eyebrows via OOXML (not natively exposed by
python-pptx):

```python
rPr = run._r.get_or_add_rPr()
rPr.set("spc", "200")   # hundredths of a point → 2.0pt tracking
```

## Palette discipline

Whole-deck palette, not per-slide. Cap at 6 hues:

- **1 brand accent** — used on the eyebrow, brand rail, start states.
- **1 attention/alert color** — decisions, warnings, retries.
- **2-3 supporting neutrals** — text, ground, subtle borders.
- **1 success color** (optional) — completions, positive outcomes.

Cool grays over warm grays for corporate/technical decks. **Ground:**
light gray-blue (`#F4F6F9`) reads softer than pure white and doesn't glare
on projectors. **Never pure red** (`#FF0000`) — too aggressive; use warm
orange (`#E67700`) or terracotta (`#C8664E`) for attention.

Example palette that ships every time:

| Token   | Hex       | Role                       |
| ------- | --------- | -------------------------- |
| INK     | `#1B2A41` | text, hairlines            |
| BG      | `#F4F6F9` | page ground                |
| BRAND   | `#0C8599` | brand accent (teal here)   |
| ALERT   | `#E67700` | decisions, retries         |
| SUCCESS | `#2F9E44` | endpoints, positive        |
| MUTED   | `#5A6B80` | small labels, secondary    |

## Layout — grid, margins, breathing room

- Canvas: **16:9 = 13.33″ × 7.5″** (`12192000 × 6858000` EMU)
- **Left brand rail**: `0.28″` colored strip, full height — a consistent
  identifier that lets slides read as "same deck" at a glance.
- Content margins: **0.9″ left, 0.5″ right** minimum
- Title zone: `y = 0` to `~2.0″` (eyebrow ~0.35″, title ~0.85″,
  subtitle ~0.35″, then breathing space)
- Content zone: `y = 2.5″` to `~7.0″` (~5.5″ of usable height)
- Bottom margin: `~0.5″`

**Grid-based placement.** Define row/column centers up front and place every
shape by center:

```python
COL_L, COL_M, COL_R = Inches(2.15), Inches(6.665), Inches(11.18)
ROW_1, ROW_2, ROW_3 = Inches(2.80), Inches(4.60), Inches(6.30)

def place(kind, cx, cy, w, h, fill, stroke=None):
    return add_shape(kind, cx - w/2, cy - h/2, w, h, fill, stroke)
```

Reflows become one-line edits; alignment stays exact across the deck.

## Card / node patterns that work

Two card treatments cover most deck needs:

**Header-strip card** — for "phased" or "categorized" content (e.g., slide 6
of a process deck):

```
┌────────────────────────────┐
│  ▊ 01  ·  PHASE ONE        │  ← 0.3″ colored strip, small caps + big Georgia number
├────────────────────────────┤
│                            │
│  Intake & Routing          │  ← Georgia Bold main label
│  Parse question, pick tier │  ← smaller gray Calibri description
│                            │
└────────────────────────────┘
```

**Accent-bar card** — for less structured content (feature lists, KPIs):

```
┃▊ Natural-language          ┃
┃  User asks in plain English┃
┃                            ┃
```

A single colored bar (`0.1″` wide) on the left edge, white fill, subtle
hairline stroke. Cleaner than the header-strip card when you have many
cards to place.

## Text on shapes — the boilerplate you need every time

```python
def label_shape(shape, text, *, size=14, bold=True, color=INK,
                font="Georgia", align=PP_ALIGN.CENTER):
    tf = shape.text_frame
    tf.margin_left = Emu(40000)     # ~0.04″ — tight but not zero
    tf.margin_right = Emu(40000)
    tf.margin_top = Emu(15000)
    tf.margin_bottom = Emu(15000)
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE   # so text centers vertically
    p = tf.paragraphs[0]; p.alignment = align
    r = p.add_run(); r.text = text
    r.font.name = font
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.color.rgb = color
```

Skipping `margin_*` gives text hugging the top edge. Skipping
`vertical_anchor` gives labels flush-to-top in centered shapes. Zero
margins look cramped.

## The Integer EMU Rule

**All coordinates must be integers.** Float coordinates in OOXML trigger
PowerPoint's "repair the file" prompt. python-pptx's `Inches()` accepts
floats and passes them straight to XML; arithmetic like `Inches(2) / 2`
returns a float. This is the single most common cause of scripted decks
that PowerPoint won't open cleanly.

Fix with a coercion helper used everywhere:

```python
from pptx.util import Emu
def E(v): return Emu(int(v))
```

Wrap every coordinate: `E(x)`, `E(y)`, `E(w)`, `E(h)`. If a deck triggers
a repair prompt, grep the extracted slide XMLs for float coordinates:

```bash
python3 -c "
import re, glob
for f in glob.glob('ppt/slides/*.xml'):
    xml = open(f).read()
    floats = re.findall(r'\"(\d+\.\d+)\"', xml)
    if floats: print(f, floats[:5])
"
```

## Safe editing patterns for existing decks

python-pptx has **no slide-delete API**, and rolling your own with
`prs.slides._sldIdLst.remove(...)` + `part.drop_rel(...)` leaves orphaned
slide parts in the zip. The next slide you add gets the same filename,
and you get a corrupted deck PowerPoint refuses to open.

**Rebuild a slide's contents in place** — locate the slide by text marker,
remove all shapes from its `spTree`, then re-add. The slide part stays; no
orphans:

```python
def clear_slide(slide):
    for sh in list(slide.shapes):
        slide.shapes._spTree.remove(sh._element)

def slide_has_text(slide, needle):
    for sh in slide.shapes:
        if sh.has_text_frame and needle in sh.text_frame.text:
            return True
    return False

target = next(s for s in prs.slides if slide_has_text(s, "MY MARKER"))
clear_slide(target)
# ... rebuild target ...
```

**Insert a new slide at position N** — `add_slide()` puts it last, then
move it via `_sldIdLst`:

```python
s = prs.slides.add_slide(prs.slide_layouts[6])
# ... populate s ...
xml_slides = prs.slides._sldIdLst
new_el = list(xml_slides)[-1]
xml_slides.remove(new_el)
xml_slides.insert(N - 1, new_el)   # 0-indexed
```

**Global font bumps** — iterate every run, adjust based on current size:

```python
def new_size(pt):
    if pt >= 20:  return pt
    if pt >= 16:  return 17
    if pt >= 14:  return 15
    if pt >= 12:  return 14
    return max(11, pt + 2)

for slide in prs.slides:
    for shape in slide.shapes:
        if not shape.has_text_frame: continue
        for para in shape.text_frame.paragraphs:
            for run in para.runs:
                if run.font.size is None: continue
                pt = run.font.size.pt
                nsz = new_size(pt)
                if abs(nsz - pt) > 0.01:
                    run.font.size = Pt(nsz)
```

**Targeted text replacement** — for surgical edits without rebuilding:

```python
for slide in prs.slides:
    for shape in slide.shapes:
        if not shape.has_text_frame: continue
        for para in shape.text_frame.paragraphs:
            for run in para.runs:
                if run.text == "old text": run.text = "new text"
```

**Repairing a corrupted pptx** (if a prior script produced one): unzip,
edit `ppt/presentation.xml` to drop bogus `<p:sldId>` entries, drop
matching `<Relationship>` from `ppt/_rels/presentation.xml.rels`, rezip.

## Render-verify workflow

python-pptx and PowerPoint sometimes disagree on rendering. LibreOffice
(via `soffice --headless`) is a fair approximation of PowerPoint. Render
to PDF, split to JPGs, eyeball before delivering:

```bash
soffice --headless --convert-to pdf --outdir /tmp/thumbs deck.pptx
pdftoppm -r 90 -jpeg /tmp/thumbs/deck.pdf /tmp/thumbs/slide
# then Read /tmp/thumbs/slide-N.jpg
```

What to look for in each render:

- Text overflow past shape bounds
- Content cut off at slide edges (bottom especially — the 7.5″ mark)
- Fonts that looked OK at 100% but disappear at thumbnail zoom
- Bullets that wrap ugly (single word on a line, or mid-word breaks)
- Alignment drift between similar cards
- Colors that clash with the ground

## Content principles

- **One idea per slide.** If you need "and also", that's a second slide.
- **Bullets: 5-8 words max.** Longer means it's a sentence — write it as
  a sentence, not a bullet.
- **Data slides: lead with the number, explain second.** "13 requests
  resolved" as the headline, breakdown below.
- **Trim aggressively before shrinking fonts.** Sub-14pt text means the
  slide has too much content, not that you need smaller type.
- **White space is structure.** Empty slide regions are not wasted; they
  guide the eye.

## Common anti-patterns

- **Sub-14pt body text** — the #1 scripted-deck failure mode
- **More than 3 typefaces** in one deck — pick 2, add mono if you must
- **7+ colors per slide** — the eye can't hold that many meanings
- **Every card a different width** — pick one width, drop nodes to fit
- **Italic + bold + colored + letter-spaced in one text block** — pick
  ONE emphasis method per block
- **Zero-margin text on shapes** — reads as cramped, feels ugly
- **Trying to fit everything on one slide** — split, or delete the
  overflow content
- **Pure white ground with pure black text** — glares on projectors, use
  `#F4F6F9` + `#1B2A41` instead
- **Left-side annotations AND right-side annotations AND top annotations
  on the same slide** — pick one side for satellite content

## Skeleton to copy

```python
from pptx import Presentation
from pptx.util import Inches, Emu, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

# --- palette ---
BG = RGBColor(0xF4, 0xF6, 0xF9); INK = RGBColor(0x1B, 0x2A, 0x41)
BRAND = RGBColor(0x0C, 0x85, 0x99); ALERT = RGBColor(0xE6, 0x77, 0x00)
GO = RGBColor(0x2F, 0x9E, 0x44); MUTED = RGBColor(0x5A, 0x6B, 0x80)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)

def E(v): return Emu(int(v))

prs = Presentation()
prs.slide_width  = Inches(13.333)
prs.slide_height = Inches(7.5)
BLANK = prs.slide_layouts[6]

def add_slide(bg=BG):
    s = prs.slides.add_slide(BLANK)
    b = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0,
                           prs.slide_width, prs.slide_height)
    b.line.fill.background()
    b.fill.solid(); b.fill.fore_color.rgb = bg
    # brand rail
    r = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0,
                           Inches(0.28), prs.slide_height)
    r.line.fill.background()
    r.fill.solid(); r.fill.fore_color.rgb = BRAND
    return s

def header(s, eyebrow, title, subtitle=None):
    # eyebrow — Calibri Bold small caps, letter-spaced
    tb = s.shapes.add_textbox(Inches(0.9), Inches(0.55),
                              Inches(11), Inches(0.35))
    tf = tb.text_frame; tf.word_wrap = True
    p = tf.paragraphs[0]
    r = p.add_run(); r.text = eyebrow
    r.font.name = "Calibri"; r.font.size = Pt(13); r.font.bold = True
    r.font.color.rgb = BRAND
    rPr = r._r.get_or_add_rPr(); rPr.set("spc", "200")
    # title
    tb = s.shapes.add_textbox(Inches(0.9), Inches(0.95),
                              Inches(11.5), Inches(0.9))
    tf = tb.text_frame; tf.word_wrap = True
    p = tf.paragraphs[0]
    r = p.add_run(); r.text = title
    r.font.name = "Georgia"; r.font.size = Pt(30); r.font.bold = True
    r.font.color.rgb = INK
    # subtitle
    if subtitle:
        tb = s.shapes.add_textbox(Inches(0.9), Inches(1.90),
                                  Inches(11.5), Inches(0.35))
        tf = tb.text_frame; tf.word_wrap = True
        p = tf.paragraphs[0]
        r = p.add_run(); r.text = subtitle
        r.font.name = "Calibri"; r.font.size = Pt(15)
        r.font.color.rgb = MUTED

s = add_slide()
header(s, "WHAT WE BUILT",
       "A single-endpoint natural-language interface.",
       "One question in. Structured, validated results out.")
# ... content ...

prs.save("deck.pptx")
```

## OOXML tricks worth knowing

| Trick | How |
|---|---|
| Letter spacing on a run | `rPr.set("spc", "200")` under `<a:rPr>` (hundredths of pt) |
| Native tail arrow on connector | Append `<a:tailEnd type="triangle" w="med" len="med"/>` under `<a:ln>` |
| Turn line off | `shape.line.fill.background()` (NOT `None`) |
| Solid fill assignment | `shape.fill.solid()` FIRST, then `fill.fore_color.rgb = color` |
| Vertical text anchor | `MSO_ANCHOR.MIDDLE` on `text_frame.vertical_anchor` |
| Text wrap in shape | `text_frame.word_wrap = True` |
| Get raw font size | `run.font.size.pt` (may be `None` if inherited) |
| Access the connector's line XML | `connector.line._get_or_add_ln()` |
