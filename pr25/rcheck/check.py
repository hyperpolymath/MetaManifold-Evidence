# SPDX-License-Identifier: AGPL-3.0-only
"""Compare what R said (generated/out.txt) with the independent model.

The model in ../clr_model.py is where every literal in test/unit/test_zero_
replacement.jl and the clr_lm testsets of test/unit/test_differential.jl came
from. This script fails unless R agrees with the model on every tagged line the
harness emitted, and unless every long literal the tests assert appears in R's
output. p-values are compared to 1e-9 rather than 1e-12: the model evaluates
Student's t through a continued fraction, which loses relative precision in the
far tail (about 3e-14 at p = 4e-4), and R's own pt() is authoritative.
"""
import math
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = pathlib.Path(os.environ.get("METAMANIFOLD_WEBUI", "/home/user/MetaManifold-WebUI"))

sys.path.insert(0, "/home/user/tools")
import clr_model as M  # noqa: E402
import fixture as F    # noqa: E402

ZERO_FREE_MSG = "Label 0 was not found in the data set"
NEGATIVE_MSG = "X contains negative values"
ONE_ROW_MSG = "X must be a data matrix with at least two rows"
DEGEN_NOTE = "each group has one distinct value, so no variance can be estimated"
CONST_NOTE = "the values are constant across samples: there is nothing to estimate"

HAND = [[0, 2, 8], [4, 0, 6]]
ONEZERO = [[2, 8], [4, 0]]
SIX = [[10, 20, 0, 0], [12, 18, 0, 0], [11, 19, 3, 0], [30, 8, 0, 0], [28, 9, 0, 0], [33, 7, 0, 0]]
SIX_KEPT = [[r[0], r[1]] for r in SIX]
SIX_ALL = [r[:3] for r in SIX]
SPARSE_KEPT = [[F.SPARSE[i][j] for j in range(4)] for i in range(8)]
SPARSE_ALL = [[F.SPARSE[i][j] for j in range(11)] for i in range(8)]

failures = []


def check(tag, kind, want, got, tol=1e-12):
    """One expectation, reported by tag so a failure names the R line at fault."""
    if got is None:
        failures.append("%s: R produced no such line (expected %s)" % (tag, kind))
        return
    if kind == "num":
        w = want if isinstance(want, list) else [want]
        g = got if isinstance(got, list) else [got]
        if len(w) != len(g):
            failures.append("%s: %d values from R, %d expected" % (tag, len(g), len(w)))
            return
        for i, (a, b) in enumerate(zip(w, g)):
            if a is None or (isinstance(a, float) and math.isnan(a)):
                if b is not None and not math.isnan(b):
                    failures.append("%s[%d]: expected nothing, R gave %.17g" % (tag, i + 1, b))
                continue
            if b is None or (isinstance(b, float) and math.isnan(b)):
                failures.append("%s[%d]: R gave nothing, expected %.17g" % (tag, i + 1, a))
                continue
            scale = max(1.0, abs(a), abs(b))
            if abs(a - b) > tol * scale:
                failures.append("%s[%d]: model %.17g vs R %.17g (diff %.3g)"
                                % (tag, i + 1, a, b, abs(a - b)))
    else:
        w = want if isinstance(want, list) else [want]
        g = got if isinstance(got, list) else [got]
        if len(w) != len(g):
            failures.append("%s: %d fields from R, %d expected" % (tag, len(g), len(w)))
            return
        for i, (a, b) in enumerate(zip(w, g)):
            if a != b:
                failures.append("%s[%d]: model %r vs R %r" % (tag, i + 1, a, b))


def read_lines():
    out = {}
    for line in (HERE / "generated" / "out.txt").read_text().splitlines():
        if not line.strip():
            continue
        tag, _, payload = line.partition("|")
        payload = payload.partition("|")[2]
        if "\x1f" in payload:
            out[tag] = ("str", payload.split("\x1f"))
            continue
        if payload:
            vals = []
            for tok in payload.split():
                try:
                    vals.append(float(tok))
                except ValueError:
                    vals = None
                    break
            if vals is not None:
                out[tag] = ("num", vals)
                continue
        out[tag] = ("str", [payload] if payload else [])
    return out


def rows_of(res):
    keys = ("estimate", "se", "statistic", "pvalue", "df")
    return {k: [r[k] for r in res["rows"]] for k in keys}


