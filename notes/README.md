# PR #25 rework — handoff

Everything here is about `MetaManifold-WebUI` PR #25 ("Add a CLR linear-model method for
differential abundance", `CHANGES_REQUESTED` by the owner on 2026-10-02). The code was written in a
throwaway clone; these are the durable parts.

| file | what it is |
| --- | --- |
| `0001-*.patch`, `0002-*.patch` | the rework, two `git format-patch` commits on `1ee3e71` |
| `pr25-rework-full.diff` | the same change as one `git diff` (14 files, +896/−186) |
| `pr25-draft-reply.md` | the reply to post on the PR, point by point against the four asks |
| `pr25-issue-rpackages.md` | the follow-up issue the reply references (provenance does not record MASS / zCompositions) |
| `pr25-rework-prompt.md` | the brief for doing this work from scratch: target repo, the four asks, the facts that cost time, acceptance list |

## Apply it

```bash
git fetch https://github.com/JoshuaJewell/MetaManifold-WebUI.git pull/25/head:pr25
git worktree add ../pr25-rework -b feat/differential-clr-rework pr25   # or checkout -B in place
cd ../pr25-rework
git am /path/to/notes/0001-*.patch /path/to/notes/0002-*.patch
```

Verified by applying exactly that way in a clean worktree at `1ee3e71`: `git apply --check` clean,
`git am` clean, resulting tree byte-identical to the one these patches were made from.

The commits are authored as `Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>`
(the identity configured in the Arena clone). To make them yours with your own details instead:

```bash
git rebase -i --exec 'git commit --amend --no-edit --reset-author' 1ee3e71
```

One commit instead of two, if that is preferred: `git apply pr25-rework-full.diff && git commit -a`.

Then, when it has been read:

```bash
git push origin feat/differential-clr-rework:feat/differential-clr      # updates PR #25 in place
gh pr comment 25 --repo hyperpolymath/MetaManifold-WebUI --body-file notes/pr25-draft-reply.md
```

Neither was run from here: pushing to someone else's PR branch and posting a reply under their
account are the two steps that should stay with the person who owns the timeline.

## What is and is not verified

Ran, and green:

- `bun install --frozen-lockfile`, `bun run test` (32 pass, 0 fail, 81 expectations) and
  `bun run typecheck` in `frontend/` — including three new tests for `zeroReplacementLine`.
- The guard's arithmetic, the prevalence advice and both new fixtures (the 4×4 `test_zero_replacement`
  table and the 40×24 sparse `test_differential` one) were worked out by hand and re-derived
  independently, because the assertions quote exact numbers (`29.9` against a total of `15`; `780`
  against `212`; advice `0.05` where the offending taxa are seen in `1` of `40`).

Not run, and this is the gap:

- **No Julia.** The sandbox could not reach `pkg.julialang.org`, the release asset host, or
  `deb.debian.org`, and there is no `R` either — so nothing in `src/analysis/*.jl` was compiled, let
  alone executed. `CI` is the first thing that will actually run it. As a substitute, every changed
  `.jl` file went through a token-level structure check (pygments' Julia lexer: block openers against
  `end`s, brackets, unterminated strings, with strings and comments excluded so the embedded R cannot
  fake a keyword). All five files are balanced; the only diagnostics are the lexer tripping on `\"`
  inside R string literals, which it also does in untouched pre-existing code (`_FIT_R`), so it says
  nothing about these edits.
- The RCall paths — `zCompositions::multRepl`, `stats::t.test`, the global-environment handoff and
  cleanup — have never met R. They are written against the packages' documented signatures
  (`multRepl(X, label, dl, frac, imp.missing, closure, z.warning, z.delete, delta)`;
  `t.test.default`'s estimate being `mean(x) − mean(y)`), not against a run.
- The three added `renv.lock` entries are hand-written metadata in renv's format, in renv's key
  order, with the file still valid JSON and the same 81 → 84 package count. They should be replaced
  by a real `renv::snapshot()` under R 4.5.0 before merge; `test/unit/test_install_pins.jl` only
  compares the R and Bioconductor *runtime* versions against `config/pins.yml`, so the hand-written
  entries will not fail CI — they will just be less trustworthy than a snapshot.

The likeliest first CI failures, in order, so they are not a surprise: a Julia typing detail in the
new code (e.g. `Matrix{Float64}(RCall.rcopy(...))` or a `Union` in a signature); the exact wording of
an R error message that a test asserts on; a zCompositions argument name that moved. All three are
one-line fixes, and all three are things that only an execution can catch.
