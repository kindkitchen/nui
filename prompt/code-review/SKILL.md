---
name: code-review
description: Explore, answer and fix code-review comments, notes marked in any file of this repository, through its `just <action> code-review` commands. Use only when referenced explicitly, as ./prompt/code-review.
---

# Code-review comments

Code-review comments are notes the user marks in any file, so a place in the code speaks for itself: questions, remarks, todos. The text after `./prompt/code-review` in the user's message is your task. Without one, summarize the comments with `just status code-review` and `just retrieve code-review`, then ask.

## Tools

Use these commands to find and inspect comments; never search for the markers yourself. Their output is JSON when captured.

- `just retrieve code-review [paths] [--meta='<toml>']`: valid comments with `file`, `line-start`, `line-end`, `line-next-nonempty` (the code line a comment is about), `comment`, `meta` and `raw`.
- `just check code-review [paths]`: broken comments and their `problems`.
- `just status code-review`: counts and meta values.
- `just remove code-review` and `just config-set code-review`: only on the user's explicit request. Run them without `--apply` first, show what they would change, and apply only once confirmed.

The markers are in `cli/code-review/config.toml`, the rules in `cli/code-review/readme.md`. `just <action> code-review --help` explains each command.

## Answering

A comment may be a conversation: the user asks, you answer below, the user asks again, and so on.

- Answer inside the same comment: right after the text you answer, before its meta and end markers.
- Wrap all you write between `agent-say-start` and `agent-say-end`, each on its own line and in the file's comment syntax, so your words stay distinct from the user's:

  ```text
  // <start>
  // Why is this retried three times?
  // agent-say-start
  // The upstream drops about 1% of calls; three tries keep failures rare.
  // agent-say-end
  // <end>
  ```

- Never change the user's text or earlier answers unless asked. Keep the meta intact and aligned.
- After editing, run `just check code-review <file>` and fix what you broke.

## Broken comments

`just check code-review` reports them. Fix only the ones you are asked about; the scripts never remove broken comments.
