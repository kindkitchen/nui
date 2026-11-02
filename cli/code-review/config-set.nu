use lib.nu
use ../emit.nu

# Set code-review markers in config.toml, keeping the codebase consistent.
#
# Blocks, listing addresses, while comments use old markers that change or the
# new markers already occur in the codebase; the flags resolve these at once.
# Only observes by default; --apply writes the config and any rewritten markers.
@example "observe a change" { just config-set code-review marker-start=<new-start> marker-end=<new-end> }
@example "rewrite existing comments too" { just config-set code-review marker-start=<new-start> --replace-old-markers --apply }
@example "quote values your shell would evaluate" { just config-set code-review 'marker-meta=(<new-meta>):' }
def main [
    ...values: string           # New markers as key=value, keys: marker-start, marker-end, marker-meta.
    --replace-old-markers       # Rewrite the old markers of existing comments to the new ones.
    --ignore-old-markers        # Leave existing comments as they are: they stop being comments.
    --ignore-already-matches    # Accept new markers that already occur in the codebase.
    --apply                     # Write instead of only observing.
    --marker-start: string      # Current start marker, instead of the configured one.
    --marker-end: string        # Current end marker, instead of the configured one.
    --marker-meta: string       # Current meta marker, instead of the configured one.
] {
    cd $lib.root
    if $replace_old_markers and $ignore_old_markers { lib fail "--replace-old-markers and --ignore-old-markers exclude each other" }
    let old = lib markers {marker-start: $marker_start, marker-end: $marker_end, marker-meta: $marker_meta}
    let new = $old | merge (pairs $values)
    lib validate $new
    let changed = $lib.keys | where {|key| ($old | get $key) != ($new | get $key) }
    if ($changed | is-empty) {
        print -e "Nothing to change."
        return
    }

    # Blockers are checked before any write, so observing shows them too.
    # Comments using changing markers: all of them, or only the ones with meta if just that changes.
    let affected = lib scan $old | where {|it| $changed != [marker-meta] or $it.at.meta != null }
    let matches = $changed | each {|key| found ($new | get $key) | insert marker $key } | flatten
    let edits = if $replace_old_markers { rewrite $affected $old $new $changed } else { [] }
    let blockers = [
        ...(if $replace_old_markers or $ignore_old_markers { [] } else {
            $affected | each {|it| {file: $it.file, line: $it.line-start, problem: "uses old markers: add --replace-old-markers or --ignore-old-markers"} }
        })
        ...(if $ignore_already_matches { [] } else {
            $matches | each {|it| {file: $it.file, line: $it.line, problem: $"new ($it.marker) already occurs: add --ignore-already-matches"} }
        })
        ...($edits | where not $it.intact | each {|it| {file: $it.file, line: null, problem: "rewriting the markers would change how its comments read"} })
    ]
    if ($blockers | is-not-empty) {
        $blockers | emit
        lib fail "resolve these first"
    }

    # The plan: the config change, then every rewritten marker or comment left as is.
    let plan = $changed
        | each {|key| {file: ($lib.config | path relative-to $lib.root), line: null, change: $"($key): ($old | get $key) -> ($new | get $key)"} }
        | append ($edits | each {|it| $it.spots | each {|spot| {file: $it.file, line: $spot.line, change: $"($spot.from) -> ($spot.to)"} } } | flatten)
        | append (if $ignore_old_markers { $affected | each {|it| {file: $it.file, line: $it.line-start, change: "keeps the old markers as plain text"} } } else { [] })
    if not $apply {
        $plan | emit
        print -e "Observed only, nothing changed. Add --apply to make these changes."
        return
    }
    for edit in $edits {
        $edit.text | save --force --raw $edit.file
        print -e $"markers rewritten in ($edit.file): ($edit.spots | length)"
    }
    lib save-config $new
    print -e $"set ($changed | str join ', ') in ($lib.config | path relative-to $lib.root)"
}

# New markers from key=value arguments.
def pairs [values: list<string>]: nothing -> record {
    let bad = $values | where {|value| not ($value | str contains "=") or ($value | split row --number 2 "=" | first) not-in $lib.keys }
    if ($bad | is-not-empty) { lib fail $"expected key=value with a key of ($lib.keys | str join ', '), got: ($bad | str join ' ')" }
    let pairs = $values | each { split row --number 2 "=" }
    if ($pairs | each { first } | uniq | length) != ($pairs | length) { lib fail "each key may be given once" }
    $pairs | reduce --fold {} {|pair, acc| $acc | insert ($pair | first) ($pair | last) }
}

# Where `text` already occurs in the codebase, as {file, line}.
def found [text: string]: nothing -> list<record> {
    lib files [$text] | each {|file|
        lib lines-of $file | enumerate | where ($it.item | str contains $text) | each {|it| {file: $file, line: ($it.index + 1)} }
    } | flatten
}

# Per file: its text with the changing markers of `affected` rewritten, the rewritten spots,
# and whether its comments still read the same with the new markers.
def rewrite [affected: list<record>, old: record, new: record, changed: list<string>]: nothing -> list<record> {
    let spots = $affected | each {|it|
        [[key at]; [marker-start $it.at.start] [marker-end $it.at.end] [marker-meta $it.at.meta]]
            | where {|spot| $spot.at != null and $spot.key in $changed }
            | each {|spot| {file: $it.file, line: $spot.at.line, col: $spot.at.col, from: ($old | get $spot.key), to: ($new | get $spot.key)} }
    } | flatten
    $spots | get file | uniq | each {|file|
        let here = $spots | where file == $file
        let lines = lib lines-of $file
        # Right to left, so earlier columns stay valid.
        let rewritten = $lines | enumerate | each {|line|
            $here | where line == ($line.index + 1) | sort-by col --reverse | reduce --fold $line.item {|spot, text|
                ($text | str substring -g 0..<$spot.col) + $spot.to + ($text | str substring -g ($spot.col + ($spot.from | str length -g))..)
            }
        }
        let before = lib scan-lines $file $lines $old | meaning
        let after = lib scan-lines $file $rewritten $new | meaning
        {file: $file, spots: ($here | sort-by line col), text: ($rewritten | str join "\n"), intact: ($before == $after)}
    }
}

# What items mean, markers aside: their lines, comment, meta and kinds of problems.
def meaning []: list<record> -> list<record> {
    $in | each {|it| {
        line-start: $it.line-start, line-end: $it.line-end, comment: $it.comment, meta: $it.meta
        problems: ($it.problems | each { split row ":" | first })
    } }
}
