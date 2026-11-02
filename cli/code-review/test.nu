use lib.nu
use ../emit.nu

# Test code-review end to end in a throwaway repository.
#
# Copies cli/ and the justfile into a temporary git repository with a submodule
# and hides them from the scans, so only the fixtures count. Writes the fixtures
# with the configured markers (so no marker is written here), runs the
# `just <action> code-review` commands there and compares their output with
# what the rules expect. Exits with 1 when a case fails.
@example "run the tests" { just test code-review }
def main [] {
    let m = lib markers
    let sandbox = mktemp --directory --tmpdir nui-code-review.XXXXXX
    cp --recursive ($lib.root | path join cli) $sandbox
    cp ($lib.root | path join justfile) $sandbox
    cd $sandbox
    fixtures $m $"($sandbox)-sub"
    let results = cases $m | each {|case|
        let actual = try { do $case.run } catch {|error| $"error: ($error.msg)" }
        let ok = $actual == $case.expected
        {case: $case.name, ok: $ok, expected: (if $ok { null } else { $case.expected | to nuon }), actual: (if $ok { null } else { $actual | to nuon })}
    }
    cd $lib.root
    rm --recursive --force $sandbox $"($sandbox)-sub"
    $results | emit
    if ($results | any { not $in.ok }) { exit 1 }
}

# The fixtures: files written with the markers `m`, and a submodule (cloned from `origin`) holding one more.
def fixtures [m: record, origin: string] {
    let s = $m.marker-start
    let e = $m.marker-end
    let x = $m.marker-meta
    let w = $x | str length -g
    ^git init --quiet
    # The copied tools are no fixtures: comments in them must not count.
    let exclude = ^git rev-parse --git-path info/exclude
    mkdir ($exclude | path dirname)
    "/cli/\n/justfile\n" | save --append $exclude
    # The spec's two examples, as they were given.
    [
        $"          /* ($s)" "hello" $"(pad 54)($x)" $"(pad (54 + $w))value=67" $"(pad (54 + $w))examples=true" "" ""
        $"              ($e)                     */" ""
        $"// ($s)" "world" "" "" $x $"(pad $w)value=68" $"(pad $w)example=true" $"// ($e)" "int main() {}" ""
    ] | str join "\n" | save examples.c
    ["let x = 1;" $"// ($s) fix this ($x) prio = 1 ($e)" "" "fn main() {}" ""] | str join "\n" | save single.rs
    [
        $"($s) unclosed" $"($s) fine" $e $"stray ($e)" $"($s) a ($e) ($s) b ($e)"
        $"($s) bad meta" $x $"(pad $w)x = = 1" $e $"($s) never closed" ""
    ] | str join "\n" | save broken.txt
    'def main [] { if ($in | str contains "fix") { print -e "mentions fix"; exit 1 } }' | save rule.nu
    mkdir $origin
    "kept\n" | save ($origin | path join kept.txt)
    ^git -C $origin init --quiet
    ^git -C $origin add .
    ^git -C $origin -c user.name=test -c user.email=test@localhost commit --quiet --message init
    ^git -c protocol.file.allow=always submodule --quiet add $origin sub
    [$"// ($s) in sub" $"// ($e)" "code" ""] | str join "\n" | save sub/a.go
}

# The cases: a name, how to get the actual value, and the expected one.
def cases [m: record]: nothing -> list<record> {
    let s = $m.marker-start
    let e = $m.marker-end
    let longest = $"// ($s) fix this ($m.marker-meta) prio = 1 ($e)" | str length -g
    [
        {
            name: "retrieve: the spec's two examples"
            run: { just retrieve code-review examples.c | from json | select line-start line-end line-next-nonempty comment meta }
            expected: [
                {line-start: 1, line-end: 8, line-next-nonempty: 10, comment: "hello", meta: {value: 67, examples: true}}
                {line-start: 10, line-end: 17, line-next-nonempty: 18, comment: "world", meta: {value: 68, example: true}}
            ]
        }
        {
            name: "retrieve: a single-line comment with meta"
            run: { just retrieve code-review single.rs | from json | select line-start line-end line-next-nonempty comment meta }
            expected: [{line-start: 2, line-end: 2, line-next-nonempty: 4, comment: "fix this", meta: {prio: 1}}]
        }
        {
            name: "retrieve: --meta keeps comments including it"
            run: { just retrieve code-review --meta='example = true' | from json | get comment }
            expected: ["world"]
        }
        {
            name: "retrieve: submodules are scanned and paths narrow"
            run: { just retrieve code-review sub | from json | get file }
            expected: ["sub/a.go"]
        }
        {
            name: "check: broken markers and meta, exit 1"
            run: { just check code-review broken.txt | complete | {exit: $in.exit_code, broken: ($in.stdout | from json | each { kinds })} }
            expected: {exit: 1, broken: [
                {line-start: 1, problems: [unclosed]}
                {line-start: 4, problems: [unopened]}
                {line-start: 5, problems: [shared-line]}
                {line-start: 5, problems: [shared-line]}
                {line-start: 6, problems: ["meta: line 8"]}
                {line-start: 10, problems: [unclosed]}
            ]}
        }
        {
            name: "check: --max-lines"
            run: { just check code-review examples.c --max-lines=7 | complete | get stdout | from json | each { kinds } }
            expected: [{line-start: 1, problems: [too-many-lines]} {line-start: 10, problems: [too-many-lines]}]
        }
        {
            name: "check: --max-line"
            run: { just check code-review single.rs $"--max-line=($longest - 1)" | complete | get stdout | from json | each { kinds } }
            expected: [{line-start: 2, problems: [line-too-long]}]
        }
        {
            name: "check: --predicate"
            run: { just check code-review single.rs --predicate=rule.nu | complete | get stdout | from json | get problems }
            expected: [["predicate: mentions fix"]]
        }
        {
            name: "status: counts"
            run: { just status code-review | from json | select comments broken files }
            expected: {comments: 5, broken: 6, files: 4}
        }
        {
            name: "remove: broken comments block"
            run: { just remove code-review --apply | complete | get exit_code }
            expected: 1
        }
        {
            name: "remove: --skip-broken may not re-pair broken markers"
            run: { just remove code-review broken.txt --skip-broken --apply | complete | get exit_code }
            expected: 1
        }
        {
            name: "remove: whole lines go, the rest stays"
            run: { just remove code-review single.rs --apply | complete; open --raw single.rs | decode utf-8 }
            expected: "let x = 1;\n\nfn main() {}\n"
        }
        {
            name: "config-set: comments with old markers block"
            run: { just config-set code-review $"marker-start=x($s)" | complete | get exit_code }
            expected: 1
        }
        {
            name: "config-set: rewritten comments read the same"
            run: {
                let before = just retrieve code-review | from json | select file line-start comment meta
                just config-set code-review $"marker-start=x($s)" $"marker-end=x($e)" --replace-old-markers --apply | complete
                let after = just retrieve code-review | from json | select file line-start comment meta
                {same: ($before == $after), start: (open cli/code-review/config.toml | get marker-start)}
            }
            expected: {same: true, start: $"x($s)"}
        }
    ]
}

# A broken item reduced to its line and kinds of problems; meta keeps its line: "meta: line <n>".
def kinds []: record -> record {
    let problems = $in.problems | each {|problem|
        let parts = $problem | split row ": "
        if ($parts | first) == "meta" { $parts | first 2 | str join ": " } else { $parts | first }
    }
    {line-start: $in.line-start, problems: $problems}
}

# `n` spaces.
def pad [n: int]: nothing -> string {
    "" | fill --width $n
}
