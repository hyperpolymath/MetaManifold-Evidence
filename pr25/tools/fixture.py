"""Print every expected constant the two Julia test files assert, as Julia
literals, from tools/clr_model.py. Run this, then tools/rcheck/check.py to see
the same numbers come out of real R.

    python3 tools/fixture.py
"""
import sys
sys.path.insert(0, "/home/user/tools")
import clr_model as M  # noqa: E402

# Built from the taxon structure rather than typed, so a row cannot quietly lose
# its last column: 12 taxa (p, q, r, s, t1..t7 rare and group-specific, ghost
# never observed), 8 samples, 61 of 96 cells zero, 'A1' a two-read library.
TAXA = ["p", "q", "r", "s", "t1", "t2", "t3", "t4", "t5", "t6", "t7", "ghost"]
_ROWS = {
    "A1": {"p": 1, "q": 1},
    "A2": {"p": 20, "q": 8, "r": 12, "s": 10, "t1": 30},
    "A3": {"p": 18, "q": 6, "r": 14, "s": 9, "t2": 30},
    "B1": {"p": 25, "q": 40, "r": 10, "s": 12, "t3": 30},
    "B2": {"p": 22, "q": 45, "r": 11, "s": 13, "t4": 30},
    "B3": {"p": 21, "q": 52, "r": 9, "s": 11, "t5": 32},
    "B4": {"p": 19, "q": 61, "s": 10, "t6": 32},
    "B5": {"p": 23, "q": 33, "r": 12, "t7": 32},
}
SAMPLES = list(_ROWS)
SPARSE = [[_ROWS[n].get(t, 0) for t in TAXA] for n in SAMPLES]
assert len(SPARSE) == 8 and all(len(r) == 12 for r in SPARSE)
assert sum(v == 0 for r in SPARSE for v in r) == 61
assert [sum(r) for r in SPARSE] == [2, 80, 77, 117, 121, 125, 122, 100]
assert [sum(r[:4]) for r in SPARSE] == [2, 50, 47, 87, 91, 93, 90, 68]  # the kept table
UNF = [r[:11] for r in SPARSE]
KEPT = [r[:4] for r in SPARSE]
UNF = [r[:11] for r in SPARSE]
HAND = [[0, 2, 8], [4, 0, 6]]
NOZ = [[1, 0, 3], [0, 5, 2], [4, 2, 0], [2, 3, 1]]
ONEZERO = [[2, 8], [4, 0]]
SHALLOW = [[0, 0, 0, 0, 1], [6, 4, 0, 0, 0], [0, 0, 6, 4, 0]]
GROUPS = ["A", "A", "A", "B", "B", "B", "B", "B"]
EFFECT_TAXA = [
    [7, 17, 1, 12, 10, 3, 15, 14, 6, 11, 15, 9, 52, 18, 40, 57, 25, 58, 8, 43, 65, 31, 47, 36],
    [32, 18, 44, 6, 43, 27, 39, 14, 30, 49, 23, 35, 14, 35, 27, 49, 6, 32, 44, 23, 43, 30, 18, 39],
    [81, 50, 22, 65, 39, 71, 59, 10, 45, 73, 54, 31, 4, 8, 8, 2, 6, 1, 5, 9, 1, 7, 3, 6],
]
EFFECT = [list(r) for r in zip(*EFFECT_TAXA)]
EG = ["A"] * 12 + ["B"] * 12
SMALL = [-1.0, 0.5, 2.0, -0.25, 0.1, 1.5, 3.0, -1.25]
SMALL_G = ["A", "A", "A", "B", "B", "B", "B", "B"]


def julia_matrix(rows, indent=28):
    pad = " " * indent
    body = ";\n".join(" ".join("%.17g" % v for v in r) for r in rows)
    return ("[" + (";" + "\n" + pad).join(" ".join("%.17g" % v for v in r) for r in rows) + "]")


def vec(v):
    return "[" + ", ".join("%.17g" % x for x in v) + "]"


def show_repl(name, X, deltas=(0.05, 0.65, 0.99)):
    print("== %s  (%d x %d)" % (name, len(X), len(X[0])))
    for d in deltas:
        try:
            out, mass, nzero, colmin = M.cmult_repl([list(map(float, r)) for r in X], frac=d)
        except ValueError as e:
            print("  delta %.2f -> refuses: %s" % (d, e))
            continue
        print("  delta %.2f, zeros %d, mass %s" % (d, nzero, vec(mass)))
        for row in out:
            print("      " + " ".join("%.17g" % v for v in row))
    print("  colmin (proportions): %s" % vec([c if c != float("inf") else c for c in colmin]))
    print("  1 - row sums: %s" % vec([abs(sum(r) - 1.0) for r in out]))


