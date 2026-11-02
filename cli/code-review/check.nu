use lib.nu
use ../emit.nu

# Check code-review comments: list the broken ones with their addresses.
#
# Always broken: unclosed, unopened, shared-line, and meta that isn't TOML.
# --max-lines, --max-line and --predicate make the check stricter.
# Exits with 1 when anything is broken.
@example "structure and meta" { just check code-review }
@example "stricter" { just check code-review --max-lines=10 --max-line=50 }
@example "own rule" { just check code-review --predicate=path/to/rule.nu }
def main [
    ...paths: string        # Where to look, relative to the root; everywhere by default.
    --max-lines: int        # A comment longer than this many lines is broken.
    --max-line: int         # A comment with a line longer than this many characters is broken.
    --predicate: path       # Nushell script reading a comment's raw text from stdin: printing `false` or failing marks it broken, its stderr says why.
    --meta: string          # Keep comments whose meta includes this TOML, e.g. 'value = 67'.
    --marker-start: string  # Use this start marker instead of the configured one.
    --marker-end: string    # Use this end marker instead of the configured one.
    --marker-meta: string   # Use this meta marker instead of the configured one.
] {
    cd $lib.root
    let markers = lib markers {marker-start: $marker_start, marker-end: $marker_end, marker-meta: $marker_meta}
    let broken = lib scan $markers $paths
        | lib only-meta $meta
        | each {|it| $it | update problems { append (strict $it $max_lines $max_line $predicate) } }
        | where ($it.problems | is-not-empty)
        | select file line-start line-end problems
    if ($broken | is-empty) {
        print -e "No broken code-review comments."
        return
    }
    $broken | emit
    exit 1
}

# Problems of a closed comment under the limits and the predicate; none for broken markers.
def strict [it: record, max_lines?: int, max_line?: int, predicate?: string]: nothing -> list<string> {
    if $it.at.start == null or $it.at.end == null { return [] }
    let count = $it.line-end - $it.line-start + 1
    let longest = $it.raw | lines | each { str length -g } | math max
    [
        (if $max_lines != null and $count > $max_lines { $"too-many-lines: ($count) > ($max_lines)" })
        (if $max_line != null and $longest > $max_line { $"line-too-long: ($longest) > ($max_line)" })
        (if $predicate != null { judge $predicate $it.raw })
    ] | compact
}

# Why the predicate rejects `raw`, or null when it accepts it.
def judge [predicate: string, raw: string] {
    let verdict = $raw | ^$nu.current-exe --stdin $predicate | complete
    if $verdict.exit_code == 0 and ($verdict.stdout | str trim) != "false" { return null }
    let said = $verdict.stderr | lines | str trim | where $it != ""
    # A nushell error says why on its `x <message>` lines.
    let reason = if ($said | any { str starts-with "Error: nu::" }) {
        $said | where { $in =~ '^[x×] ' } | each { str substring -g 2.. }
    } else { $said } | str join " "
    if ($reason | is-empty) { "predicate" } else { $"predicate: ($reason)" }
}
