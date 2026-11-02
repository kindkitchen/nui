use lib.nu
use ../emit.nu

# Retrieve code-review comments with their addresses.
#
# Lists valid comments only: `just check code-review` lists the broken ones.
# Each has file, line-start, line-end, line-next-nonempty (the line it's about),
# comment, meta and raw. Paths are relative to the repository root.
@example "all comments" { just retrieve code-review }
@example "comments in cli/ having value = 67 in meta" { just retrieve code-review cli --meta='value = 67' }
@example "pipe into nushell" { just retrieve code-review | from json | select file line-start comment }
def main [
    ...paths: string        # Where to look, relative to the root; everywhere by default.
    --meta: string          # Keep comments whose meta includes this TOML, e.g. 'value = 67'.
    --marker-start: string  # Use this start marker instead of the configured one.
    --marker-end: string    # Use this end marker instead of the configured one.
    --marker-meta: string   # Use this meta marker instead of the configured one.
] {
    cd $lib.root
    let markers = lib markers {marker-start: $marker_start, marker-end: $marker_end, marker-meta: $marker_meta}
    lib scan $markers $paths
        | lib only-meta $meta
        | where ($it.problems | is-empty)
        | select file line-start line-end line-next-nonempty comment meta raw
        | emit
}
