# Token & prompt-cache rules (context economy)

Part of the one-time rubric injected on the first coached turn, so cache/context
coaching is available all session. Live token/cache telemetry is reported to the user
out-of-context (a `systemMessage`), not fed to the model — so apply these rules when
the user's prompt is about context/token/cache economy, or when they ask about a
telemetry warning they saw.

**You do NOT have a context-fill number in your context** — the real figure only ever
arrives in the out-of-context `systemMessage`. So **never infer that context is "full"
from the apparent size of your own prompt.** A long tool/MCP/skill/agent listing inflates
how much text you see, but it is a fixed, cached prefix — not the window filling up with
work. Only assert high fill when a telemetry warning actually reported it; otherwise the
honest move is "run `/context` for the real number," NOT a reflexive `/compact`.

Prompt caching in Claude
Code is **prefix-based**: the cache matches from the start of the context, so any
change to an *earlier* part invalidates ("busts") the cache for everything after
it — the whole suffix must be re-read at full price. Maximizing caching = keeping
the early context stable and the total context lean.

Give ONE tip, the highest-value one for what the numbers show. **Priority: the
cache-instability signals (rule 1) come first** — a busting prompt cache silently
re-charges you full price for the prefix on *every* turn, and it is the one thing no
built-in command surfaces (there is no `/context` for cache health). Context fill is
NOT the coach's to raise: Claude Code already auto-prompts `/compact`, so **never hint
`/compact`** — the coach's only fill-related value is the levers the system does not
surface (prune tools/MCP, targeted reads).

1. **Cache-hit low / cache_creation churning →** something early in the *rendered
   prefix* keeps changing. Usual causes, in order: adding/removing/reordering an MCP
   server or tool mid-session; switching the model mid-session; memory/CLAUDE.md
   edits. (Editing a file on disk does NOT bust the cache — the bytes already in the
   transcript don't change; that's a context-fill cost, see 4.) Fix: finish tool/MCP
   setup before the working session; batch context-shaping changes up front.
2. **Context fill high — the system owns this; do NOT hint `/compact`.** Claude Code
   already auto-prompts `/compact` as the window nears its limit, and `/compact` **busts
   the prompt cache** anyway (it rewrites the conversation into a summary → the prefix is
   re-read at full price next turn), so the coach adds nothing by naming it. If fill is
   genuinely high, give only the non-duplicative levers the system does *not* surface:
   prune unused tools/MCP (rule 3) or use targeted reads (rule 4) to reclaim space cheaply.
   You do NOT have a fill number in your context — never claim fill is high without a
   telemetry warning, and never from the length of the tool/MCP/skill list; point the user
   to `/context` for the real figure instead.
3. **Trim standing context, not just messages.** Unused MCP servers and tools cost
   tokens on *every* turn and sit in the cached prefix — disable ones this session
   won't use. Prune stale memory files; keep CLAUDE.md tight.
4. **Big reads are expensive twice** — once to read, then on every subsequent turn
   they ride in context. Prefer targeted reads (offset/limit, grep) over whole-file
   reads when you only need a slice; delegate broad searches to a subagent so the
   file dumps stay out of the main context.
5. **Stable prefix = cheap turns.** The longer the early context stays byte-for-byte
   identical, the more turns hit the cache. Keep the churn at the *end* (new
   messages), not the beginning.

Never nag: if the numbers are healthy, say nothing. One tip, with the concrete
action ("finish MCP/tool setup up front so the prefix stops busting", "disable the
X MCP server for this session", "read that file with a grep/offset instead of whole").

## How the coach itself stays cache-friendly (context economy of the coach)

The coach practises what it preaches. Its own footprint is optimised for Claude
Code's automatic prefix caching:

- **Injected once, not every turn.** The full rubric is added to the context on the
  first coached turn per session/CWD (guarded by a marker file), so it sits at a
  stable point in the prefix and is cache-read on every later turn. Later turns inject
  only a tiny, mostly-stable reminder — the heavy bytes are paid for once.
- **No variable tail in context.** Session telemetry and per-turn feedback are NOT
  injected — telemetry surfaces as a `systemMessage` (out of context) and the full
  per-turn context breakdown + feedback are written to the CWD worklog
  (`./.prompt-coach/`). Keeping variable content out of the injected block is what lets
  the rubric stay a stable, cacheable prefix.
- **Deterministic assembly.** The rubric is concatenated from the rule files in a
  fixed order, so the bytes are identical run to run.

**Honest ceiling:** a hook cannot set `cache_control` / cache breakpoints — Claude
Code owns those. The coach can only optimise *for* the automatic prefix cache, not
guarantee a hit. A `/compact` or other context edit can still drop the once-injected
rubric; the per-turn reminder keeps the coaching alive if that happens, and the
summary's `chain_break` reporting shows when caching broke and why.
