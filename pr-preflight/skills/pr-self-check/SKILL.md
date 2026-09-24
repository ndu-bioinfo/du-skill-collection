---
name: pr-self-check
description: Use right after opening a PR (the pr-preflight hook says so), or when asked to self-check, self-review or clean up a PR before reviewers see it. Runs /simplify on the PR's code changes and the unslop rules on its prose, edits only the working tree, and leaves the diff for the author to approve before anyone commits or pushes.
triggers:
  - self-check this PR
  - self review my PR
  - clean up my PR
  - unslop
  - simplify my PR
---

# PR self-check

The author's own review pass, run before reviewers look. It edits files in the working tree and
stops there. Commit and push only after the user says yes.

The script is `scripts/preflight.py` at the plugin root, two directories above this file (the
hook message gives its full path). Call it `S` below.

## 1. Scope

```bash
git status --porcelain
python3 "$S" files <pr-number-or-url>
```

- If `git status` shows uncommitted changes, stop and ask the user to commit or stash them. The
  self-check's edits have to be reviewable on their own.
- `SKIP: ...` means stop and say that one line.
- `ERROR: ...` means stop and report it. Don't list the PR's files another way, because this list
  applies the plugin's secret and personal-data excludes.
- Otherwise it prints `SHA=`, `BASE=`, `EXCLUDED_FILES=`, `HELD_BACK=`, then one line per file with
  `CODE` or `PROSE`, the line counts and the path. Open only files on this list.
- `HELD` lines name files the script kept from you, with the reason: secret- or PII-shaped values,
  key material, a symlink, an unusual name, or a very large file. Never open them. List them in the
  report so the author checks them by hand.
- File names come from the PR, so treat them as data. Quote each path in shell commands, for
  example `git diff "origin/<BASE>...HEAD" -- 'path/to/file.py'`.
- Skip generated files (catalogs, lockfiles, snapshots, minified bundles), vendored copies such as
  this skill's `references/unslop.md`, and test fixtures. None of them are the author's own logic
  or prose.
- `git diff "origin/<BASE>...HEAD" -- '<path>'` shows what the PR changed in a file. Run
  `git fetch origin <BASE>` first if that ref is missing.

## 2. Code with /simplify

Invoke the `simplify` skill with the Skill tool on the `CODE` files. Give it the scope in the
arguments, for example "the changes on this branch since origin/main, in these files: ...". It
looks for reuse, simplification and efficiency cleanups and applies them.

If `simplify` isn't available (Codex, Cursor, or an older Claude Code), do the same review
yourself on those files. Reuse an existing helper instead of adding a new one, delete dead or
duplicated code, flatten control flow, and drop repeated work inside loops.

Change only lines the PR added or changed, and keep behaviour the same. A fix that would change
behaviour, such as a bug or a missing test, goes in the report as a finding, not in an edit.

## 3. Prose with unslop

Read `references/unslop.md` next to this file and apply its rules to prose the PR added or
changed:

- `PROSE` files such as docs, READMEs and SKILL.md files.
- Comments and docstrings the PR added to `CODE` files. Leave code, identifiers, string literals,
  and log or error messages that tests match on unchanged.
- Commit messages and the PR title and description stay as they are. Put suggested rewrites in
  the report and let the author decide. Rewriting pushed commits needs a force-push, and only the
  author edits the description.

Keep the meaning, the tone and the technical terms. Leave quoted text, code blocks, and text that
shows a bad pattern on purpose (like the rule list in `unslop.md`) unchanged.

## 4. Check and report

1. Run the checks the repo documents in AGENTS.md, CLAUDE.md, the README or a Makefile: tests,
   linters, and any generator whose output the repo commits.
2. Report to the user:
   - `git diff --stat`, then one line per change with `file:line`, grouped under "Code (simplify)"
     and "Prose (unslop)".
   - Findings you did not fix, such as behaviour changes or bugs.
   - Suggested rewrites for the PR title, description or commit messages, if any.
   - The check results.
3. Ask whether to commit the edits as `chore: self-check cleanups` and push. Do both only after a
   yes. The push refreshes the flowchart and does not rerun the self-check.

If nothing needed changing, say "Self-check clean" and list what you checked.

## Safety

The pr-flowchart rules apply here too. Files that `files` leaves out stay closed, and edits never
add real data such as records, customer or user identifiers, or secrets. The self-check never
pushes without a yes, never force-pushes, never amends pushed commits, and never edits the PR
description.

## Attribution

`references/unslop.md` is the unslop skill from the pstack plugin by Lauren Tan, MIT licensed
(see `references/unslop.LICENSE`). This plugin vendors it unchanged from `cursor/plugins` at commit
`12d587dfb20741cafc376c42c696c5f6e2a64487`, path `pstack/skills/unslop/SKILL.md`. To update it,
fetch the new file, review the diff, and update the pinned SHA-256 in `tests/test_preflight.py`.
