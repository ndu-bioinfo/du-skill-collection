# prompt-coach summary flow

Invoked when the user runs `/prompt-coach summary` (optionally `/prompt-coach summary
--debug`). Produces the trainee summary always, and the coach self-feedback only in
debug mode:

1. **The trainee summary** (`OUTFILE` markdown + `OUTFILE_HTML` rich report) — a
   real, self-contained lookback for the person who ran the session. Four sections
   (below). This is training material about *their* session — it must NOT contain
   suggestions about how to change the coach tool itself. **Always produced.**
2. **Suggestions to the coach** (`OUTFILE_COACH` markdown) — a *separate* file holding
   concrete improvements to prompt-coach's own rules/references. Kept apart so the
   trainee summary stays about the trainee, and tool-tuning notes stay actionable for
   whoever maintains the skill. **DEBUG-ONLY, default OFF** — produced only when the
   user ran `/prompt-coach summary --debug`. The locator emits an `OUTFILE_COACH` line
   only in that case; if it is absent, skip this deliverable entirely.

Two data sources, ingested together:
- **The worklog** (`WORKLOG`, JSONL, one record per turn) — structured ground truth
  for context/cache dynamics and the logged `🧭` feedback. Records look like:
  `{ts,turn,prompt,feedback,ctx:{total,window,pct,categories:{system_tools,conversation,tool_results_files,coach}},cache:{read,creation,hit_pct,chain_break}}`.
- **The transcript** (`TRANSCRIPT`, JSONL of the raw session messages) — the actual
  conversation and tool flow: what was asked, how the work went, detours/rework,
  verification gaps. This is the *content* the worklog can't hold.

Cross-reference them: explain a worklog `chain_break` (or a context spike) with what
the transcript shows happened that turn — a large paste, a whole-file read, a big
tool dump, a model/MCP switch, or a compaction.

## Steps

1. Run the locator to get `TRANSCRIPT`, `WORKLOG`, `OUTFILE`, `OUTFILE_HTML` (and, in
   debug mode, `OUTFILE_COACH`) as shell variables. It prints shell-quoted `KEY=VALUE`
   lines, so load them with `eval`, which keeps paths intact even when they contain
   spaces. Pass `--debug` through ONLY if the user's invocation included it:
   `eval "$(bash "<skill-base-dir>/scripts/summary.sh")"` (default), or
   `eval "$(bash "<skill-base-dir>/scripts/summary.sh" --debug)"` (debug). The skill's
   base directory is the one provided when this skill is invoked. If the locator exits
   non-zero, tell the user no transcript was found and stop. Always double-quote the
   variables when you use them downstream (`"$WORKLOG"`, `"$OUTFILE"`, …). Whether
   `OUTFILE_COACH` is set decides step 4: set (debug) → write it; unset (default) → skip it.
2. Read the `WORKLOG` if it exists (it may not — coach was off or first run). Read the
   `TRANSCRIPT`. Build the trainee summary from BOTH (and, in debug mode, the coach
   file too); if the worklog is absent, produce the report from the transcript alone
   and add a one-line caveat that context-management metrics are unavailable for turns
   before the coach was enabled.