def show_welch(tag, z, groups, ref, con, ntax=None):
    ia = [i for i, g in enumerate(groups) if g == ref]
    ib = [i for i, g in enumerate(groups) if g == con]
    m = ntax or len(z[0])
    out = {"estimate": [], "se": [], "statistic": [], "pvalue": [], "df": []}
    pool = {"pvalue": [], "df": []}
    for j in range(m):
        col = [z[i][j] for i in range(len(z))]
        b = [col[i] for i in ib]
        a = [col[i] for i in ia]
        w = M.welch(b, a)
        for k in out:
            out[k].append(w[k])
        p = M.pooled_t(b, a)
        pool["pvalue"].append(p["pvalue"])
        pool["df"].append(p["df"])
    print("-- %s" % tag)
    for k in ("estimate", "se", "statistic", "pvalue", "df"):
        print("   %-9s %s" % (k, vec(out[k])))
    print("   pooled_p  %s" % vec(pool["pvalue"]))
    print("   pooled_df %s" % vec(pool["df"]))
    return out


def small_cases():
    """The 6 x 4 fixture in test_differential.jl, both orders."""
    x = [[10, 20, 0, 0], [12, 18, 0, 0], [11, 19, 3, 0], [30, 8, 0, 0], [28, 9, 0, 0], [33, 7, 0, 0]]
    g = ["A", "A", "A", "B", "B", "B"]
    print("== six-sample fixture, min_prevalence 0.5: the NEW order (filter, then replace)")
    r = M.pipeline(x, g, "A", "B", min_prevalence=0.5)
    for row in r["rows"]:
        print("   kept=%s est %.17g se %.17g t %.17g p %.17g df %.17g padj %.17g"
              % (row["taxon"], row["estimate"], row["se"], row["statistic"], row["pvalue"],
                 row["df"], row["padj"]))
    print("   zeros %d, replaced in %d samples, excluded %d, unobserved %d, max mass %.17g"
          % (r["zeros"], r["n_samples_replaced"], r["n_excluded"], r["n_unobserved"], r["max_imputed"]))
    print("== the OLD order (replace over 3 observed taxa, then filter)")
    obs = [row[:3] for row in x]
    closed, mass, nz, colmin = M.cmult_repl([list(map(float, row)) for row in obs], frac=0.65)
    z = M.clr(closed)
    ia = [0, 1, 2]; ib = [3, 4, 5]
    for j, name in enumerate(["p", "q", "rare"]):
        b = [z[i][j] for i in ib]; a_ = [z[i][j] for i in ia]
        w = M.welch(b, a_)
        print("   %-5s est %.17g se %.17g p %.17g   (imputed mass %s)"
              % (name, w["estimate"], w["se"], w["pvalue"], vec(mass)))
    print("   the estimate for p differs by %.6g between the two orders"
          % abs(r["rows"][0]["estimate"] - M.welch([z[i][0] for i in ib],
                                                   [z[i][0] for i in ia])["estimate"]))
    print("== a taxon whose two groups are each constant")
    v = [[1.0], [1.0], [2.0], [2.0]]
    col = [r[0] for r in v]
    print("   unique overall %d, per group %d/%d -> the note fires, and t.test would say:"
          % (len(set(col)), len(set(col[:2])), len(set(col[2:]))))
    w = M.welch([2.0, 2.0], [1.0, 1.0])
    print("   model welch (var=0): %s" % {k: ("nan" if str(v2) == "nan" else "%.17g" % v2)
                                          for k, v2 in w.items()})


