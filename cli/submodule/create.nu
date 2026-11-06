use ../emit.nu

# Every sub-project history starts at this tag.
const start = "01-01-init"
# The repository root: this script lives in cli/submodule/.
const root = path self ../..

# Create a sub-project: a submodule pointing to any remote.
#
# Starts a repository in ./<name> from the 01-01-init tag of this one, taking
# only that tag, on the <name>/main branch, and registers it as a submodule
# tracking that branch, with --url as its remote: e.g. its own repository,
# or this one. The remote's branches under <name> must be free; a remote
# that can't be reached yet is only warned about.
# Only observes by default; --apply makes the changes. They are staged,
# not committed; nothing is pushed.
@example "observe what would be affected" { just create submodule --name=example --url=https://github.com/kindkitchen/example.git }
@example "make the changes" { just create submodule --name=example --url=https://github.com/kindkitchen/example.git --apply }
@example "a branch in the remote of this repository" { just create submodule --name=example --url=https://github.com/kindkitchen/nui.git --apply }
def main [
    --name: string  # Sub-project name: its folder and branch/tag prefix.
    --url: string   # Remote of the submodule: any URL or path git can reach.
    --apply         # Make the changes instead of only showing them.
] {
    cd $root

    # Blockers are checked before any write, so observing shows them too.
    if $name == null { fail "--name is required" }
    if $url == null { fail "--url is required" }
    let branch = $"($name)/main"
    if ($name | str contains "/") or (git check-ref-format --branch $branch | complete).exit_code != 0 {
        fail $"invalid name: ($name)"
    }
    if ($name | path exists) { fail $"./($name) already exists" }
    let gitdir = git rev-parse --git-path $"modules/($name)"
    if ($gitdir | path exists) { fail $"($gitdir) already exists, left by a removed submodule" }
    if (git rev-parse --verify --quiet $"refs/tags/($start)" | complete).exit_code != 0 { fail $"tag ($start) not found" }
    # A remote that isn't created yet can't be checked: warn instead of blocking.
    let remote = with-env {GIT_TERMINAL_PROMPT: "0"} { git ls-remote $url $"refs/heads/($name)" $"refs/heads/($name)/*" | complete }
    if $remote.exit_code != 0 {
        print -e $"Warning: can't reach ($url), its branches are unchecked: ($remote.stderr | str trim | lines | last)"
    }
    let taken = $remote.stdout | lines | parse "{sha}\t{ref}" | get ref | str replace "refs/heads/" ""
    if ($taken | is-not-empty) { fail $"branch namespace ($name) is taken in ($url) by: ($taken | str join ', ')" }

    # The plan: what each step affects and the exact command it runs.
    let steps = [
        [affects command];
        [$"./($name)" [git init $name]]
        [$"./($name): tag ($start)" [git -C $name fetch .. tag $start]]
        [$"./($name): branch ($branch)" [git -C $name switch --create $branch $start]]
        [$"./($name): origin" [git -C $name remote add origin $url]]
        [".gitmodules, .git/config, index" [git submodule add --branch $branch $url $name]]
        [$gitdir [git submodule absorbgitdirs $name]]
    ]

    if not $apply {
        $steps | update command { str join " " } | emit
        print -e "Observed only, nothing changed. Add --apply to make these changes."
        return
    }
    for step in $steps {
        let result = run-external ...$step.command | complete
        if $result.exit_code != 0 {
            fail $"failed: ($step.command | str join ' ')\n($result.stderr | str trim)"
        }
        print -e $"applied: ($step.affects)"
    }
    print -e $"Staged, not committed. Publish the branch: git -C ($name) push -u origin ($branch)"
}

# Abort with a message.
def fail [message: string] {
    error make --unspanned {msg: $message}
}
