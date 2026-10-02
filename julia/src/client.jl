# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

# Read a counts table from a running MetaManifold through its public
# results-table query route. Nothing in MetaManifold is imported.

"Names MetaManifold accepts for studies, runs, tables and groups."
const SAFE_NAME = r"^[A-Za-z0-9._-]+$"

"""
    safe_name(kind, s) -> String

Return `s` if it is a plain name, and refuse anything that could change the
route (slashes, `..`, query characters).
"""
function safe_name(kind::AbstractString, s::AbstractString)
    (occursin(SAFE_NAME, s) && s != "." && s != "..") ||
        throw(ArgumentError("invalid $kind name: $(repr(s))"))
    return String(s)
end

"""
    fetch_counts(base_url, study, run, table; group = nothing, per_page = 10_000)

Page through `POST /api/v1/studies/{study}/runs/{run}/results/tables/{table}/query`
and return a [`CountsTable`](@ref). Sample columns are the ones the app itself
reports as `sample_count_columns`.
"""
function fetch_counts(base_url::AbstractString, study, run, table;
                      group = nothing, per_page::Integer = 10_000)
    url = string(rstrip(base_url, '/'), "/api/v1/studies/", safe_name("study", study),
                 "/runs/", safe_name("run", run), "/results/tables/", safe_name("table", table),
                 "/query")
    group === nothing || (url *= "?group=" * safe_name("group", group))
    rows = Any[]
    columns = sample_columns = nothing
    page = 1
    while true
        resp = HTTP.post(url, ["Content-Type" => "application/json"],
                         JSON3.write((; page, perPage = per_page)); status_exception = false)
        resp.status == 200 ||
            error("MetaManifold returned HTTP $(resp.status) for $url: $(String(resp.body))")
        j = JSON3.read(resp.body)
        columns = j.columns
        sample_columns = j.sample_count_columns
        append!(rows, j.rows)
        length(rows) >= j.total && break
        isempty(j.rows) && error("MetaManifold returned an empty page $page after $(length(rows)) of $(j.total) rows")
        page += 1
    end
    return table_from_rows(rows, columns, sample_columns)
end
