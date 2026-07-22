#!/usr/bin/env python3
"""Render prompt-coach worklog telemetry into legended, length-bounded views for the
/prompt-coach summary report. Deterministic — the chart and stats are computed here,
never hand-authored by the model, so they are always correct and consistently
formatted regardless of session length.

A real session is 50-80 turns, so a per-turn table would swamp the report. This
emits instead:
  1. a ROLLUP table  — session aggregates (peak/mean/final fill, chain-breaks, cache)
  2. a NOTABLE-TURNS table — only the turns worth reading (start, peak fill, every
     chain-break, ≥75% crossings, biggest category spikes, lowest cache-hit, end),
     capped so it stays short however long the session is
  3. a multi-series line chart WITH A LEGEND (distinct colour + marker per series),
     as self-contained inline SVG (renders anywhere; no mermaid legend limitation)

Usage:
  render_worklog.py <worklog.jsonl> --md     # markdown tables (embed in the .md report)
  render_worklog.py <worklog.jsonl> --html    # self-contained HTML dashboard
  render_worklog.py --selfcheck               # assert-based smoke test
"""
import json, sys, re, math, html as _html

SERIES = [  # (key, label, colour, marker)
    ("total",              "Total context",       "#111827", "line"),
    ("system_tools",       "System / tools / MCP","#2563eb", "circle"),
    ("conversation",       "Conversation",        "#059669", "square"),
    ("tool_results_files", "Tool results / files","#d97706", "triangle"),
    ("coach",              "Coach",               "#7c3aed", "diamond"),
]
NOTABLE_CAP = 12

def load(path):
    rows=[]
    # explicit utf-8: the worklog is written with ensure_ascii=False (🧭 + non-ASCII
    # prompt text as raw bytes); the default encoding is ASCII under a C/POSIX locale
    # (CI containers, LANG=C) and would raise UnicodeDecodeError mid-iteration.
    for l in open(path, encoding="utf-8"):
        l=l.strip()
        if not l: continue
        try: rows.append(json.loads(l))
        except Exception: continue
    return rows

def series_val(r, key):
    c=r["ctx"]
    return c["total"] if key=="total" else c["categories"].get(key,0)

def tier(fb):
    # COARSE, prose-RELIABLE buckets only. Sub-classifying safety tiers (secret/
    # destructive/…) from line text is unreliable (incidental words mis-bucket; the exact
    # counts contradict the narrative) — so we DON'T. The safety-category breakdown lives
    # in the model-authored "Coaching notes" narrative, which reads the actual session.
    # Here we report only what the marker text tells us for certain.
    low=(fb or "").lower()
    if "🧭" not in (fb or ""): return "—"
    if "↺" in (fb or ""): return "recurrence"                 # compact "still not sticking" reminder
    if "even better" in low: return "even-better"             # explicit marker, reliable
    if re.search(r"prompt is clear\s*[-—]", low): return "tight-ack"  # explicit marker, reliable
    return "flagged"                                          # a problem was flagged (see narrative for tier)

def k(n):
    if n>=1_000_000: return f"{n/1_000_000:.0f}M" if n%1_000_000==0 else f"{n/1_000_000:.1f}M"
    return f"{n/1000:.0f}k" if n>=1000 else str(int(n))

def _model(r): return r.get("model") or ""

