# Shortcuts for boring commands: devx/<command>.nu, free of the cli/ conventions.
#
# Run `nu devx.nu <command> [...args]`, or `use devx.nu` once and then `devx <command> [...args]`.
# Commands run from the repo root, like just recipes.

const root = path self .

# Run devx/<command>.nu with the args; without a command, list the commands.
export def --wrapped main [
    command?: string@commands  # A script in devx/, without .nu.
    ...args                    # Arguments of the script, passed untouched.
] {
    if $command in [null "--help" "-h"] { return (commands) }
    cd $root
    ^$nu.current-exe $"devx/($command).nu" ...$args
}

# The commands: scripts in devx/.
def commands []: nothing -> list<string> {
    cd $root
    glob devx/*.nu | each { path parse | get stem } | sort
}
