use lib.nu
use ../emit.nu

# Remove code-review comments: their whole lines.
#
# Only observes by default: lists the comments that would go; --apply removes them.
# Any broken comment in scope blocks the removal, whatever --meta says;
# --skip-broken removes the valid ones and leaves the broken untouched.
# Broken comments are never removed.
@example "observe" { just remove code-review }
@example "remove the ones having done = true in meta" { just remove code-review --meta='done = true' --apply }
@example "remove the valid ones despite broken ones" { just remove code-review --skip-broken --apply }
def main [
    ...paths: string        # Where to look, relative to the root; everywhere by default.
    --skip-broken           # Remove the valid comments, leave the broken ones untouched.
    --apply                 # Remove instead of only listing.
    --meta: string          # Keep comments whose meta includes this TOML, e.g. 'value = 67'.
    --marker-start: string  # Use this start marker instead of the configured one.
    --marker-end: string    # Use this end marker instead of the configured one.
    --marker-meta: string   # Use this meta marker instead of the configured one.
] {
    cd $lib.root
    let markers = lib markers {marker-start: $marker_start, marker-end: $marker_end, marker-meta: $marker_meta}
    let items = lib scan $markers $paths

    # Blockers are checked before any write, so observing shows them too.
    let broken = $items | where ($it.problems | is-not-empty)
    if ($broken | is-not-empty) and not $skip_broken {
        $broken | select file line-start line-end problems | emit
        lib fail "broken comments block the removal: fix them or add --skip-broken"
    }

    # The plan: per file, the comments to remove (as whole lines) and the lines left.
    let doomed = $items | where ($it.problems | is-empty) | lib only-meta $meta
    if ($doomed | is-empty) {
        print -e "No code-review comments to remove."
        return
    }
    let plan = $doomed | get file | uniq | each {|file|
        let comments = $doomed | where file == $file
        let gone = $comments | each {|it| seq $it.line-start $it.line-end } | flatten
        let left = lib lines-of $file | enumerate | where ($it.index + 1) not-in $gone | get item
        # What stays must read the same: removal may not re-pair the markers left.
        let kept = $items | where file == $file and line-start not-in ($comments | get line-start) | reading
        let after = lib scan-lines $file $left $markers | reading
        {file: $file, comments: $comments, left: $left, intact: ($kept == $after)}
    }
    let repaired = $plan | where not $it.intact | get file
    if ($repaired | is-not-empty) {
        lib fail $"removal would re-pair the broken markers left in: ($repaired | str join ', '). Fix them first"
    }

    if not $apply {
        $doomed | select file line-start line-end comment | emit
        print -e "Observed only, nothing changed. Add --apply to remove these comments."
        return
    }
    for file in $plan {
        $file.left | str join "\n" | save --force --raw $file.file
        print -e $"removed ($file.comments | length) from ($file.file)"
    }
}

# How items read wherever they are: their text and kinds of problems.
def reading []: list<record> -> list<record> {
    $in | each {|it| {raw: $it.raw, problems: ($it.problems | each { split row ":" | first })} }
}