def analyse(rows):
    n=len(rows)
    pcts=[r["ctx"]["pct"] for r in rows]
    totals=[r["ctx"]["total"] for r in rows]
    hits=[r["cache"]["hit_pct"] for r in rows]
    peak_i=max(range(n), key=lambda i: pcts[i])       # peak FILL (window-normalized %)
    peak_tok_i=max(range(n), key=lambda i: totals[i])  # peak TOKENS (may differ if windows vary)
    minhit_i=min(range(n), key=lambda i: hits[i])
    breaks=[i for i,r in enumerate(rows) if r["cache"].get("chain_break")]
    cross75=[i for i,p in enumerate(pcts) if p>=75 and (i==0 or pcts[i-1]<75)]
    # windows / models present — mixed-model sessions must not blend fill denominators
    windows=sorted({r["ctx"].get("window") for r in rows if r["ctx"].get("window")})
    models=[]
    for r in rows:
        m=_model(r)
        if m and m not in models: models.append(m)
    # category-spike turns: largest single-turn jump in tool_results_files, but a
    # model switch between adjacent turns invalidates the delta (different basis).
    trf=[r["ctx"]["categories"].get("tool_results_files",0) for r in rows]
    def trf_delta(i):
        if i>0 and _model(rows[i]) and _model(rows[i-1]) and _model(rows[i])!=_model(rows[i-1]): return 0
        return trf[i]-(trf[i-1] if i>0 else 0)
    deltas=sorted(range(n), key=trf_delta, reverse=True)
    spikes=[i for i in deltas if trf_delta(i)>0][:3]
    tiers={}
    for r in rows:
        tiers[tier(r.get("feedback"))]=tiers.get(tier(r.get("feedback")),0)+1
    # coaching lines = turns that actually carried a 🧭 line (not skipped/blank)
    coached=sum(1 for r in rows if r.get("feedback") and "🧭" in r.get("feedback",""))
    return dict(n=n,pcts=pcts,totals=totals,hits=hits,peak_i=peak_i,peak_tok_i=peak_tok_i,
                minhit_i=minhit_i,breaks=breaks,cross75=cross75,spikes=spikes,trf=trf,
                tiers=tiers,windows=windows,models=models,coached=coached)

def notable(rows, a):
    reasons={}
    def add(i,why):
        reasons.setdefault(i,[]);
        if why not in reasons[i]: reasons[i].append(why)
    add(0,"start"); add(a["n"]-1,"end"); add(a["peak_i"],"peak fill")
    for i in a["breaks"]: add(i,"chain break")
    for i,p in enumerate(a["pcts"]):
        if p>=100: add(i,"OVER window — truncated")   # mandatory: a blowout can't be crowded out
    for i in a["cross75"]: add(i,"crossed 75%")
    mandatory=set(reasons)
    for i in a["spikes"]:
        if len(reasons)>=NOTABLE_CAP and i not in mandatory: continue
        add(i,"tool-dump spike")
    # surface coaching-flagged turns even without a telemetry coincidence (a secret/
    # derail turn shouldn't be invisible just because its fill was ordinary)
    for i,r in enumerate(rows):
        if len(reasons)>=NOTABLE_CAP and i not in mandatory: continue
        if tier(r.get("feedback")) in ("flagged","recurrence"): add(i,"coaching flag")
    if len(reasons)<NOTABLE_CAP: add(a["minhit_i"],"lowest cache-hit")
    return sorted(reasons.items())

def rollup_rows(rows, a):
    p=a["pcts"]; h=a["hits"]
    # bind "dominant category" to the peak-TOKEN turn (the real max), not peak-fill —
    # they diverge when the window changes mid-session.
    peak=rows[a["peak_tok_i"]]; dom=max(peak["ctx"]["categories"].items(), key=lambda kv:kv[1])
    mix=", ".join(f"{v} {kk}" for kk,v in sorted(a["tiers"].items()))
    win=a["windows"]; win_str=(" / ".join(k(w) for w in win)) if win else "n/a"
    mdl=a["models"]; mdl_str=(", ".join(mdl)) if mdl else "unknown"
    out=[
        ("Turns recorded", str(a["n"])),
        ("Model(s)", mdl_str),
        ("Context window", win_str + ("  (mixed — fill % is per-turn against its own window)" if len(win)>1 else "")),
        ("Peak context fill", f'{p[a["peak_i"]]}%  (turn {rows[a["peak_i"]]["turn"]})' + ("  ⚠ over window — context truncated" if p[a["peak_i"]]>100 else "")),
        ("Mean context fill", f"{sum(p)/len(p):.1f}%" + ("  (mixed windows — blends two denominators; read per-turn fill)" if len(a["windows"])>1 else "")),
        ("Final context fill", f'{p[-1]}%'),
        ("Cache chain-breaks", (f'{len(a["breaks"])}  (turns '+", ".join(str(rows[i]["turn"]) for i in a["breaks"])+")") if a["breaks"] else "0"),
        ("Mean cache-hit", f"{sum(h)/len(h):.1f}%"),
        ("Lowest cache-hit", f'{h[a["minhit_i"]]}%  (turn {rows[a["minhit_i"]]["turn"]})'),
        ("Peak tool-results/files", f'{k(max(a["trf"]))} tokens'),
        ("Dominant category at peak", f"{dom[0]} ({k(dom[1])}, turn {peak['turn']})"),
        ("Coaching lines", f'{a["coached"]} of {a["n"]} turns  ({mix}) — safety-tier breakdown is in the Coaching-notes narrative'),
    ]
    return out

