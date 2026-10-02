# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

using Test
using HTTP
using JSON3
using MetaManifoldEvidence
using MetaManifoldEvidence: verdicts_response, safe_name, _static
using ResidualEvidenceTypes: decide, candidates, ENTAILED, REFUTED, UNRESOLVED, INCONSISTENT

"Presence: the latent abundance is at least one (Agda: `Present`)."
present(w) = latent(w) >= 1

const GRID = 0:12

const TSV = "OTU\tS1\tS2\tS3\nOtu001\t120\t0\t3\nOtu002\t0\t\tNA\nOtu003\t5\t2.5\t7\n"

@testset "MetaManifoldEvidence" begin

@testset "closed form agrees with generic decide (tested; proved in Agda)" begin
    checked = 0
    for y in GRID, n in GRID
        c = count_case(y, n)
        @test decide(c, present).status == count_verdict(y, n)
        ls = sort(unique(latent.(candidates(c))))
        f = fibre(y, n)
        @test ls == collect(f.lo:f.hi)
        checked += 1
    end
    # Non-vacuous: every grid point ran, and all three reachable verdicts occur.
    @test checked == length(GRID)^2
    vs = Set(count_verdict(y, n) for y in GRID, n in GRID)
    @test vs == Set([ENTAILED, REFUTED, UNRESOLVED])
    @test !(INCONSISTENT in vs)
end

@testset "boundary cases named by the Agda reject controls" begin
    @test count_verdict(2, 2) == UNRESOLVED   # reject/EntailedAtBound
    @test count_verdict(0, 1) == UNRESOLVED   # reject/RefutedUnderNoise
    @test count_verdict(3, 1) == ENTAILED     # reject/VerdictMislabel
    @test count_verdict(0, 0) == REFUTED
    @test fibre(0, 3) == (lo = 0, hi = 3)
    @test_throws DomainError count_verdict(-1, 0)
    @test_throws DomainError fibre(1, -1)
end


@testset "TSV input contract" begin
    t = read_tsv(IOBuffer(TSV))
    @test t.id_column == "OTU"
    @test t.ids == ["Otu001", "Otu002", "Otu003"]
    @test t.samples == ["S1", "S2", "S3"]
    @test t.counts[1, :] == [120, 0, 3]
    @test t.counts[2, 2] === nothing && t.counts[2, 3] === nothing
    @test t.counts[3, 2] === nothing          # fractional is not a read count
    @test_throws ArgumentError read_tsv(IOBuffer("OTU\tS1\nOtu1\t1\t2\n"))
    @test_throws ArgumentError read_tsv(IOBuffer(""))
end

@testset "evaluate and receipt" begin
    t = read_tsv(IOBuffer(TSV))
    res = evaluate(t, 3)
    @test length(res) == 3
    @test res[1].cells[1].verdict == ENTAILED
    @test res[1].cells[2].verdict == UNRESOLVED
    @test res[1].cells[3].verdict == UNRESOLVED
    @test res[2].cells[2].verdict === nothing
    r = receipt(t, 3, res)
    @test r["verdicts"] == Dict("entailed" => 3, "refuted" => 0, "unresolved" => 3, "not_a_count" => 3)
    @test sum(values(r["verdicts"])) == 9
    @test r["noise_bound"] == 3 && r["model"] == MODEL
    @test length(r["input_sha256"]) == 64 && all(in("0123456789abcdef"), r["input_sha256"])
    @test verify_receipt(t, r)
    @test verify_receipt(t, JSON3.read(JSON3.write(r)))   # survives the wire
    # Planted positive: a receipt for different data must not verify.
    t2 = read_tsv(IOBuffer(replace(TSV, "120" => "121")))
    @test !verify_receipt(t2, r)
    @test receipt(t, 0, evaluate(t, 0))["verdicts"]["refuted"] == 2
end

@testset "rows from MetaManifold's query response" begin
    rows = [Dict("OTU" => "Otu1", "Genus" => "Bacteroides", "F3D0" => 10, "F3D1" => 0),
            Dict("OTU" => "Otu2", "Genus" => nothing, "F3D0" => 1, "F3D1" => nothing)]
    t = table_from_rows(rows, ["OTU", "Genus", "F3D0", "F3D1"], ["F3D0", "F3D1"])
    @test t.ids == ["Otu1", "Otu2"] && t.samples == ["F3D0", "F3D1"]
    @test t.counts == Union{Int,Nothing}[10 0; 1 nothing]
