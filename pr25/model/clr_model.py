"""An independent implementation of the clr_lm pipeline, for deriving and
checking the numbers the Julia tests assert.

This is written from zCompositions 1.6.2's own R source (tools/rcheck/zc/R/
cmultRepl.R), not from a paper summary, so that "the model agrees" means
something: same rule, same order of operations, same floating point shape.

    python3 tools/fixture.py            # print every constant the tests use
    python3 tools/rcheck/check.py       # compare them with real R's output
"""
import math


def cmult_repl(counts, frac=0.65, threshold=0.5, adjust=True, z_warning=1.0, z_delete=False):
    """`cmultRepl(X, label = 0, method = "CZM", output = "prop", ...)`.

    counts: list of rows (samples) of non-negative integers.
    Returns (matrix of proportions, per-row imputed mass, number of zeros).
    """
    n, m = len(counts), len(counts[0])
    if n < 2:
        raise ValueError("X must be a data matrix with at least two rows")
    if any(v < 0 for row in counts for v in row):
        raise ValueError("X contains negative values")
    if not any(v == 0 for row in counts for v in row):
        raise ValueError("Label 0 was not found in the data set")
    row_tot = [sum(r) for r in counts]
    if any(t <= 0 for t in row_tot):
        raise ValueError("row sums must be positive")
    # X2: proportions of each sample's own total, None where the count is zero.
    X2 = [[(v / t if v != 0 else None) for v in row] for row, t in zip(counts, row_tot)]
    # z.warning decides whether a column or row that is mostly zeros is deleted;
    # this project calls with z.warning = 1, which nothing can exceed, so the
    # table keeps its shape. Assert that the call stayed as assumed.
    if z_warning <= 1.0 and any(sum(1 for i in range(n) if X2[i][j] is None) / n > z_warning
                               for j in range(m)):
        raise NotImplementedError("z.warning below 1 needs z.delete handled too")
    zeros_row = [sum(1 for j in range(m) if X2[i][j] is None) for i in range(n)]
    # CZM: every zero of sample i gets frac * threshold / n_i, on the closed scale.
    repl = [[frac * threshold / t for _ in range(m)] for t in row_tot]
    colmin = []
    for j in range(m):
        seen = [X2[i][j] for i in range(n) if X2[i][j] is not None]
        colmin.append(min(seen) if seen else math.inf)
    mass = [0.0] * n
    for i in range(n):
        z = [j for j in range(m) if X2[i][j] is None]
        if not z:
            continue
        for j in z:
            X2[i][j] = repl[i][j]
            if adjust and X2[i][j] > colmin[j]:
                X2[i][j] = frac * colmin[j]
        taken = sum(X2[i][j] for j in z)
        mass[i] = taken
        for j in range(m):
            if j not in z:
                X2[i][j] = (1 - taken) * X2[i][j]
    assert all(v is not None for row in X2 for v in row)
    return X2, mass, sum(zeros_row), colmin


def clr(closed):
    """Centred log-ratio of each row: log(x) minus the row's mean log."""
    out = []
    for row in closed:
        l = [math.log(v) for v in row]
        mean = sum(l) / len(l)
        out.append([v - mean for v in l])
    return out


def var(v):
    n = len(v)
    mu = sum(v) / n
    return sum((x - mu) ** 2 for x in v) / (n - 1)


def student_cdf(t, df):
    """P(T <= t) for Student's t, via the incomplete beta function.

    I_x(a, b) with x = df/(df+t^2), a = df/2, b = 1/2, continued fraction as
    in Numerical Recipes; the same value R's pt() returns to ~1e-15.
    """
    x = df / (df + t * t)
    p = 0.5 * _betai(df / 2.0, 0.5, x)
    return 1.0 - p if t > 0 else p