def main():
    small_cases()
    show_repl("hand  [0 2 8; 4 0 6]", HAND)
    show_repl("onezero  [2 8; 4 0]", ONEZERO, (0.65,))
    show_repl("kept (sparse, first four taxa)", KEPT)
    show_repl("nozero  4x3", NOZ)

    print("== shallow refusal  [0 0 0 0 1; 6 4 0 0 0; 0 0 6 4 0]")
    got = M.pipeline(SHALLOW, ["a", "b", "c"], "b", "c", min_prevalence=0.0, delta=0.65)
    print("   ", got.get("refused"), got.get("detail"))
    for d in (0.5, 0.55, 0.556, 0.65):
        r = M.pipeline(SHALLOW, ["a", "b", "c"], "b", "c", min_prevalence=0.0, delta=d)
        print("   delta %-6s -> %s" % (d, "refused" if "refused" in r else "runs"))

    print("== unfiltered sparse (11 taxa) refusal numbers")
    for mp, label in ((0.0, "min_prevalence 0.0"), (0.125, "min_prevalence 0.125"),
                      (0.25, "min_prevalence 0.25")):
        r = M.pipeline(SPARSE, GROUPS, "A", "B", min_prevalence=mp, samples=SAMPLES)
        if "refused" in r:
            d = r["detail"]
            print("   %-22s refused: %s" % (label, r["refused"]))
            print("   %-22s bound %.17g, sample index %d, n_zeros %d"
                  % ("", d["bound"], d["index"], d["n_zeros"]))
        else:
            print("   %-22s runs: %d kept, %d zeros, mass %s"
                  % (label, len(r["kept"]), r["zeros"], vec(r["mass"])))
    print("   prevalence per taxon:", vec([sum(1 for i in range(8) if SPARSE[i][j] > 0) / 8
                                           for j in range(12)]))
    print("   row totals:", [sum(r) for r in SPARSE])

    print("== kept sparse at min_prevalence 0.25: the whole result")
    r = M.pipeline(KEPT, GROUPS, "A", "B", min_prevalence=0.25)
    for name, row in zip(["p", "q", "r", "s"], r["rows"]):
        print("   %-2s est %-20.17g se %-20.17g t %-18.17g p %-20.17g df %-18.17g padj %.17g"
              % (name, row["estimate"], row["se"], row["statistic"], row["pvalue"],
                 row["df"], row["padj"]))
    print("   diagnostics: zeros %d, samples replaced %d, excluded %d, unobserved %d, "
          "max %.17g median %.17g"
          % (r["zeros"], r["n_samples_replaced"], r["n_excluded"], r["n_unobserved"],
             r["max_imputed"], r["median_imputed"]))
    show_welch("Welch vs pooled on the kept sparse table",
               M.clr(r["closed"]), GROUPS, "A", "B", ntax=4)

    print("== effect fixture (no zeros, plain CLR)")
    closed = [[v / sum(row) for v in row] for row in EFFECT]
    z = M.clr(closed)
    show_welch("Welch vs pooled on the effect table", z, EG, "A", "B", ntax=3)
    p = [M.welch([z[i][j] for i in range(24) if EG[i] == "B"],
                 [z[i][j] for i in range(24) if EG[i] == "A"])["pvalue"] for j in range(3)]
    print("   padj: %s" % vec(M.bh_adjust(p)))
    print("   row sums of closed:", vec([abs(sum(c) - 1) for c in closed]))

    print("== the small three-against-five case")
    w = M.welch([SMALL[i] for i in range(8) if SMALL_G[i] == "B"],
                [SMALL[i] for i in range(8) if SMALL_G[i] == "A"])
    pl = M.pooled_t([SMALL[i] for i in range(8) if SMALL_G[i] == "B"],
                    [SMALL[i] for i in range(8) if SMALL_G[i] == "A"])
    print("   welch ", vec([w[k] for k in ("estimate", "se", "statistic", "pvalue", "df")]))
    print("   pooled", vec([pl[k] for k in ("estimate", "se", "statistic", "pvalue", "df")]))
    print("   bh of [0.01 0.02 0.03 0.04]: %s" % vec(M.bh_adjust([.01, .02, .03, .04])))

    print("\n== the effect fixture's R-verified numbers, for the literals in the tests")
    closed = [[v / sum(row) for v in row] for row in EFFECT]
    z = M.clr(closed)
    for j, name in enumerate(["t_up", "t_flat", "t_down"]):
        w = M.welch([z[i][j] for i in range(24) if EG[i] == "B"],
                    [z[i][j] for i in range(24) if EG[i] == "A"])
        print("   %-7s est %.17g  se %.17g  t %.17g  p %.17g  df %.17g"
              % (name, w["estimate"], w["se"], w["statistic"], w["pvalue"], w["df"]))
    print("== the CLR itself, first row of the kept table (a hand check)")
    print("   log-geometric-mean check: %s" % vec([sum(v) for v in M.clr(r["closed"])]))


if __name__ == "__main__":
    main()
