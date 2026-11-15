# Builds the documentation with Documenter.jl:
#
#     julia --project=docs -e 'using Pkg; Pkg.instantiate()'   # once
#     julia --project=docs docs/make.jl
#
# The pages under docs/src take their code from the scripts in examples/basics, so
# the scripts stay the only copy and the pages always show their real output. In a
# page, inside a fenced block:
#
#     #! include first_pack.jl main  the script's `# ANCHOR: main` region
#     #! setup first_pack.jl         the script's lines before its first ANCHOR
#                                    (its imports and includes), for an @setup block
#
# The pages with those lines filled in are written to docs/build-src (not
# committed), and Documenter builds from there. On CI, deploydocs publishes the
# result to the gh-pages branch.

using Documenter, DocumenterMermaid
using SenMLFormat

const EXAMPLES = normpath(joinpath(@__DIR__, "..", "examples", "basics"))
const SRC = joinpath(@__DIR__, "src")
const GEN = joinpath(@__DIR__, "build-src")

"""The lines of `file` between `# ANCHOR: region` and `# ANCHOR_END: region`, without
the anchor lines of any region nested inside."""
function region(file, name)
    lines = readlines(joinpath(EXAMPLES, file))
    first = findfirst(==("# ANCHOR: $name"), strip.(lines))
    last = findfirst(==("# ANCHOR_END: $name"), strip.(lines))
    (first === nothing || last === nothing) && error("$file has no region $name")
    keep = filter(l -> !startswith(strip(l), "# ANCHOR"), lines[first+1:last-1])
    return join(keep, '\n')
end

"""The setup lines of a script: everything before its first ANCHOR that is not a
comment, with `include("x.jl")` made to point into examples/basics."""
function setup(file)
    out = String[]
    for line in readlines(joinpath(EXAMPLES, file))
        startswith(strip(line), "# ANCHOR") && break
        (isempty(strip(line)) || startswith(strip(line), "#")) && continue
        m = match(r"^include\(\"(.+)\"\)$", strip(line))
        push!(out, m === nothing ? line : "include($(repr(joinpath(EXAMPLES, m[1]))))")
    end
    return join(out, '\n')
end

function expand(text)
    lines = map(split(text, '\n')) do line
        m = match(r"^(\s*)#! (include|setup) (\S+)(?: (\S+))?\s*$", line)
        m === nothing && return line
        indent, what, file, name = m[1], m[2], m[3], m[4]
        body = what == "setup" ? setup(file) :
               name === nothing ? rstrip(read(joinpath(EXAMPLES, file), String)) :
               region(file, name)
        return join((isempty(l) ? l : indent * l for l in split(body, '\n')), '\n')
    end
    return join(lines, '\n')
end

rm(GEN; force = true, recursive = true)
for (dir, _, files) in walkdir(SRC), f in files
    target = joinpath(GEN, relpath(joinpath(dir, f), SRC))
    mkpath(dirname(target))
    if endswith(f, ".md")
        write(target, expand(read(joinpath(dir, f), String)))
    else
        cp(joinpath(dir, f), target)
    end
end

makedocs(
    sitename = "SenMLFormat.jl",
    root = @__DIR__,
    source = "build-src",
    modules = [SenMLFormat],
    repo = Remotes.GitHub("nhenehan", "SenMLFormat.jl"),
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "") == "true",
        canonical = "https://nhenehan.github.io/SenMLFormat.jl/stable",
        edit_link = nothing,
    ),
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "manual/glossary.md",
            "manual/getting-started.md",
            "manual/first-pack.md",
            "manual/formats.md",
            "manual/resolve.md",
            "manual/validate.md",
            "manual/streaming.md",
            "manual/errors.md",
            "manual/untrusted-input.md",
        ],
        "API reference" => [
            "api/model.md",
            "api/formats.md",
            "api/media.md",
            "api/validate.md",
            "api/resolve.md",
            "api/units.md",
            "api/errors.md",
        ],
        "Appendix" => [
            "appendix/rfc-choices.md",
            "appendix/conformance.md",
            "appendix/comparison.md",
            "appendix/performance.md",
            "appendix/side-by-side.md",
            "appendix/thanks.md",
        ],
    ],
    pagesonly = true,
    # Every exported name must be documented and listed in the API reference.
    checkdocs = :exports,
    warnonly = false,
)

if get(ENV, "CI", "") == "true"
    deploydocs(repo = "github.com/nhenehan/SenMLFormat.jl.git", devbranch = "main", push_preview = false)
end
