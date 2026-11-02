# Code-review comments: config, scanning, parsing and filtering shared by the actions.
#
# Lines are 1-based. Columns are 0-based and count characters, not bytes.

# The repository root: this module lives in cli/code-review/.
export const root = path self ../..
# The markers config. Never scanned, as it holds the markers literally.
export const config = path self config.toml
# Marker keys: in config.toml, as config-set values and as override flags.
export const keys = [marker-start marker-end marker-meta]

# Abort with a message.
export def fail [message: string] {
    error make --unspanned {msg: $message}
}

# Markers from config.toml, overridden by the non-null values of `overrides`.
export def markers [overrides: record = {}]: nothing -> record {
    let markers = open $config | merge ($overrides | compact) | select --optional ...$keys
    validate $markers
    $markers
}

# Write the markers to config.toml, keeping its leading comment lines.
export def save-config [markers: record] {
    let header = lines-of $config | take while { str starts-with "#" }
    $header | append ($markers | select ...$keys | to toml | str trim | lines) | append "" | str join "\n" | save --force --raw $config
}

# Fail unless the markers are non-empty single-line strings, none containing another.
export def validate [markers: record] {
    for key in $keys {
        let value = $markers | get --optional $key
        if ($value | describe) != "string" or ($value | is-empty) or ($value =~ "[\r\n]") {
            fail $"($key) must be a non-empty single-line string"
        }
    }
    for a in $keys {
        for b in $keys {
            if $a != $b and ($markers | get $a | str contains ($markers | get $b)) {
                fail $"($a) contains ($b): markers must differ and none may contain another"
            }
        }
    }
}

# Comments and broken markers in the files under `paths`, in order of appearance.
export def scan [markers: record, paths: list<string> = []]: nothing -> list<record> {
    files [$markers.marker-start $markers.marker-end] $paths | each {|file| scan-file $file $markers } | flatten
}

# Files containing any of `needles` under `paths` (relative to the root; all when empty).
#
# Covers the root repository and its initialized submodules: tracked files and
# untracked ones that are not ignored. Binary files and the config are skipped.
export def files [needles: list<string>, paths: list<string> = []]: nothing -> list<string> {
    let subs = submodules
    let paths = relative $paths
    let patterns = $needles | each {|needle| [-e $needle] } | flatten
    [""] | append $subs | each {|repo|
        let specs = pathspecs $repo $paths $subs
        if $specs == null { return [] }
        let found = ^git --literal-pathspecs -C (if $repo == "" { "." } else { $repo }) grep -z -l -I -F --untracked ...$patterns -- ...$specs | complete
        if $found.exit_code > 1 { fail $"git grep failed in ./($repo): ($found.stderr | str trim)" }
        $found.stdout | split row (char nul) | where $it != "" | each {|file| if $repo == "" { $file } else { $"($repo)/($file)" } }
    } | flatten | where $it != ($config | path relative-to $root)
}

# Lines of a file's text, without line terminators. A final newline leaves an empty last line.
export def lines-of [file: string]: nothing -> list<string> {
    open --raw $file | decode utf-8 | split row "\n"
}

# Comments and broken markers of a file, in order of appearance.
export def scan-file [file: string, markers: record]: nothing -> list<record> {
    scan-lines $file (lines-of $file) $markers
}

# Comments and broken markers of a file's lines (as from `lines-of`), in order of appearance.
export def scan-lines [file: string, lines: list<string>, markers: record]: nothing -> list<record> {
    let lines = $lines | each { str trim --right --char "\r" }
    mut items = []
    mut opened: any = null
    for index in 0..<($lines | length) {
        for event in (events ($lines | get $index) $markers) {
            let at = {line: ($index + 1), col: $event.col}
            if $event.marker == "start" {
                if $opened != null { $items = $items | append (unclosed $file $lines $opened) }
                $opened = $at
            } else if $opened == null {
                $items = $items | append (unopened $file $lines $at)
            } else {
                $items = $items | append (comment $file $lines $opened $at $markers)
                $opened = null
            }
        }
    }
    if $opened != null { $items = $items | append (unclosed $file $lines $opened) }
    $items | flag-shared-lines
}