def notable_cells(rows, a):
    out=[]
    for i,why in notable(rows,a):
        r=rows[i]; c=r["ctx"]["categories"]
        out.append([str(r["turn"]), ", ".join(why),
                    k(r["ctx"]["total"]), f'{r["ctx"]["pct"]}%',
                    k(c.get("system_tools",0)), k(c.get("conversation",0)),
                    k(c.get("tool_results_files",0)), k(c.get("coach",0)),
                    f'{r["cache"]["hit_pct"]}%',
                    "yes" if r["cache"].get("chain_break") else "—"])
    return out

NOTABLE_COLS=["Turn","Why shown","Total","Fill %","system/tools","conversation",
              "tool/files","coach","Cache-hit","Chain-break"]

# ---- markdown ----
def md_table(headers, rows):
    out=["| "+" | ".join(headers)+" |", "|"+"|".join("---" for _ in headers)+"|"]
    for r in rows: out.append("| "+" | ".join(r)+" |")
    return "\n".join(out)

def render_md(rows):
    a=analyse(rows)
    s=["**Session rollup**\n", md_table(["Metric","Value"], [[m,v] for m,v in rollup_rows(rows,a)]),
       "\n**Notable turns** (only turns worth reading; full per-turn data is in the worklog)\n",
       md_table(NOTABLE_COLS, notable_cells(rows,a))]
    return "\n".join(s)

# ---- svg chart ----
def nice_ceil(v):
    import math
    if v<=0: return 1
    e=10**int(math.floor(math.log10(v))); f=v/e
    for m in (1,2,2.5,5,10):
        if f<=m: return int(m*e)
    return int(10*e)

def svg(rows):
    # LOG Y-axis: context categories span ~3k (coach) to ~700k (system/tools); on a
    # linear axis the small series vanish into the baseline, so we plot log10(tokens).
    # Zeros/sub-floor values are clamped to FLOOR so they still draw a line.
    n=len(rows); W,H=900,432; ml,mr,mt,mb=70,16,14,44
    pw,ph=W-ml-mr,H-mt-mb
    FLOOR=100
    vmax=max(r["ctx"]["total"] for r in rows)
    top=10**math.ceil(math.log10(max(vmax, FLOOR*10)))
    lg_lo, lg_hi = math.log10(FLOOR), math.log10(top)
    # X maps by POSITION (0-based index), not the raw turn number — turns can start
    # anywhere (coach enabled mid-session) or have gaps, so keying on the value flings
    # points off-canvas. Ticks below are still LABELLED with the real turn number.
    def X(i): return ml+(0 if n==1 else i/(n-1)*pw)
    def Y(v): return mt+(1-(math.log10(max(v,FLOOR))-lg_lo)/(lg_hi-lg_lo))*ph
    parts=[f'<svg viewBox="0 0 {W} {H}" width="100%" preserveAspectRatio="xMidYMid meet" font-family="system-ui,sans-serif" font-size="11">']
    # y decade gridlines + labels (100, 1k, 10k, 100k, 1M ...)
    d=FLOOR
    while d<=top+1:
        y=Y(d)
        parts.append(f'<line x1="{ml}" y1="{y:.1f}" x2="{ml+pw}" y2="{y:.1f}" stroke="#e5e7eb"/>')
        parts.append(f'<text x="{ml-6}" y="{y+3:.1f}" text-anchor="end" fill="#6b7280">{k(d)}</text>')
        d*=10
    # x ticks (thinned)
    step=max(1,round(n/10))
    for i in range(0,n,step):
        t=rows[i]["turn"]; x=X(i)
        parts.append(f'<text x="{x:.1f}" y="{mt+ph+16}" text-anchor="middle" fill="#6b7280">{t}</text>')
    parts.append(f'<text x="{ml+pw/2}" y="{H-4}" text-anchor="middle" fill="#374151">turn</text>')
    parts.append(f'<text x="12" y="{mt+ph/2}" text-anchor="middle" fill="#374151" transform="rotate(-90 12 {mt+ph/2})">tokens (log scale)</text>')
    # series
    markers = n<=24
    for key,label,col,mk in SERIES:
        pts=[(X(idx),Y(series_val(r,key))) for idx,r in enumerate(rows)]
        d=" ".join(f"{x:.1f},{y:.1f}" for x,y in pts)
        wdt=2.6 if key=="total" else 1.6
        parts.append(f'<polyline points="{d}" fill="none" stroke="{col}" stroke-width="{wdt}"/>')
        if markers:
            for x,y in pts: parts.append(_marker(mk,x,y,col))
    parts.append("</svg>")
    return "".join(parts)

