use ../emit.nu

# Every sub-project history starts at this tag.
const start = "01-01-init"
# The repository root: this script lives in cli/submodule/.
const root = path self ../..

# Create a sub-project: a submodule of this same repository.
#
# Clones this repository into ./<name> at the 01-01-init tag, starts the
# <name>/main branch there and registers it as a submodule tracking it.
# Only observes by default; --apply makes the changes. They are staged,
# not committed; nothing is pushed.
@example "observe what would be affected" { just create submodule --name=example }
@example "make the changes" { just create submodule --name=example --apply }
def main [
    --name: string  # Sub-project name: its folder and branch/tag prefix.
    --apply         # Make the changes instead of only showing them.
] {
    cd $root

    # Blockers are checked before any write, so observing shows them too.
    if $name == null { fail "--name is required" }
    let branch = $"($name)/main"
    if ($name | str contains "/") or (git check-ref-format --branch $branch | complete).exit_code != 0 {
        fail $"invalid name: ($name)"
    }
    if ($name | path exists) { fail $"./($name) already exists" }
    let taken = git for-each-ref '--format=%(refname:short)' $"refs/heads/($name)" $"refs/remotes/origin/($name)" | lines
    if ($taken | is-not-empty) { fail $"branch namespace ($name) is taken by: ($taken | str join ', ')" }
    let gitdir = git rev-parse --git-path $"modules/($name)"
    if ($gitdir | path exists) { fail $"($gitdir) already exists, left by a removed submodule" }
    if (git rev-parse --verify --quiet $"refs/tags/($start)" | complete).exit_code != 0 { fail $"tag ($start) not found" }
    let origin = git remote get-url origin | complete
    if $origin.exit_code != 0 { fail "no origin remote to point the submodule to" }
    let url = $origin.stdout | str trim

    # The plan: what each step affects and the exact command it runs.
    let steps = [
        [affects command];
        [$"./($name)" [git clone --branch $start . $name]]
        [$"./($name): branch ($branch)" [git -C $name switch --create $branch]]
        [$"./($name): origin" [git -C $name remote set-url origin $url]]
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
