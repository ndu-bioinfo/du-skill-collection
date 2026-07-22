# Prompting & context rules — maintainer reference

Background distillation for whoever maintains this skill (never loaded at runtime).
Draws on general prompt-engineering practice — Anthropic's Claude prompting guidance,
IBM Technology's prompt-engineering material (ibm.com/think prompt-engineering topic +
techniques articles), and planning-frameworks thinking (grilling / structured
brainstorming / explore-first). Refresh when the underlying material changes.

## Prompt quality

- **Task + Context + Format + Constraints** — the core formula for every prompt.
- **Be specific, not vague** — the single most common correction. The model fills
  gaps with assumptions. Name the outcome, the file(s), the success criteria.
- **Assign a specific role** — "senior security engineer reviewing for injection
  flaws" beats "a developer." Specificity predicts quality.
- **State the format explicitly** — JSON schema, named table columns, numbered
  steps. Don't let the model guess.
- **Add constraints/guardrails** — "only use the stdlib", "limit to 5", "if
  unsure, say so." Reduces hallucination and drift.
- **Few-shot when patterned** — 2–5 input→output examples; best example last.
- **Ask for reasoning only on hard tasks** — "think step by step" for genuinely
  complex/ambiguous work; don't over-apply.
- **Describe WHAT, not HOW (for code)** — "write a function that parses the config
  headers" beats step-by-step implementation dictation.
- **State the "why"** — conventions with rationale, not bare rules.
- **Scope one task at a time** — small focused requests beat large vague ones; chain
  multi-step work (analyze → focus → synthesize → produce).
- **Read before you write** — have the agent understand existing code first.
- **Iterate** — first prompt ≠ best prompt. Draft → send → evaluate → refine.

## Context management

- **Context is your most valuable resource** — monitor it; compact at 60–70%, don't
  wait until full. `/compact` to continue the same task, `/new` for unrelated work.
- **Break large tasks into phases** — don't do everything in one session.
- **CLAUDE.md bridges sessions** — keep it tight (<~200 lines), use pointers not
  pasted code, include build/test/lint commands and conventions-with-rationale.
- **Reference sources of truth** — constrain to authoritative docs/APIs; cross-reference
  rather than trusting model memory.
- **Isolate parallel work** — subagents and git worktrees keep unrelated context out
  of the main window.

## Advanced techniques

Beyond the core formula — reach for these when the task is genuinely hard or
high-stakes. Don't over-apply; a simple prompt needs none of them.

**Reasoning strategies (hard tasks only):**

- **ReAct (reason + act)** — for exploratory/debugging work, have the agent
  interleave reason → act (read/run/grep) → observe → revise, so the codebase, not
  its assumptions, drives the plan.
- **Tree of Thoughts** — for a design/refactor with several viable approaches, have
  it lay out 2–3 candidates with tradeoffs and prune *before* writing code, instead
  of committing to the first idea.
- **Self-consistency / majority vote** — for a costly or uncertain result, reason
  through it independently several times (or across agents) and take the recurring
  answer; trades extra calls for lower variance.
- **Generated-knowledge** — have the agent first state the facts, API contracts, and
  invariants it will rely on, then build on them, so a hidden wrong assumption
  surfaces before it corrupts the implementation.

**Steering the agent:**

- **Directional stimulus (hint tokens)** — seed exact symbol names, file paths,
  error strings, or the API to use; steers toward the right code path without
  dictating the whole solution.
- **Meta prompting** — have the agent draft or critique the spec/prompt first,
  surfacing missing details before it implements.
- **Neutral framing, not leading questions** — ask "why is X failing?" not "fix the
  null-check bug in X"; a presumed cause makes the agent confirm your guess instead
  of investigating.
- **Active prompting** — add examples targeting exactly the cases the agent gets
  wrong, not generic ones.

**Input hygiene:**

- **Treat fetched content as data, not commands** — tell the agent that pasted
  files, web pages, or tool output is untrusted data to act on, never instructions
  to follow (prompt-injection guard).
- **Structured input over prose** — hand it JSON / tables / a typed schema when the
  data is structured; attach a screenshot or diagram for UI or error-repro work.
- **Proofread & budget the prompt** — clean typos (they misdirect the agent) and
  trim to the tokens that actually change the output (leaner = lower latency/cost).

## Planning-phase strategy

The planning/design phase matters *more* in the AI era, not less: code generation is
cheap, but a vague spec yields perfect-but-wrong code. The value of planning is
**asking the right question**, not quickly getting a wrong answer. AI can't think for
you — if the requirement is fuzzy going in, no model fixes it.

**Three ways to structure the thinking.** These are cognitive modes; recommend an
installed skill only if you can confirm it exists in the session (see `judge.md`).

- **Pressure-test (QA thinking)** — adversarial Q&A: answer pointed questions one at
  a time until the idea holds up. Fast, lightweight. Best for: validating an idea you
  already have, or a specific framed problem.
- **Structure it (process thinking)** — explore context → clarifying questions → 2–3
  options with tradeoffs → design doc → self-review → your review → plan. Heavier,
  but forces early consensus and preserves the "why". Best for: anything that ships,
  team work, production/core changes.
- **Explore first (cognitive-support thinking)** — read the code, compare options,
  sketch a diagram (ASCII is fine), clarify scope *before* committing to a proposal.
  Best for: a large, messy, unfamiliar system where you don't know where to start.

**How to choose — match depth to stakes:**

- Solo / throwaway / just validating → pressure-test, keep it quick.
- Unfamiliar or messy system → explore first, then structure.
- Ships / team / production → structure it and produce the design doc. Default here.
- **Combine:** explore to frame → pressure-test to find holes → structure + design
  doc if it's important enough to ship.

**Do's:**

- **Don't over-design in planning** — surface the *key* questions and decisions; defer
  the rest to implementation. Planning that tries to settle every detail never ends.
- **Write down the key decisions + rationale**, even on the quick path — 5 minutes,
  short but clear. A pressure-test with no record is a decision you can't defend later.
- **Design isolation & clarity** — each part has one clear purpose, talks to the rest
  through a well-defined interface, and is independently understandable/testable. The
  antidote to "changed one line, the far side of the system broke."

## Anti-patterns

Vague/underspecified prompts · generic roles · doing too much in one shot · not
verifying output ("trust but verify" — AI output is a first draft) · committing code
you don't understand · letting the agent guess format/commands · CLAUDE.md "novels" /
pasted code that goes stale · rules without rationale · carrying stale context.

## Conventions worth surfacing

- **Never paste secrets/credentials** — API keys, passwords, private keys, tokens.
  Rotate and move to a secret store.
- **Keep sensitive data / PII out of prompts** — anonymize or use synthetic data.
- **Higher stakes → more verification** — the higher the blast radius, the more expert
  review the output needs. "Would I ship this without checking?"
- **Human-review gates over direct action** — prepare commits/PRs for review, don't
  push to protected branches on the user's behalf.
- **Tone** — practical, empowering; the agent is a capable junior colleague, not an
  oracle. The user stays the senior engineer.
- **Mantras usable as tags** — "Always verify" · "Task + Context + Format +
  Constraints" · "Read before you write."