def _marker(mk,x,y,col):
    if mk=="circle": return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.6" fill="{col}"/>'
    if mk=="square": return f'<rect x="{x-2.4:.1f}" y="{y-2.4:.1f}" width="4.8" height="4.8" fill="{col}"/>'
    if mk=="triangle": return f'<polygon points="{x:.1f},{y-3:.1f} {x-3:.1f},{y+2.4:.1f} {x+3:.1f},{y+2.4:.1f}" fill="{col}"/>'
    if mk=="diamond": return f'<polygon points="{x:.1f},{y-3:.1f} {x-3:.1f},{y:.1f} {x:.1f},{y+3:.1f} {x+3:.1f},{y:.1f}" fill="{col}"/>'
    return ""  # "line" = total, no marker

def legend_html(rows):
    a=analyse(rows); peaks={k2:0 for k2,_,_,_ in SERIES}
    for r in rows:
        for key,_,_,_ in SERIES: peaks[key]=max(peaks[key],series_val(r,key))
    items=[]
    for key,label,col,mk in SERIES:
        items.append(f'<span class="lg"><span class="sw" style="background:{col}"></span>'
                     f'{label} <span class="pk">peak {k(peaks[key])}</span></span>')
    return '<div class="legend">'+"".join(items)+'</div>'

def html_table(headers, rows, cls=""):
    h="".join(f"<th>{c}</th>" for c in headers)
    body=""
    for r in rows:
        tds=""
        for j,c in enumerate(r):
            klass=""
            if headers[j]=="Fill %" and c.rstrip("%").replace(".","").isdigit():
                fv=float(c.rstrip("%"))
                if fv>=100: klass=' class="bad"'      # over window — context truncated
                elif fv>=75: klass=' class="warn"'
            if headers[j]=="Chain-break" and c=="yes": klass=' class="bad"'
            if j==0: klass=' class="idx"'
            tds+=f"<td{klass}>{c}</td>"
        body+=f"<tr>{tds}</tr>"
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{body}</tbody></table>'

# ---- full report (session info + narrative + embedded dashboard) ----
def _inline(s):
    s=_html.escape(s)
    s=re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    s=re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    s=re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', s)
    return s

