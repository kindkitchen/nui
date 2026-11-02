use emit.nu

# The cli folder: features are its folders, actions their scripts.
const cli = path self .
# The gateway: its recipes are the actions and the targets.
const justfile = path self ../justfile

# Route `just <action> <target> [...args]` to cli/<target>/<action>.nu.
#
# Without a target, lists the targets implementing the action.
# `just <target>` lists the actions of the target instead; a word after
# it is a misplaced action, warned about.
@example "list the targets of an action" { just check }
@example "list the actions of a target" { just code-review }
@example "explain an action of a target" { just check code-review --help }
def --wrapped main [
    action?: string  # What to do: check, create, ...; or a target, to list its actions.
    target?: string  # What to do it with: a feature folder in cli/.
    ...args          # Arguments of the action script, passed untouched (untyped, so never evaluated).
] {
    # A wrapped command gets --help as a word: optional, `action` takes it as one.
    if $action in [null "" "--help" "-h"] {
        print (help main)
        return
    }
    # `just <target>` arrives with the target first.
    if ($cli | path join $action | path type) == dir {
        actions-of $action ([$target] | append $args | compact)
        return
    }
    if $target in [null "" "--help" "-h"] {
        let targets = glob ($cli | path join "*" $"($action).nu") | each {|script|
            {target: ($script | path dirname | path basename), about: (about $script)}
        }
        if ($targets | is-empty) { error make --unspanned {msg: $"no target implements ($action)"} }
        $targets | sort-by target | emit
        print -e $"`just ($action) <target> --help` explains one."
        return
    }
    let script = $cli | path join $target $"($action).nu"
    if not ($script | path exists) { error make --unspanned {msg: $"($target) has no ($action): cli/($target)/($action).nu is missing"} }
    ^$nu.current-exe $script ...$args
}

# List the actions of a target as `just <action> <target>` commands; any `extra` word is a misplaced action.
def actions-of [target: string, extra: list] {
    let actions = actions | where {|action| $cli | path join $target $"($action).nu" | path exists }
    $actions | each {|action| {command: $"just ($action) ($target)", about: (about ($cli | path join $target $"($action).nu"))} } | emit
    print -e $"`just <action> ($target) --help` explains one."
    let extra = $extra | where $it not-in ["" "--help" "-h"]
    if ($extra | is-empty) { return }
    let hint = if ($extra | first) in $actions { $"just ($extra | first) ($target)" } else { $"just <action> ($target)" }
    print -e $"Warning: ($target) is a target, not an action: it goes second, `($hint)`."
    exit 1
}

# Actions: the justfile's recipes that aren't targets.
def actions []: nothing -> list<string> {
    ^just --justfile $justfile --summary | str trim | split row " " | where {|name| ($cli | path join $name | path type) != dir }
}

# The first line of a script's help.
def about [script: string]: nothing -> string {
    ^$nu.current-exe $script --help | lines | first
}
