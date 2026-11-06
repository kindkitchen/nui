use ../emit.nu

# The repository root: this script lives in cli/submodule/.
const root = path self ../..

# Sync the submodules with their remotes: fetch, then pull where it's safe.
#
# Each submodule fetches its remote (`git fetch`), then pulls: fast-forwards
# its branch to the upstream (`git merge --ff-only @{upstream}`). A pull that
# isn't safe is skipped with the reason: on a detached HEAD, without an
# upstream, or diverged from it; git refuses one over conflicting local
# changes. A submodule failing doesn't stop the others.
# Only observes by default: shows what would run, without fetching.
# --apply fetches and pulls. Nothing is staged in this repository.
@example "observe what would run" { just sync submodule }
@example "fetch and pull" { just sync submodule --apply }
def main [
    --apply  # Fetch and pull instead of only showing what would run.
] {
    cd $root
    submodules | each {|path| if $apply { sync $path } else { plan $path } } | emit
    if not $apply { print -e "Observed only, nothing changed. Add --apply to fetch and pull." }
}

# What syncing a submodule would do: its branch and upstream, and each step
# ready to run or skipped with the reason.
def plan [path: string]: nothing -> record {
    let row = {submodule: $path, branch: null, upstream: null, fetch: "ready", pull: "ready"}
    if not ($path | path join .git | path exists) {
        return ($row | merge {fetch: "skipped: not initialized", pull: "skipped: not initialized"})
    }
    let branch = git -C $path symbolic-ref --quiet --short HEAD | complete
    if $branch.exit_code != 0 { return ($row | merge {pull: "skipped: detached HEAD"}) }
    let branch = $branch.stdout | str trim
    let upstream = git -C $path for-each-ref '--format=%(upstream:short)' $"refs/heads/($branch)" | str trim
    if $upstream == "" { return ($row | merge {branch: $branch, pull: "skipped: no upstream"}) }
    $row | merge {branch: $branch, upstream: $upstream}
}

# Run the plan of a submodule: each ready step gets its result.
def sync [path: string]: nothing -> record {
    let row = plan $path
    if $row.fetch != "ready" { return $row }
    let fetched = git -C $path fetch | complete
    if $fetched.exit_code != 0 { return ($row | merge {fetch: $"failed: (reason $fetched)", pull: "skipped: fetch failed"}) }
    $row | merge {fetch: "done", pull: (if $row.pull == "ready" { pull $path } else { $row.pull })}
}

# Fast-forward the checked-out branch to its upstream, or say why not.
def pull [path: string]: nothing -> string {
    if (git -C $path rev-parse --verify --quiet '@{upstream}' | complete).exit_code != 0 { return "skipped: upstream gone" }
    let count = git -C $path rev-list --left-right --count 'HEAD...@{upstream}' | parse "{ahead}\t{behind}" | into int ahead behind | first
    if $count.behind == 0 { return (if $count.ahead == 0 { "up to date" } else { $"up to date, ($count.ahead) ahead" }) }
    if $count.ahead > 0 { return $"skipped: diverged, ($count.ahead) ahead and ($count.behind) behind" }
    let before = git -C $path rev-parse --short HEAD | str trim
    let merged = git -C $path merge --ff-only '@{upstream}' | complete
    if $merged.exit_code != 0 { return $"failed: (reason $merged)" }
    $"done: ($before)..(git -C $path rev-parse --short HEAD | str trim)"
}

# Git's message of a failed command on one line: its first line and the list under it.
def reason [result: record]: nothing -> string {
    let lines = $result.stderr | lines | where $it != ""
    let list = $lines | skip 1 | take while {|line| $line | str starts-with "\t" } | str trim
    $lines | first 1 | str replace --regex '^(error|fatal): ' '' | append $list | str join " "
}

# Paths of the submodules, as .gitmodules lists them.
def submodules []: nothing -> list<string> {
    git config --file .gitmodules --get-regexp '\.path$' | complete | get stdout | lines
        | each { split row --number 2 " " | last }
}