def md_to_html(md):
    """Minimal, dependency-free markdown → HTML for the narrative sections the model
    writes (headings, bold, code, lists, tables, blockquotes). Mermaid fences are
    dropped — the chart is supplied natively by the renderer."""
    lines=md.split("\n"); out=[]; i=0; n=len(lines)
    while i<n:
        ln=lines[i]
        if ln.strip().startswith("```"):
            lang=ln.strip()[3:].strip(); i+=1; buf=[]
            while i<n and not lines[i].strip().startswith("```"): buf.append(lines[i]); i+=1
            i+=1
            if lang!="mermaid": out.append("<pre><code>"+_html.escape("\n".join(buf))+"</code></pre>")
            continue
        if ln.strip().startswith("|") and i+1<n and re.match(r'^\s*\|?[-:\s|]+\|?\s*$', lines[i+1]):
            hdr=[c.strip() for c in ln.strip().strip("|").split("|")]; i+=2; rws=[]
            while i<n and lines[i].strip().startswith("|"):
                rws.append([c.strip() for c in lines[i].strip().strip("|").split("|")]); i+=1
            th="".join(f"<th>{_inline(c)}</th>" for c in hdr)
            bd="".join("<tr>"+"".join(f"<td>{_inline(c)}</td>" for c in r)+"</tr>" for r in rws)
            out.append(f'<table class="nar"><thead><tr>{th}</tr></thead><tbody>{bd}</tbody></table>'); continue
        m=re.match(r'^(#{1,6})\s+(.*)$', ln)
        # `#`->h1, `##`->h2 (standard): section headings the narrative writes with `##`
        # must land as <h2> so the dashboard-injection anchor (and the CSS) find them.
        if m: lvl=min(6,len(m.group(1))); out.append(f"<h{lvl}>{_inline(m.group(2))}</h{lvl}>"); i+=1; continue
        if re.match(r'^\s*---+\s*$', ln): out.append("<hr>"); i+=1; continue
        if ln.strip().startswith(">"):
            buf=[]
            while i<n and lines[i].strip().startswith(">"): buf.append(lines[i].strip()[1:].strip()); i+=1
            out.append("<blockquote>"+_inline(" ".join(buf))+"</blockquote>"); continue
        if re.match(r'^\s*[-*]\s+', ln):
            buf=[]
            while i<n and re.match(r'^\s*[-*]\s+', lines[i]): buf.append(re.sub(r'^\s*[-*]\s+','',lines[i])); i+=1
            out.append("<ul>"+"".join(f"<li>{_inline(x)}</li>" for x in buf)+"</ul>"); continue
        if re.match(r'^\s*\d+\.\s+', ln):
            buf=[]
            while i<n and re.match(r'^\s*\d+\.\s+', lines[i]): buf.append(re.sub(r'^\s*\d+\.\s+','',lines[i])); i+=1
            out.append("<ol>"+"".join(f"<li>{_inline(x)}</li>" for x in buf)+"</ol>"); continue
        if not ln.strip(): i+=1; continue
        buf=[ln]; i+=1
        while i<n and lines[i].strip() and not re.match(r'^\s*([-*]\s|\d+\.\s|#|>|\|)', lines[i]) and not lines[i].strip().startswith("```"):
            buf.append(lines[i]); i+=1
        out.append("<p>"+_inline(" ".join(buf))+"</p>")
    return "\n".join(out)

def dashboard_fragment(rows):
    a=analyse(rows)
    roll=html_table(["Metric","Value"], [[m,v] for m,v in rollup_rows(rows,a)],"roll")
    notab=html_table(NOTABLE_COLS, notable_cells(rows,a),"notable")
    return ('<div class="legend-wrap">'+legend_html(rows)+'</div>'
            +'<div class="chart">'+svg(rows)+'</div>'
            +'<h3>Session rollup</h3>'+roll
            +'<h3>Notable turns <span class="muted">(only the turns worth reading — full per-turn data stays in the worklog)</span></h3>'+notab)

def session_header(rows, title, project):
    a=analyse(rows); n=a["n"]
    ts0=rows[0].get("ts",""); ts1=rows[-1].get("ts","")
    pw=rows[a["peak_i"]]["ctx"].get("window")
    peak_lbl=f'{a["pcts"][a["peak_i"]]}%' + (f' of {k(pw)}' if len(a["windows"])>1 and pw else '')
    chips=[("Turns",str(n)),
           ("Peak fill",peak_lbl),
           ("Chain-breaks",str(len(a["breaks"]))),
           ("Mean cache-hit",f'{sum(a["hits"])/len(a["hits"]):.0f}%'),
           ("Coaching lines",f'{a["coached"]}/{n}')]
    if a["windows"]: chips.append(("Ctx window"," / ".join(k(w) for w in a["windows"])))
    if a["models"]: chips.append(("Model", ", ".join(a["models"])))
    if project: chips.insert(0,("Context",project))
    chiphtml="".join(f'<div class="chip"><span class="k">{_html.escape(kk)}</span><span class="v">{_html.escape(vv)}</span></div>' for kk,vv in chips)
    dr=f'{ts0} → {ts1}' if ts0 else ''
    return (f'<header><h1>{_html.escape(title)}</h1>'
            f'<div class="sub">prompt-coach session summary{(" · "+_html.escape(dr)) if dr else ""}</div>'
            f'<div class="chips">{chiphtml}</div></header>')

def render_report(rows, narrative_md, title, project):
    nar=md_to_html(narrative_md); dash=dashboard_fragment(rows)
    # Anchor is heading-level-agnostic: inject the dashboard right after whatever
    # heading the narrative used for its context/stats section (the contract says
    # "## Context & coaching stats"). Only if none exists do we append our own.
    m=re.search(r'<h[1-6]>[^<]*[Cc]ontext[^<]*</h[1-6]>', nar)
    if m: nar=nar[:m.end()]+dash+nar[m.end():]
    else: nar=nar+'<h2>Context &amp; coaching stats</h2>'+dash
    return (f'<!doctype html><html><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{_html.escape(title)} — session summary</title>'
            f'<style>{SHARED_CSS}</style></head><body>'
            f'{session_header(rows,title,project)}<main>{nar}</main></body></html>')