def main():
    r = read_lines()

    for name, x, delta in (("hand", HAND, 0.65), ("onezero", ONEZERO, 0.65),
                           ("sparse_kept", SPARSE_KEPT, 0.65),
                           ("sparse_all", SPARSE_ALL, 0.65),
                           ("hand_shallow", HAND, 0.05), ("hand_deep", HAND, 0.99)):
        closed, mass, _nz, _cm = M.cmult_repl([list(map(float, row)) for row in x], frac=delta)
        check("repl.%s.out" % name, "num", [v for row in closed for v in row],
              _val(r, "repl.%s.out" % name))
        check("repl.%s.mass" % name, "num", mass, _val(r, "repl.%s.mass" % name))
        check("repl.%s.rest" % name, "num",
              [1.0 - sum(row) for row in closed], _val(r, "repl.%s.rest" % name))
        obs = [closed[i][j] for i in range(len(x)) for j in range(len(x[0])) if x[i][j] > 0]
        check("repl.%s.minobs" % name, "num", min(obs), _val(r, "repl.%s.minobs" % name))
        check("repl.%s.positive" % name, "str", "yes" if all(v > 0 for v in obs) else "no",
              _val(r, "repl.%s.positive" % name))
        check("repl.%s.error" % name, "str", "none", _val(r, "repl.%s.error" % name))
    check("repl.six_kept.error", "str", ZERO_FREE_MSG, _val(r, "repl.six_kept.error"))
    check("msg.zero_free", "str", ZERO_FREE_MSG, _val(r, "msg.zero_free"))
    check("msg.negative", "str", NEGATIVE_MSG, _val(r, "msg.negative"))
    check("msg.one_row", "str", ONE_ROW_MSG, _val(r, "msg.one_row"))

    chains = (("sparse_kept", SPARSE_KEPT, F.GROUPS, 0.25),
              ("six_kept", SIX_KEPT, ["A", "A", "A", "B", "B", "B"], 0.5),
              ("six_all", SIX_ALL, ["A", "A", "A", "B", "B", "B"], 0.0),
              ("effect", F.EFFECT, F.EG, 0.0))
    for name, x, groups, mp in chains:
        if name == "sparse_kept":
            res = M.pipeline(F.SPARSE, F.GROUPS, "A", "B", min_prevalence=mp, samples=F.SAMPLES)
        else:
            res = M.pipeline(x, groups, "A", "B", min_prevalence=mp)
        vals = rows_of(res)
        p = vals["pvalue"]
        check("chain.%s.estimate" % name, "num", vals["estimate"], _val(r, "chain.%s.estimate" % name))
        check("chain.%s.se" % name, "num", vals["se"], _val(r, "chain.%s.se" % name))
        check("chain.%s.statistic" % name, "num", vals["statistic"], _val(r, "chain.%s.statistic" % name))
        # p-values carry the model's own tail error, so they get a looser bound.
        check("chain.%s.pvalue" % name, "num", p, _val(r, "chain.%s.pvalue" % name), tol=1e-9)
        check("chain.%s.df" % name, "num", vals["df"], _val(r, "chain.%s.df" % name))
        check("chain.%s.bh" % name, "num", M.bh_adjust(p), _val(r, "chain.%s.bh" % name), tol=1e-9)
        check("chain.%s.status" % name, "str", ["ok"] * len(p), _val(r, "chain.%s.status" % name))
        check("chain.%s.note" % name, "str", [""] * len(p), _val(r, "chain.%s.note" % name))
        if name == "sparse_kept":
            z = M.clr(res["closed"])
            mass = res["mass"]
        elif name == "six_all":
            closed, mass, _n, _c = M.cmult_repl([list(map(float, row)) for row in x], frac=0.65)
            z = M.clr(closed)
        else:
            tot = [sum(row) for row in x]
            closed = [[v / t for v in row] for row, t in zip(x, tot)]
            z = M.clr(closed)
            mass = [0.0] * len(x)
        check("chain.%s.clr" % name, "num", [v for row in z for v in row], _val(r, "chain.%s.clr" % name))
        check("chain.%s.mass" % name, "num", mass, _val(r, "chain.%s.mass" % name))
        ia = [i for i, g in enumerate(groups) if g == "A"]
        ib = [i for i, g in enumerate(groups) if g == "B"]
        pooled = [M.pooled_t([z[i][j] for i in ib], [z[i][j] for i in ia])["pvalue"]
                  for j in range(len(p))]
        check("chain.%s.pooled" % name, "num", pooled, _val(r, "chain.%s.pooled" % name), tol=1e-9)

    # The notes are text the shipped R snippet writes; they must match the Julia
    # source character for character, since the tests compare them that way.
    src = (REPO / "src/analysis/differential.jl").read_text()
    for note in (DEGEN_NOTE, CONST_NOTE):
        if '"%s"' % note not in src:
            failures.append("the note %r is not in differential.jl any more" % note)
    check("fit.degen.status", "str", ["failed", "ok"], _val(r, "fit.degen.status"))
    check("fit.degen.note", "str", [DEGEN_NOTE, ""], _val(r, "fit.degen.note"))
    check("fit.const.status", "str", ["failed"], _val(r, "fit.const.status"))
    check("fit.const.note", "str", [CONST_NOTE], _val(r, "fit.const.note"))
    check("fit.single.status", "str", ["failed"], _val(r, "fit.single.status"))
    # The numbers of those three fits: nothing for the two that cannot estimate,
    # and one ordinary Welch test for the taxon that can.
    dg = M.welch([3.0, 9.0], [1.0, 5.0])   # contrast B minus reference A
    check("fit.degen.estimate", "num", [None, 3.0], _val(r, "fit.degen.estimate"))
    check("fit.degen.pvalue", "num", [None, dg["pvalue"]], _val(r, "fit.degen.pvalue"), tol=1e-9)
    check("fit.degen.df", "num", [None, dg["df"]], _val(r, "fit.degen.df"))
    for tag in ("fit.const.estimate", "fit.const.pvalue", "fit.const.df",
                "fit.single.estimate", "fit.single.pvalue", "fit.single.df"):
        check(tag, "num", [None], _val(r, tag))
    if "not enough 'x' observations" not in _txt(r, "fit.single.note"):
        failures.append("fit.single.note: R's own t.test error is not in %r"
                        % _txt(r, "fit.single.note"))

    literals(r)

    known = set(r)
    expected = set(EXPECTED)
    unexplained = sorted(known - expected)
    if unexplained:
        failures.append("R lines with no expectation: %s" % ", ".join(unexplained))
    missing = sorted(expected - known)
    if missing:
        failures.append("expected lines R never printed: %s" % ", ".join(missing))

    print("%d tagged lines from R, %d expectations checked" % (len(known), len(EXPECTED)))
    if failures:
        print("\n".join("FAIL " + f for f in failures))
        return 1
    print("R and the model agree on every line, and every long literal in the "
          "tests is one R itself printed.")
    return 0