def _betacf(a, b, x):
    MAXIT, EPS, FPMIN = 300, 3e-16, 1e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    if abs(d) < FPMIN:
        d = FPMIN
    d = 1.0 / d
    h = d
    for m in range(1, MAXIT + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        de = d * c
        h *= de
        if abs(de - 1.0) < EPS:
            break
    return h


def _betai(a, b, x):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    lbeta = (math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
             + a * math.log(x) + b * math.log1p(-x))
    bt = math.exp(lbeta)
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _betacf(a, b, x) / a
    return 1.0 - bt * _betacf(b, a, 1.0 - x) / b


def welch(b, a):
    """Welch's t.test(b, a, var.equal = FALSE). Returns the five statistics."""
    nb, na = len(b), len(a)
    mb, ma = sum(b) / nb, sum(a) / na
    vb, va = var(b), var(a)
    se2 = vb / nb + va / na
    est = mb - ma
    if se2 == 0:
        return dict(estimate=est, se=0.0, statistic=math.nan, pvalue=math.nan, df=math.nan)
    se = math.sqrt(se2)
    t = est / se
    df = se2 ** 2 / ((vb / nb) ** 2 / (nb - 1) + (va / na) ** 2 / (na - 1))
    p = 2.0 * (1.0 - student_cdf(abs(t), df))
    return dict(estimate=est, se=se, statistic=t, pvalue=p, df=df)


def pooled_t(b, a):
    """The pooled version, i.e. what `t.test(..., var.equal = TRUE)` and a
    one-covariate `lm` give: the contrast the Welch numbers have to differ from."""
    nb, na = len(b), len(a)
    mb, ma = sum(b) / nb, sum(a) / na
    sp2 = ((nb - 1) * var(b) + (na - 1) * var(a)) / (nb + na - 2)
    se = math.sqrt(sp2 * (1 / nb + 1 / na))
    t = (mb - ma) / se
    df = nb + na - 2
    # R's pt for integer df, same continued fraction.
    p = 2.0 * (1.0 - student_cdf(abs(t), df))
    return dict(estimate=mb - ma, se=se, statistic=t, pvalue=p, df=float(df))


def bh_adjust(p):
    """`p.adjust(p, "BH")`: step-up, capped at 1, non-decreasing in p."""
    n = len(p)
    if n == 0:
        return []
    order = sorted(range(n), key=lambda i: -p[i])
    out = [0.0] * n
    running = 1.0
    for k, idx in enumerate(order):
        rank = n - k
        running = min(running, n / rank * p[idx])
        out[idx] = min(running, 1.0)
    return out


def median(v):
    s = sorted(v)
    n = len(s)
    return 0.5 * (s[n // 2 - 1] + s[n // 2]) if n % 2 == 0 else s[n // 2]


def pipeline(counts, groups, reference, contrast, min_prevalence=0.0, delta=0.65,
             threshold=0.5, samples=None):
    """What differential_abundance does for clr_lm, in order: drop taxa with no
    reads, filter by prevalence, replace zeros over what is left, take the CLR,
    test each taxon with Welch's t, adjust with Benjamini-Hochberg.

    Returns a dict with `rows`, or {"refused": message} where Julia throws.
    """
    n, m = len(counts), len(counts[0])
    present = [sum(1 for i in range(n) if counts[i][j] > 0) for j in range(m)]
    prevalence = [p / n for p in present]
    kept = [j for j in range(m) if present[j] > 0 and prevalence[j] >= min_prevalence]
    if len(kept) < 2:
        return dict(refused="the centred log-ratio needs at least 2 taxa with reads at "
                            "or above analysis.differential.min_prevalence")
    sub = [[counts[i][j] for j in kept] for i in range(n)]
    has_zero = any(v == 0 for row in sub for v in row)
    mass = [0.0] * n
    if has_zero:
        # The refusal the wrapper raises before R is asked for anything.
        tot = [sum(r) for r in sub]
        colmin = []
        for j in range(len(kept)):
            seen = [sub[i][j] / tot[i] for i in range(n) if sub[i][j] > 0]
            colmin.append(min(seen) if seen else math.inf)
        refused = []
        for i in range(n):
            z = [j for j in range(len(kept)) if sub[i][j] == 0]
            if not z:
                continue
            u = delta * threshold / tot[i]
            mass_i = sum(u if u <= colmin[j] else delta * colmin[j] for j in z)
            if mass_i >= 1:
                refused.append((i, len(z), mass_i, math.ceil(delta / mass_i * 1000) / 1000.0))
        if refused:
            i, k, mass_i, bound = refused[0]
            name = _sample_name(i) if samples is None else samples[i]
            # Word for word what src/analysis/zero_replacement.jl throws, so the
            # two can be diffed rather than re-derived by hand.
            msg = ("sample '%s' has %d zeros whose replacements at delta = %s would hold "
                   "%.1f%% of its total, leaving nothing for the taxa it does have. The "
                   "largest delta that can still work is below %s. Raise "
                   "analysis.differential.min_prevalence, so that the composition being "
                   "replaced over is the one the test is run on, or lower "
                   "analysis.differential.replacement_delta to take the zeros one tier "
                   "at a time." % (name, k, delta, 100 * mass_i, _fig3(bound)))
            return dict(refused=msg, detail=dict(index=i, n_zeros=k, mass=mass_i, bound=bound))
        closed, mass, n_zero, colmin = cmult_repl(sub, frac=delta, threshold=threshold)
    else:
        tot = [sum(r) for r in sub]
        closed = [[v / t for v in r] for r, t in zip(sub, tot)]
        n_zero = 0
    z = clr([[v for v in row] for row in closed])
    ia = [i for i, g in enumerate(groups) if g == reference]
    ib = [i for i, g in enumerate(groups) if g == contrast]
    if len(ia) < 2 or len(ib) < 2:
        return dict(refused="Welch's t test needs a variance in each of them: at least "
                            "2 samples per group")
    rows = []
    for j in range(len(kept)):
        col = [z[i][j] for i in range(n)]
        b, a = [col[i] for i in ib], [col[i] for i in ia]
        if len(set(col)) < 2:
            rows.append(dict(taxon=kept[j], status="failed", note="constant", estimate=None,
                             se=None, statistic=None, pvalue=None, df=None))
            continue
        st = welch(b, a)
        st["status"] = "ok"
        st["note"] = ""
        st["taxon"] = kept[j]
        st["prevalence"] = prevalence[kept[j]]
        rows.append(st)
    fitted = [r for r in rows if r["status"] == "ok" and r["se"]]
    padj = bh_adjust([r["pvalue"] for r in fitted])
    for r, q in zip(fitted, padj):
        r["padj"] = q
    for r in rows:
        r.setdefault("padj", None)
    return dict(rows=rows, mass=mass, kept=kept, zeros=n_zero,
                n_samples_replaced=sum(1 for v in mass if v > 0),
                n_excluded=sum(1 for j in range(m) if present[j] > 0) - len(kept),
                n_unobserved=sum(1 for j in range(m) if present[j] == 0),
                max_imputed=max(mass), median_imputed=median(mass),
                closed=closed)


_sample_name = lambda i: "sample %d" % (i + 1)


def _fig3(x):
    """Julia prints a Float64 rounded to 3 digits as the shortest form that reads
    back as itself, which is what the message does with `bound[i]`."""
    return repr(round(x, 3))