SHARED_CSS = """
:root{color-scheme:light dark}
*{box-sizing:border-box}
body{font:15px/1.6 system-ui,-apple-system,sans-serif;margin:0;color:#111827;background:#f3f4f6}
header{background:#111827;color:#f9fafb;padding:24px 28px}
header h1{font-size:20px;margin:0}
header .sub{color:#9ca3af;font-size:12px;margin-top:2px}
.chips{display:flex;flex-wrap:wrap;gap:10px;margin-top:14px}
.chip{background:#1f2937;border-radius:8px;padding:6px 12px;display:flex;flex-direction:column;min-width:78px}
.chip .k{font-size:10px;color:#9ca3af;text-transform:uppercase;letter-spacing:.04em}
.chip .v{font-size:16px;font-weight:600}
main{max-width:960px;margin:20px auto;padding:0 20px 40px}
h2{font-size:16px;margin:30px 0 8px;padding-bottom:5px;border-bottom:2px solid #e5e7eb}
h3{font-size:13px;color:#374151;margin:18px 0 6px}
p{margin:8px 0} ul,ol{margin:8px 0;padding-left:22px} li{margin:3px 0}
blockquote{border-left:3px solid #d1d5db;margin:10px 0;padding:2px 14px;color:#4b5563}
code{background:#e5e7eb;padding:1px 5px;border-radius:4px;font-size:12px}
pre{background:#1f2937;color:#e6edf3;padding:12px;border-radius:8px;overflow-x:auto}
pre code{background:none;color:inherit}
a{color:#2563eb}
.muted{font-weight:400;color:#6b7280;font-size:11px}
.legend-wrap{margin-top:8px}
.legend{display:flex;flex-wrap:wrap;gap:14px;margin:8px 0 4px}
.lg{display:flex;align-items:center;gap:6px;font-size:12px}
.sw{width:16px;height:4px;border-radius:2px;display:inline-block}
.pk{color:#6b7280;font-size:11px}
.chart{overflow-x:auto;background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:8px}
table{border-collapse:collapse;width:100%;font-size:12px;margin:6px 0;background:#fff}
th,td{border:1px solid #e5e7eb;padding:5px 9px;text-align:right}
th{background:#f9fafb}
td.idx,th:first-child{text-align:left;font-weight:600}
.notable td:nth-child(2){text-align:left}
table.nar td,table.nar th{text-align:left}
tbody tr:nth-child(even){background:#fafafa}
td.warn{background:#fef3c7;font-weight:600} td.bad{background:#fee2e2;color:#991b1b;font-weight:600}
@media(prefers-color-scheme:dark){
 body{background:#0d1117;color:#e6edf3}
 h2{border-color:#30363d} h3{color:#9ca3af}
 code{background:#30363d} blockquote{border-color:#30363d;color:#9ca3af}
 .chart{background:#161b22;border-color:#30363d}
 table{background:#0d1117} th{background:#161b22} th,td{border-color:#30363d}
 tbody tr:nth-child(even){background:#161b22}
 td.warn{background:#3b2f12} td.bad{background:#3b1518;color:#ffb4ab}
 a{color:#58a6ff}}
"""