# Keep items whose meta includes `filter` (TOML); all of them when it's null.
export def only-meta [filter?: string]: list<record> -> list<record> {
    let items = $in
    if $filter == null { return $items }
    let wanted = try { $filter | from toml } catch { fail $"--meta is not valid TOML: ($filter)" }
    $items | where {|it| includes $it.meta $wanted }
}

# Whether `value` includes `wanted`: records key by key, lists element by element, the rest by equality.
def includes [value: any, wanted: any]: nothing -> bool {
    let kind = $wanted | describe --detailed | get type
    if $kind == "record" {
        ($value | describe --detailed | get type) == "record" and ($wanted | columns | all {|key| $key in ($value | columns) and (includes ($value | get $key) ($wanted | get $key)) })
    } else if $kind == "list" {
        ($value | describe --detailed | get type) == "list" and ($wanted | all {|w| $value | any {|v| includes $v $w } })
    } else {
        $value == $wanted
    }
}

# Start and end markers of a line, left to right, as {marker, col}.
def events [line: string, markers: record]: nothing -> list<record> {
    [start end] | each {|marker|
        occurrences $line ($markers | get $"marker-($marker)") | each {|col| {marker: $marker, col: $col} }
    } | flatten | sort-by col
}

# Columns where `text` occurs in `line`, left to right.
def occurrences [line: string, text: string]: nothing -> list<int> {
    if not ($line | str contains $text) { return [] }
    let width = $text | str length -g
    $line | split row $text | drop | reduce --fold [] {|part, cols|
        let from = if ($cols | is-empty) { 0 } else { ($cols | last) + $width }
        $cols | append ($from + ($part | str length -g))
    }
}

# A comment from the start marker at `opened` to the end marker at `closed`.
def comment [file: string, lines: list<string>, opened: record, closed: record, markers: record]: nothing -> record {
    # The comment's text on each of its lines: columns [a, b).
    let parts = $opened.line..$closed.line | each {|n|
        let line = $lines | get ($n - 1)
        let a = if $n == $opened.line { $opened.col + ($markers.marker-start | str length -g) } else { 0 }
        let b = if $n == $closed.line { $closed.col } else { $line | str length -g }
        {line: $n, a: $a, b: $b, text: ($line | between $a $b)}
    }
    let meta_at = $parts | each {|part|
        let col = $part.text | str index-of -g $markers.marker-meta
        if $col >= 0 { {line: $part.line, col: ($part.a + $col)} }
    } | get --optional 0
    let text = $parts
        | where {|part| $meta_at == null or $part.line <= $meta_at.line }
        | each {|part| if $meta_at != null and $part.line == $meta_at.line { $part.text | between 0 ($meta_at.col - $part.a) } else { $part.text } }
        | str join "\n" | str trim
    let meta = if $meta_at == null { {value: {}, problems: []} } else { meta-of $lines $parts $meta_at $markers }
    {
        file: $file
        line-start: $opened.line
        line-end: $closed.line
        line-next-nonempty: (next-nonempty $lines $closed.line)
        comment: $text
        meta: $meta.value
        raw: ($lines | skip ($opened.line - 1) | first ($closed.line - $opened.line + 1) | str join "\n")
        problems: $meta.problems
        at: {start: $opened, end: $closed, meta: $meta_at}
    }
}

# The meta of a comment: TOML right after the meta marker, each next line read from the marker's end column.
def meta-of [lines: list<string>, parts: list<record>, at: record, markers: record]: nothing -> record {
    let col = $at.col + ($markers.marker-meta | str length -g)
    let toml = $parts | where line >= $at.line | each {|part| $lines | get ($part.line - 1) | between ([$col $part.a] | math max) $part.b } | str join "\n"
    try {
        {value: ($toml | from toml), problems: []}
    } catch {|error|
        {value: {}, problems: [$"meta: (toml-error $error $at.line)"]}
    }
}

