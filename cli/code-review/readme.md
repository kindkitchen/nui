# code-review

Code-review comments are notes marked in any file, so a place in the code speaks for itself: a question, a remark, a todo. Scripts find, check, summarize and remove them deterministically. Agents use the same scripts as tools: `prompt/code-review`.

## Comments

The markers are set in `config.toml`; below they are `<start>`, `<end>` and `<meta>`. They are plain text, so any comment syntax around them works:

```text
/* <start>
   Why is this retried three times?
   <meta>
         status = "open"
<end> */
retry(3, call)
```

- A comment runs from a line with `<start>` to the first line with `<end>` after it. Both on one line make a single-line comment.
- A comment is whole lines: `raw` and removal cover `line-start..line-end`. Keep markers on lines of their own, or removal takes the code sharing them.
- `comment` is the text after `<start>` up to `<meta>` or `<end>`, trimmed.
- Meta is optional TOML after `<meta>`: the rest of its line, then each next line read from the column right after `<meta>`, up to `<end>`. Whatever is left of that column (indentation, `//`, ` *`) is skipped, so align the TOML there.
- Columns count characters; a tab is one.

Broken comments:

- `unclosed`: another `<start>` or the end of the file comes before `<end>`.
- `unopened`: an `<end>` outside of any comment.
- `shared-line`: a line belongs to two comments.
- `meta`: the meta is not TOML.
- `too-many-lines`, `line-too-long`, `predicate`: only with the `check` flags of the same names.

## Commands

`just <action> code-review --help` explains each. Data is a table in a terminal and JSON when piped, e.g. `just retrieve code-review | from json | where meta.status? == "open"`.

- `retrieve`: valid comments as `file`, `line-start`, `line-end`, `line-next-nonempty` (the line it is about), `comment`, `meta`, `raw`.
- `check`: broken comments as `file`, `line-start`, `line-end`, `problems`; exits with 1 if any. `--predicate=<script.nu>` gets a comment's raw text on stdin: printing `false` or failing marks it broken, its stderr says why.
- `status`: counts of comments, broken ones and files, and comments per meta `key = value`.
- `remove`: removes comments. Broken ones in scope block it; `--skip-broken` removes only the valid ones, unless that would re-pair the broken markers left. Broken comments are never removed.
- `config-set`: sets markers, e.g. `marker-start=<value>`. Comments with old markers and existing occurrences of new ones block it; `--replace-old-markers`, `--ignore-old-markers` and `--ignore-already-matches` resolve that. Quote values your shell would evaluate: `'marker-meta=(<new-meta>):'`.
- `test`: end-to-end tests in a throwaway repository.

`remove` and `config-set` only observe by default; `--apply` writes.

All but `test` take `--marker-start`, `--marker-end` and `--marker-meta` to override the config. `retrieve`, `check`, `status` and `remove` take paths, relative to the root, to narrow the scan, and `--meta='<toml>'`: it keeps comments whose meta includes that TOML, records by keys, lists by elements and other values by equality.

Scanned: the root repository and its initialized submodules, tracked files and untracked ones that are not ignored. Binary files and `config.toml` are skipped.