def render_html(rows, title):
    title=_html.escape(title)   # title is CLI-derived (may be a path); escape like render_report
    a=analyse(rows)
    roll=html_table(["Metric","Value"], [[m,v] for m,v in rollup_rows(rows,a)],"roll")
    notab=html_table(NOTABLE_COLS, notable_cells(rows,a),"notable")
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} — context-window dashboard</title>
<style>
:root{{color-scheme:light dark}}
body{{font:14px/1.5 system-ui,sans-serif;margin:0;padding:24px;max-width:960px;margin:auto;color:#111827;background:#fff}}
h1{{font-size:18px}} h2{{font-size:14px;color:#374151;margin-top:28px}}
.legend{{display:flex;flex-wrap:wrap;gap:14px;margin:8px 0 4px}}
.lg{{display:flex;align-items:center;gap:6px;font-size:12px}}
.sw{{width:16px;height:4px;border-radius:2px;display:inline-block}}
.pk{{color:#6b7280;font-size:11px}}
.chart{{overflow-x:auto;border:1px solid #e5e7eb;border-radius:8px;padding:8px}}
table{{border-collapse:collapse;width:100%;font-size:12px;margin-top:6px}}
th,td{{border:1px solid #e5e7eb;padding:4px 8px;text-align:right}}
th{{background:#f9fafb;text-align:right}}
td.idx,th:first-child{{text-align:left;font-weight:600}}
.notable td:nth-child(2){{text-align:left}}
tbody tr:nth-child(even){{background:#fafafa}}
td.warn{{background:#fef3c7;font-weight:600}} td.bad{{background:#fee2e2;color:#991b1b;font-weight:600}}
@media(prefers-color-scheme:dark){{body{{background:#0d1117;color:#e6edf3}}th{{background:#161b22}}
.chart{{border-color:#30363d}} th,td{{border-color:#30363d}} tbody tr:nth-child(even){{background:#161b22}}
td.warn{{background:#3b2f12}} td.bad{{background:#3b1518;color:#ffb4ab}}}}
</style></head><body>
<h1>{title} — context-window dashboard</h1>
<h2>Context load over turns</h2>
{legend_html(rows)}
<div class="chart">{svg(rows)}</div>
<h2>Session rollup</h2>{roll}
<h2>Notable turns <span style="font-weight:400;color:#6b7280">(only the turns worth reading — full per-turn data stays in the worklog)</span></h2>{notab}
</body></html>"""

def selfcheck():
    # synthetic 30-turn worklog with a chain-break and a spike
    rows=[]
    for t in range(1,31):
        total=40000+t*22000; trf=0
        if t==15: trf=120000
        cb = t==10
        rows.append({"turn":t,"model":"claude-opus-4-8","feedback":("🧭 coach: clear — even better: x" if t%3 else "🧭 coach: prompt is clear — y"),
          "ctx":{"total":total,"window":1000000,"pct":round(total/10000,1),
                 "categories":{"system_tools":int(total*0.8),"conversation":t*100,"tool_results_files":trf,"coach":3200}},
          "cache":{"read":int(total*(0.3 if cb else 0.9)),"creation":5000,"hit_pct":33.0 if cb else 96.0,"chain_break":cb}})
    a=analyse(rows)
    assert a["peak_i"]==29, a["peak_i"]
    assert 9 in a["breaks"], a["breaks"]
    assert 14 in a["spikes"], a["spikes"]
    nb=notable(rows,a); assert len(nb)<=NOTABLE_CAP, len(nb)
    assert any("chain break" in w for _,w in nb)
    h=render_html(rows,"selfcheck"); assert "<svg" in h and "legend" in h and "Notable turns" in h
    assert "log scale" in h, "chart should be log-scale"
    m=render_md(rows); assert "Session rollup" in m and "| Turn |" in m
    nar=("## Session lookback\nBuilt a version route; work stayed on track.\n\n"
         "## Gaps & insufficiencies\n- claimed done without a check\n\n"
         "## Coaching notes this session\n- return format nudged 3x\n\n"
         "## Context & coaching stats\nFill grew steadily.\n")
    rep=render_report(rows, nar, "selfcheck-report", "general session")
    assert "<header>" in rep and "Session lookback" in rep and "<svg" in rep
    assert "Coaching notes" in rep and "Session rollup" in rep and 'class="chip"' in rep
    # #4 — dashboard injects UNDER the narrative's context heading, exactly once, and
    # the old duplicate "Context-window management" h2 is never appended.
    assert "Context-window management" not in rep, "duplicate context section was appended"
    assert "<h2>Context &amp; coaching stats</h2>" in rep, "section heading should be <h2>"
    ci=rep.index("Context &amp; coaching stats"); assert rep.index("<svg", ci) > ci, "chart must sit under the context heading"
    assert rep.count("Context &amp; coaching stats")==1, "context heading duplicated"
    # #5 — model + window surfaced in header + rollup; mixed windows handled
    assert "claude-opus-4-8" in rep and "Ctx window" in rep, "header should show model + window"
    mix=[{"turn":1,"model":"claude-opus-4-8","feedback":"🧭 x","ctx":{"total":900000,"window":1000000,"pct":90.0,"categories":{"system_tools":800000,"conversation":1000,"tool_results_files":99000,"coach":3000}},"cache":{"read":800000,"creation":5000,"hit_pct":95.0,"chain_break":False}},
         {"turn":2,"model":"claude-haiku-4-5","feedback":"🧭 y","ctx":{"total":150000,"window":200000,"pct":75.0,"categories":{"system_tools":100000,"conversation":1000,"tool_results_files":46000,"coach":3000}},"cache":{"read":120000,"creation":5000,"hit_pct":90.0,"chain_break":False}}]
    am=analyse(mix); assert am["peak_i"]==0 and am["peak_tok_i"]==0, (am["peak_i"],am["peak_tok_i"])
    assert am["windows"]==[200000,1000000] and len(am["models"])==2, (am["windows"],am["models"])
    rm=render_md(mix); assert "mixed" in rm and "claude-haiku-4-5" in rm, "rollup should flag mixed windows + list models"
    # chart X maps by POSITION, not raw turn number: a worklog whose turns don't start at
    # 1 (coach enabled mid-session) must still plot on-canvas, not fly off to the right.
    off=[dict(r, turn=r["turn"]+594) for r in rows]           # turns 595..624
    import re as _re
    xs=[float(p.split(",")[0]) for pl in _re.findall(r'<polyline points="([^"]+)"', svg(off)) for p in pl.split()]
    assert xs and all(70 <= x <= 900 for x in xs), f"chart points off-canvas: {min(xs):.0f}..{max(xs):.0f}"
    # tier() is COARSE + prose-reliable only: safety lines all read "flagged"; the
    # reliable markers (even-better / tight-ack / ↺ recurrence) classify exactly.
    assert tier("🧭 coach: force-push over main is destructive — open a PR first")=="flagged"
    assert tier("🧭 coach: that's a secret — rotate the API key")=="flagged"
    assert tier("🧭 coach: clear — even better: name the format")=="even-better"
    assert tier("🧭 coach: prompt is clear — nothing to add")=="tight-ack"
    assert tier("🧭 coach: ↺ return-format (5th time) — still not sticking")=="recurrence"
    # #16 — arg validation rejects unknown flags / bad first arg
    print("selfcheck OK — %d turns, notable=%d, breaks=%s, spikes=%s; inject-under-heading + model/window + tiers verified" % (a["n"],len(nb),a["breaks"],a["spikes"]))

USAGE=("usage: render_worklog.py <worklog.jsonl> [--md | --html | "
       "--report <narrative.md> [--title T] [--project P]]\n       render_worklog.py --selfcheck")
KNOWN_FLAGS={"--md","--html","--report","--title","--project","--selfcheck"}

def main():
    # the report/dashboard output carries 🧭 + em-dashes; force utf-8 stdout so writing
    # it doesn't UnicodeEncodeError under a C/POSIX-locale (ASCII) stdout.
    try: sys.stdout.reconfigure(encoding="utf-8")
    except Exception: pass
    if "--selfcheck" in sys.argv: return selfcheck()
    argv=sys.argv[1:]
    if not argv or argv[0] in ("--help","-h"): print(USAGE); return 0
    # reject unknown flags loudly instead of silently falling through to --md
    unknown=[a for a in argv if a.startswith("-") and a not in KNOWN_FLAGS]
    if unknown: print(f"error: unknown flag(s): {', '.join(unknown)}\n{USAGE}", file=sys.stderr); return 2
    if argv[0].startswith("-"): print(f"error: first argument must be the worklog path\n{USAGE}", file=sys.stderr); return 2
    path=sys.argv[1]; rows=load(path)
    if not rows: print("(worklog empty or unreadable)"); return 1
    import os; title=os.path.basename(path).replace("coach-","").replace(".jsonl","")
    def arg(flag, default=""):
        return sys.argv[sys.argv.index(flag)+1] if flag in sys.argv and sys.argv.index(flag)+1<len(sys.argv) else default
    if "--report" in sys.argv:
        narrative=open(arg("--report"), encoding="utf-8").read()
        sys.stdout.write(render_report(rows, narrative, arg("--title", title), arg("--project","")))
    elif "--html" in sys.argv: sys.stdout.write(render_html(rows,title))
    else: sys.stdout.write(render_md(rows))

if __name__=="__main__":
    sys.exit(main() or 0)