# A TOML error as "line <n>: <reason>", <n> being the line in the file.
def toml-error [error: record, line: int]: nothing -> string {
    let help = $error.details?.help? | default "" | lines | str trim | where $it != ""
    if ($help | is-empty) { return "invalid TOML" }
    let at = $help | first | parse --regex 'at line (?<n>\d+)' | get --optional 0.n
    if $at == null { $help | last } else { $"line ($line + ($at | into int) - 1): ($help | last)" }
}

# Characters [a, b) of a string; empty when b <= a.
def between [a: int, b: int]: string -> string {
    if $b <= $a { "" } else { $in | str substring -g $a..<$b }
}

# The first non-blank line after `line`, or null.
def next-nonempty [lines: list<string>, line: int] {
    let found = $lines | skip $line | enumerate | where ($it.item | str trim | is-not-empty) | get --optional 0.index
    if $found == null { null } else { $found + $line + 1 }
}

# A start marker with no end marker before the next start or the end of the file.
def unclosed [file: string, lines: list<string>, at: record]: nothing -> record {
    broken $file ($lines | get ($at.line - 1)) $at.line null unclosed {start: $at, end: null, meta: null}
}

# An end marker outside of any comment.
def unopened [file: string, lines: list<string>, at: record]: nothing -> record {
    broken $file ($lines | get ($at.line - 1)) $at.line $at.line unopened {start: null, end: $at, meta: null}
}

# A broken marker as an item: its line is all it has.
def broken [file: string, raw: string, start: int, end: any, problem: string, at: record]: nothing -> record {
    {file: $file, line-start: $start, line-end: $end, line-next-nonempty: null, comment: "", meta: {}, raw: $raw, problems: [$problem], at: $at}
}

# Mark items sharing a line as broken: comments are removed as whole lines.
def flag-shared-lines []: list<record> -> list<record> {
    let items = $in | enumerate
    let shared = $items
        | each {|it| ($it.item.line-start)..($it.item.line-end | default $it.item.line-start) | each {|line| {line: $line, owner: $it.index} } }
        | flatten | group-by line | values | where ($it | length) > 1 | flatten | get owner | uniq
    $items | each {|it| if $it.index in $shared { $it.item | update problems { append shared-line } } else { $it.item } }
}

# Paths relative to the root ("" for the root itself); fails for any outside of it.
def relative [paths: list<string>]: nothing -> list<string> {
    let base = $root | path expand --no-symlink
    let full = $paths | each { path expand --no-symlink }
    let outside = $full | where {|path| $path != $base and not ($path | str starts-with $"($base)/") }
    if ($outside | is-not-empty) { fail $"outside the repository: ($outside | str join ', ')" }
    $full | each { path relative-to $base }
}

# Pathspecs of `paths` inside `repo` ("" is the root): [] for all of it, null for none of it.
def pathspecs [repo: string, paths: list<string>, subs: list<string>] {
    if ($paths | is-empty) { return [] }
    if $repo == "" {
        let own = $paths | where {|path| not ($subs | any {|sub| $path == $sub or ($path | str starts-with $"($sub)/") }) }
        if ($own | is-empty) { null } else { $own | each { if $in == "" { "." } else { $in } } }
    } else if ($paths | any {|path| $path == "" or $path == $repo or ($repo | str starts-with $"($path)/") }) {
        []
    } else {
        let inner = $paths | where { str starts-with $"($repo)/" } | each { str substring -g (($repo | str length -g) + 1).. }
        if ($inner | is-empty) { null } else { $inner }
    }
}

# Paths of the initialized submodules.
def submodules []: nothing -> list<string> {
    ^git config --file .gitmodules --get-regexp '\.path$' | complete | get stdout | lines
        | each { split row --number 2 " " | last }
        | where { $in | path join .git | path exists }
}
