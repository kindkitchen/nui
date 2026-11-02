use lib.nu
use ../emit.nu

# Summarize code-review comments: how many, where, and their meta values.
#
# meta counts the comments per key = value: nested tables give dotted keys,
# values are shown as NUON. Broken comments are only counted.
@example "everything" { just status code-review }
@example "comments having value = 67 in meta" { just status code-review --meta='value = 67' }
def main [
    ...paths: string        # Where to look, relative to the root; everywhere by default.
    --meta: string          # Keep comments whose meta includes this TOML, e.g. 'value = 67'.
    --marker-start: string  # Use this start marker instead of the configured one.
    --marker-end: string    # Use this end marker instead of the configured one.
    --marker-meta: string   # Use this meta marker instead of the configured one.
] {
    cd $lib.root
    let markers = lib markers {marker-start: $marker_start, marker-end: $marker_end, marker-meta: $marker_meta}
    let items = lib scan $markers $paths | lib only-meta $meta
    let comments = $items | where ($it.problems | is-empty)
    {
        comments: ($comments | length)
        broken: (($items | length) - ($comments | length))
        files: ($comments | get file | uniq | length)
        meta: ($comments | each {|it| $it.meta | pairs } | flatten | uniq --count
            | each {|it| {key: $it.value.key, value: $it.value.value, comments: $it.count} }
            | sort-by key value)
    } | emit
}

# A record as key = value pairs: nested records give dotted keys, values become NUON.
def pairs [prefix: string = ""]: record -> list<record> {
    $in | transpose key value | each {|it|
        let key = if $prefix == "" { $it.key } else { $"($prefix).($it.key)" }
        if ($it.value | describe --detailed | get type) == "record" {
            $it.value | pairs $key
        } else {
            [{key: $key, value: ($it.value | to nuon)}]
        }
    } | flatten
}
