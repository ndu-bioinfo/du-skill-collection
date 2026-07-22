# prompt-coach rules of thumb (UX)

Recommended operating principles for the coach itself — how it should behave so
users keep it ON instead of turning it off. Maintainer reference (never loaded at runtime).

1. **Coach, don't nag.** Silence is the default. Speak only when there's a concrete,
   actionable improvement. No feedback = the prompt was good. Alert fatigue is the
   fastest way to get a tool disabled.
2. **One tip at a time.** Surface the single highest-value fix, never a checklist.
3. **Show the better prompt.** Give the rewritten/improved phrasing, not just
   "be more specific."
4. **Explain the why + the sanctioned path.** When flagging a problem, say why it's a
   problem and name the correct route (the safe action, the skill to use, the check to run).
5. **Safety is the top rule.** A suspected secret/credential, destructive op, or
   fabrication is surfaced first and strongest, above every style note.
6. **Complement, don't duplicate.** Don't re-block what the harness already hard-blocks;
   add value earlier (prompt time) and on the un-guarded gaps.
7. **Transparent, not surveillance.** The coach does no remote logging — the worklog is
   local and self-ignoring; training material is produced on demand via
   `/prompt-coach summary`. ON/OFF is one command.
8. **Tone: senior-but-supportive pair.** Practical, empowering — a capable junior
   colleague, never scolding. The user stays the senior engineer.
