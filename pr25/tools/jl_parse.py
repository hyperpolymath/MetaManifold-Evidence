# SPDX-License-Identifier: AGPL-3.0-only
"""Parse Julia files with tree-sitter and report anything the parser could not read.

There is no Julia in this sandbox, so this is the strongest static check
available on the sources the tests and the package are written in: it catches
unbalanced `end`s, broken string literals and malformed argument lists, which is
what an anchor-splice into a long file tends to produce. It does not check
semantics, so a green run here is a licence to hand the file to `julia --project=.
test/runtests.jl`, not a substitute for it.

    python3 tools/jl_parse.py src/analysis/differential.jl test/unit/test_differential.jl
"""
import sys

from tree_sitter import Language, Parser
import tree_sitter_julia

JULIA = Language(tree_sitter_julia.language())


def check(path):
    src = open(path, "rb").read()
    tree = Parser(JULIA).parse(src)
    problems = []

    def walk(node):
        if node.is_missing:
            problems.append("line %d: missing %s" % (node.start_point[0] + 1, node.type))
        elif node.has_error:
            if node.child_count == 0:
                problems.append("line %d: unmatched syntax (%s)"
                                % (node.start_point[0] + 1, node.type))
            else:
                for c in node.children:
                    walk(c)

    walk(tree.root_node)
    if problems:
        print(" FAIL %s" % path)
        for p in problems[:12]:
            print("      " + p)
        if len(problems) > 12:
            print("      ... %d more" % (len(problems) - 12))
    else:
        print("  ok  %s" % path)
    return not problems


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2
    bad = [p for p in argv if not check(p)]
    print()
    if bad:
        print("%d of %d file(s) do not parse" % (len(bad), len(argv)))
        return 1
    print("all %d file(s) parse" % len(argv))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
