# Public gateway to the cli/ hub: `just <action> <target> [...args]`.
# cli/main.nu runs cli/<target>/<action>.nu; omit the target to list them,
# or run `just <target>` to list the actions of a target.
# Recipes are nushell scripts, so arguments reach the actions untouched.

set positional-arguments
set script-interpreter := ["nu"]

[private]
[script]
default:
    just --list

# Check a target.
[group('actions')]
[script]
check target="" *args:
    def --wrapped main [...args] { nu cli/main.nu check ...$args }

# Set the config of a target.
[group('actions')]
[script]
config-set target="" *args:
    def --wrapped main [...args] { nu cli/main.nu config-set ...$args }

# Create a target.
[group('actions')]
[script]
create target="" *args:
    def --wrapped main [...args] { nu cli/main.nu create ...$args }

# Remove a target.
[group('actions')]
[script]
remove target="" *args:
    def --wrapped main [...args] { nu cli/main.nu remove ...$args }

# Retrieve a target.
[group('actions')]
[script]
retrieve target="" *args:
    def --wrapped main [...args] { nu cli/main.nu retrieve ...$args }

# Show the status of a target.
[group('actions')]
[script]
status target="" *args:
    def --wrapped main [...args] { nu cli/main.nu status ...$args }

# Test a target.
[group('actions')]
[script]
test target="" *args:
    def --wrapped main [...args] { nu cli/main.nu test ...$args }

# List the actions of code-review.
[group('targets')]
[script]
code-review *args:
    def --wrapped main [...args] { nu cli/main.nu code-review ...$args }

# List the actions of submodule.
[group('targets')]
[script]
submodule *args:
    def --wrapped main [...args] { nu cli/main.nu submodule ...$args }