EXPECTED = set()


def _val(r, tag):
    if tag not in r:
        return None
    kind, v = r[tag]
    return v if kind == "num" else (v[0] if len(v) == 1 else v)


def _txt(r, tag):
    kind, v = r.get(tag, ("str", []))
    return " ".join(v) if isinstance(v, list) else str(v)


NUM = re.compile(r"(?<![\d.])(-?\d\.\d{8,}(?:e-?\d+)?)")


def literals(r):
    """Every constant with more than eight figures in the two test files has to
    be a number R printed, not one a model or a memory produced."""
    flat = [v for _tag, (kind, vals) in r.items() if kind == "num" and vals
            for v in vals if v is not None]
    for rel in ("test/unit/test_differential.jl", "test/unit/test_zero_replacement.jl"):
        scanning = rel.endswith("zero_replacement.jl")   # that whole file is R-facing
        for lineno, line in enumerate((REPO / rel).read_text().splitlines(), 1):
            m = re.match(r'\s*@testset "([^"]+)"', line)
            if m:
                scanning = bool(re.match(r"(clr_lm|CLR|fit_welch|.*sparse table)", m.group(1)))
            if not scanning:
                continue
            if "padj" in line or "@test_skip" in line or line.lstrip().startswith("#"):
                continue
            for lit in NUM.findall(line):
                x = float(lit)
                if not any(abs(x - v) <= 1e-10 * max(1.0, abs(v)) for v in flat):
                    failures.append("%s:%d: %s matches nothing R printed" % (rel, lineno, lit))


if __name__ == "__main__":
    # EXPECTED is the set of tags the harness should have produced, so a dropped
    # case is an error rather than a silent pass.
    for name, _x, _d in (("hand", HAND, 0.65), ("onezero", ONEZERO, 0.65),
                         ("sparse_kept", SPARSE_KEPT, 0.65), ("sparse_all", SPARSE_ALL, 0.65),
                         ("hand_shallow", HAND, 0.05), ("hand_deep", HAND, 0.99)):
        EXPECTED |= {"repl.%s.%s" % (name, k) for k in
                     ("out", "mass", "rest", "minobs", "positive", "error")}
    EXPECTED.add("repl.six_kept.error")
    EXPECTED |= {"msg.zero_free", "msg.negative", "msg.one_row"}
    for name in ("sparse_kept", "six_kept", "six_all", "effect"):
        EXPECTED |= {"chain.%s.%s" % (name, k) for k in
                     ("estimate", "se", "statistic", "pvalue", "df", "bh", "status",
                      "note", "clr", "mass", "pooled")}
    EXPECTED |= {"fit.degen.status", "fit.degen.note", "fit.const.status", "fit.const.note",
                 "fit.single.status", "fit.single.note"}
    for f in ("degen", "const", "single"):
        EXPECTED |= {"fit.%s.%s" % (f, k) for k in ("estimate", "pvalue", "df")}
    sys.exit(main())
