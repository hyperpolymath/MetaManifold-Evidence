# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

# HTTP routes. Each handler is a plain function from parsed input to a
# response, so the routes can be tested without a socket.
#
#   GET  /api/v1/evidence/health
#   GET  /api/v1/evidence/fibre?reads=R&noise=N
#   POST /api/v1/evidence/verdicts      {noise_bound, table | tsv | source}
#   GET  /*                             static files of the web UI, if built

"Default port. Deliberately not an 8080-class port; MetaManifold uses 8080."
const DEFAULT_PORT = 47613

"""
    json_response(status, body)

A JSON HTTP response.
"""
json_response(status::Integer, body) =
    HTTP.Response(status, ["Content-Type" => "application/json"], JSON3.write(body))

"""
    fibre_response(reads, noise_bound)

The fibre and verdict for a single cell.
"""
function fibre_response(reads::Integer, noise_bound::Integer)
    f = fibre(reads, noise_bound)
    return Dict("reads" => reads, "noise_bound" => noise_bound, "lo" => f.lo, "hi" => f.hi,
                "size" => f.hi - f.lo + 1, "verdict" => verdict_name(count_verdict(reads, noise_bound)))
end

"""
    verdicts_response(table, noise_bound)

Verdicts for every cell, with the receipt. Cells are `[reads, verdict, lo, hi]`,
or `null` where the source value was not a read count.
"""
function verdicts_response(table::CountsTable, noise_bound::Integer)
    results = evaluate(table, noise_bound)
    rows = [Dict("id" => r.id,
                 "cells" => [c.verdict === nothing ? nothing :
                             Any[c.reads, verdict_name(c.verdict), c.lo, c.hi] for c in r.cells])
            for r in results]
    return Dict("id_column" => table.id_column, "samples" => table.samples, "rows" => rows,
                "receipt" => receipt(table, noise_bound, results))
end

"""
    table_from_json(t) -> CountsTable

Parse `{id_column, ids, samples, counts}` from a request body.
"""
function table_from_json(t)
    ids = String.(collect(t.ids))
    samples = String.(collect(t.samples))
    rows = collect(t.counts)
    length(rows) == length(ids) || throw(ArgumentError("counts has $(length(rows)) rows for $(length(ids)) ids"))
    counts = Matrix{Union{Int,Nothing}}(nothing, length(ids), length(samples))
    for (i, row) in enumerate(rows)
        length(row) == length(samples) || throw(ArgumentError("row $i has $(length(row)) cells for $(length(samples)) samples"))
        for j in eachindex(samples)
            counts[i, j] = as_count(row[j])
        end
    end
    return CountsTable(String(get(t, :id_column, "id")), ids, samples, counts)
end

"""
    resolve_table(body, metamanifold_url) -> CountsTable

The table named by a request: inline (`table`), a TSV string (`tsv`), or
`source = {study, run, table, group?}` read from the MetaManifold instance this
server was started against. The URL is server configuration, never taken from
the request.
"""
function resolve_table(body, metamanifold_url)
    haskey(body, :table) && return table_from_json(body.table)
    haskey(body, :tsv) && return read_tsv(IOBuffer(String(body.tsv)))
    if haskey(body, :source)
        metamanifold_url === nothing &&
            throw(ArgumentError("this server was started without a MetaManifold URL"))
        s = body.source
        return fetch_counts(metamanifold_url, String(s.study), String(s.run), String(s.table);
                            group = haskey(s, :group) && s.group !== nothing ? String(s.group) : nothing)
    end
    throw(ArgumentError("the request needs one of: table, tsv, source"))
end

"""
    parse_nat(s, name) -> Int

A query or body value as a natural number, or an `ArgumentError`.
"""
function parse_nat(s, name::AbstractString)
    v = s isa Integer ? Int(s) : tryparse(Int, string(s))
    (v === nothing || v < 0) && throw(ArgumentError("$name must be a natural number, got $(repr(s))"))
    return v
end

"""
    router(; metamanifold_url = nothing, web_root = nothing) -> HTTP.Router

The routes. `web_root` is a directory of built UI files to serve, if any.
"""
function router(; metamanifold_url = nothing, web_root = nothing)
    r = HTTP.Router(_ -> HTTP.Response(404, "not found"))
    HTTP.register!(r, "GET", "/api/v1/evidence/health", _ -> json_response(200, Dict(
        "ok" => true, "model" => MODEL,
        "proofs" => Dict(String(k) => v for (k, v) in pairs(PROOF_PINS)),
        "metamanifold" => metamanifold_url)))
    HTTP.register!(r, "GET", "/api/v1/evidence/fibre", req -> _guard() do
        q = HTTP.queryparams(HTTP.URI(req.target))
        json_response(200, fibre_response(parse_nat(get(q, "reads", ""), "reads"),
                                          parse_nat(get(q, "noise", ""), "noise")))
    end)
    HTTP.register!(r, "POST", "/api/v1/evidence/verdicts", req -> _guard() do
        body = JSON3.read(req.body)
        n = parse_nat(get(body, :noise_bound, nothing), "noise_bound")
        json_response(200, verdicts_response(resolve_table(body, metamanifold_url), n))
    end)
    if web_root !== nothing
        root = realpath(web_root)
        HTTP.register!(r, "GET", "/**", req -> _static(root, HTTP.URI(req.target).path))
        HTTP.register!(r, "GET", "/", _ -> _static(root, "/index.html"))
    end
    return r
end

"""
    _guard(f)

Run a handler, turning bad input into a 400 and anything else into a 500
without leaking a stack trace.
"""
function _guard(f)
    try
        return f()
    catch e
        e isa Union{ArgumentError,DomainError,DimensionMismatch,JSON3.Error} &&
            return json_response(400, Dict("error" => sprint(showerror, e)))
        @error "evidence route failed" exception = (e, catch_backtrace())
        return json_response(500, Dict("error" => "internal error"))
    end
end

"Content types for the files a bun build emits."
const MIME = Dict(".html" => "text/html; charset=utf-8", ".js" => "text/javascript",
                  ".css" => "text/css", ".svg" => "image/svg+xml", ".json" => "application/json",
                  ".map" => "application/json")

"""
    _static(root, path)

Serve `path` from `root`, refusing anything that resolves outside it.
"""
function _static(root::AbstractString, path::AbstractString)
    rel = lstrip(HTTP.unescapeuri(path), '/')
    isempty(rel) && (rel = "index.html")
    full = abspath(joinpath(root, rel))
    (startswith(full, root * "/") && isfile(full)) || return HTTP.Response(404, "not found")
    ext = lowercase(splitext(full)[2])
    return HTTP.Response(200, ["Content-Type" => get(MIME, ext, "application/octet-stream")], read(full))
end

"""
    serve(; host = "127.0.0.1", port = DEFAULT_PORT, metamanifold_url, web_root)

Start the Evidence server and block. Returns when the server is closed.
"""
function serve(; host = "127.0.0.1", port::Integer = DEFAULT_PORT,
               metamanifold_url = get(ENV, "METAMANIFOLD_URL", nothing),
               web_root = _default_web_root())
    @info "MetaManifold-Evidence listening" host port metamanifold_url web_root
    HTTP.serve(router(; metamanifold_url, web_root), host, port)
end

"""
    _default_web_root()

The built UI next to this package (`../web/dist`), if it exists.
"""
function _default_web_root()
    d = normpath(joinpath(@__DIR__, "..", "..", "web", "dist"))
    return isdir(d) ? d : nothing
end