end

@testset "routes" begin
    r = router()
    get(path) = r(HTTP.Request("GET", path))
    post(path, body) = r(HTTP.Request("POST", path, ["Content-Type" => "application/json"], JSON3.write(body)))

    h = get("/api/v1/evidence/health")
    @test h.status == 200 && JSON3.read(h.body).model == MODEL

    f = get("/api/v1/evidence/fibre?reads=5&noise=2")
    @test f.status == 200
    j = JSON3.read(f.body)
    @test (j.lo, j.hi, j.size, j.verdict) == (3, 7, 5, "entailed")
    @test get("/api/v1/evidence/fibre?reads=-1&noise=2").status == 400
    @test get("/api/v1/evidence/fibre?reads=x").status == 400

    v = post("/api/v1/evidence/verdicts", (; noise_bound = 3, tsv = TSV))
    @test v.status == 200
    j = JSON3.read(v.body)
    @test length(j.rows) == 3
    @test j.rows[1].cells[1] == [120, "entailed", 117, 123]
    @test j.rows[2].cells[2] === nothing
    @test j.receipt.verdicts.entailed == 3

    inline = (; noise_bound = 0, table = (; id_column = "OTU", ids = ["a", "b"], samples = ["S"],
                                          counts = [[0], [4]]))
    j = JSON3.read(post("/api/v1/evidence/verdicts", inline).body)
    @test [c[2] for c in (j.rows[1].cells[1], j.rows[2].cells[1])] == ["refuted", "entailed"]

    @test post("/api/v1/evidence/verdicts", (; tsv = TSV)).status == 400
    @test post("/api/v1/evidence/verdicts", (; noise_bound = 1)).status == 400
    # No MetaManifold configured: a source request is refused, not attempted.
    @test post("/api/v1/evidence/verdicts",
               (; noise_bound = 1, source = (; study = "s", run = "r", table = "t"))).status == 400
    @test get("/nope").status == 404
end

@testset "static files stay inside the web root" begin
    mktempdir() do d
        write(joinpath(d, "index.html"), "<p>ok</p>")
        root = realpath(d)
        @test _static(root, "/").status == 200
        @test _static(root, "/index.html").status == 200
        @test _static(root, "/%2e%2e/%2e%2e/etc/passwd").status == 404
        @test _static(root, "/../../etc/passwd").status == 404
    end
end

@testset "client pages MetaManifold's query route" begin
    @test_throws ArgumentError safe_name("study", "../x")
    @test_throws ArgumentError safe_name("run", "a/b")
    @test_throws ArgumentError safe_name("group", "g?x=1")

    all_rows = [Dict("OTU" => "Otu$i", "Genus" => "G", "F3D0" => i - 1, "F3D1" => 2i) for i in 1:5]
    seen = String[]
    stub = HTTP.serve!("127.0.0.1", 0; listenany = true) do req
        push!(seen, req.target)
        b = JSON3.read(req.body)
        lo = (b.page - 1) * b.perPage + 1
        page = all_rows[lo:min(end, lo + b.perPage - 1)]
        HTTP.Response(200, JSON3.write((; total = 5, columns = ["OTU", "Genus", "F3D0", "F3D1"],
                                        sample_count_columns = ["F3D0", "F3D1"], rows = page)))
    end
    try
        port = HTTP.port(stub)
        t = fetch_counts("http://127.0.0.1:$port/", "miseq", "run1", "otu_table"; group = "all", per_page = 2)
        @test length(seen) == 3                     # pages 1, 2, 3 of size 2
        @test all(==("/api/v1/studies/miseq/runs/run1/results/tables/otu_table/query?group=all"), seen)
        @test t.ids == ["Otu$i" for i in 1:5]
        @test t.counts[:, 1] == [0, 1, 2, 3, 4]
        # Through the server, with the URL as configuration.
        r = router(; metamanifold_url = "http://127.0.0.1:$port")
        resp = r(HTTP.Request("POST", "/api/v1/evidence/verdicts", [],
                              JSON3.write((; noise_bound = 1, source = (; study = "miseq", run = "run1", table = "otu_table")))))
        @test resp.status == 200
        @test JSON3.read(resp.body).receipt.taxa == 5
    finally
        close(stub)
    end
end

end
