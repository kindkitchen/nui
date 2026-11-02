# Turn the code-review comments into a prompt: remove them, print the prompt and copy it with pbcopy.
#
# Each comment becomes a numbered item: `file:line`, its text and its meta as TOML.
# The line is where the comment was, counted after the removal, so the prompt
# matches the files left. Broken comments block the removal: nothing changes.
def main [] {
    let comments = just retrieve code-review | from json
    if ($comments | is-empty) {
        print -e "No code-review comments."
        return
    }
    let items = $comments | each {|comment|
        # The comments above it in its file go too: their lines shift it up.
        let shift = $comments | where file == $comment.file and line-end < $comment.line-start | each {|above| seq $above.line-start $above.line-end } | flatten | length
        [$"($comment.file):($comment.line-start - $shift)" $comment.comment ($comment.meta | to toml | str trim)] | compact --empty | str join "\n"
    }
    just remove code-review --apply
    $items | enumerate | each { $"($in.index + 1). ($in.item)" } | str join "\n\n" | tee { pbcopy }
}