3. Write the trainee NARRATIVE markdown to `OUTFILE` with EXACTLY these four sections,
   in this order. Prose only — do NOT hand-build the context chart or stats tables;
   step 5 renders them deterministically and injects them into the fourth section.
   Keep it tight: this is a lookback, not a report dump — a few bullets or sentences
   per section, not pages.

   ## Session lookback
   - What the session set out to do and how it actually went (from the transcript):
     the goal, the shape of the work, what got done, what did well.
   - If any safety-tier event fired (secret, destructive op, fabrication, injection),
     name the session's defining safety event(s) here — not only the wins. A loaded
     session's summary must lead with what was risky.

   ## Gaps & insufficiencies
   - Where prompts or workflow fell short: recurring prompt-quality weaknesses,
     detours and rework, planning depth vs. stakes, and any verification gaps
     (claims of done without a check that proves it).
   - One or two concrete changes that would have made the session tighter — but if the
     session genuinely had no material gaps, say that plainly ("no material gaps this
     session") rather than manufacture a tightening item. Don't dress up a defensible choice
     (e.g. a justified whole-file read) as a gap; the anti-padding rule applies here too.

   ## Coaching notes this session
   - A deduped summary of the `🧭 coach:` lines that fired (from the worklog
     `feedback` field and the transcript) — grouped by theme, with how many times each
     recurred. Call out any theme that recurred and never "stuck" (the habit to adopt).
     List each **safety** theme separately with its own recurrence count (the deterministic
     rollup bundles these under "flagged" — this section is where they get itemized), so the
     controls-to-add line below can be tied to a specific recurring risk.
   - End with a short **"habits to adopt / controls to add"** line: the 1–3 concrete
     changes that would end the recurring themes for good — a personal prompt checklist
     for style habits, and a structural control (secret scanner, pre-commit hook,
     prod-approval gate) for any recurring *safety* theme.
   - This section summarizes what the coach told the trainee. It is NOT where
     suggestions about improving the coach go — those belong in `OUTFILE_COACH`.

   ## Context & coaching stats
   Prose only (skip with a caveat if the worklog is absent). Do NOT build a table or a
   chart here — the renderer in step 5 injects a legended log-scale chart plus the
   rollup and notable-turns tables right under this heading. Write 3–5 sentences the
   numbers can't self-explain: for each chain-break turn, read the transcript for that
   turn and state the likely cause (large paste, whole-file read, tool/MCP or model
   switch, compaction) and how to avoid it; call out any category that dominates and
   why; and give the highest-value mitigation for the peak fill (targeted reads,
   trimming standing tools/MCP — the system owns compaction, so don't hint `/compact`).
   **Attribute bloat to whoever caused it** — a whole-file read or big tool dump is often
   the *agent's* choice from a benign prompt; don't blame the trainee's prompt for context
   the agent grew. In a mixed-model session note the model/window shown in the rollup so
   fill % is read against the right window. To know which turns to discuss, you may run
   `render_worklog.py "$WORKLOG" --md` and read its rollup + notable-turns tables.

4. **Debug-only — skip this step entirely unless `OUTFILE_COACH` is set** (the user
   ran `/prompt-coach summary --debug`). When set, write the SEPARATE coach-improvement
   file to `OUTFILE_COACH`. This is the ONLY place tool-tuning suggestions live.
   Concrete, actionable improvements to prompt-coach's rules/references, each grounded:
   - **External:** cite a specific public prompt-engineering practice or tool by
     name/URL where it supports the suggestion.
   - If a suggestion needs grounding the transcript cannot provide, you MAY fetch
     additional content from public references before writing it. Do not invent sources.
   - Keep it short: the highest-value 2–4 suggestions, each one paragraph. If nothing
     warrants a change, say so in one line rather than padding.

5. Render the rich HTML report from the trainee narrative + worklog:
   `render_worklog.py "$WORKLOG" --report "$OUTFILE" --title "<session name/date>" --project "general session" > "$OUTFILE_HTML"`.
   This produces the single self-contained trainee deliverable — a session-info header
   (turns, peak fill, chain-breaks, cache-hit, context type), the four narrative
   sections, and the legended log-scale chart + rollup + notable-turns tables embedded
   under Context & coaching stats. If the worklog is absent, skip this step and hand
   over the `OUTFILE` markdown alone with the caveat.
6. Tell the user the `OUTFILE_HTML` trainee report path (primary; open in a browser)
   and summarize inline the top 1–2 coaching themes for the trainee and the single most
   important context-management takeaway. In debug mode, also give the `OUTFILE_COACH`
   path and the top coach suggestion.

## Notes
- Read-only w.r.t. the coach's own files — this flow writes only `OUTFILE`,
  `OUTFILE_HTML`, and (debug only) `OUTFILE_COACH`.
- No secrets/PII in either output: redact any credential or personal identifier
  encountered in either source. The worklog prompts are scrubbed for STRUCTURED
  identifiers only (SSN/phone/email/credentials) — free-text names are NOT caught, so
  re-check anything pulled from the transcript AND any prompt/feedback text you surface.
