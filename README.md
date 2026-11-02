# About

~~t~~nui (~~Terminal~~Nik's User Interface)


# Codebase organization

Organized as a monorepo by conventions only: no monorepo tool, neither third-party nor custom.

- The root belongs to no application: no `package.json`, `Cargo.toml` or similar manifest. It is the developer-oriented place: overview, shared files, helper scripts and anything else supporting the whole project.
- Applications (sub-projects) live in top-level folders, each with the files typical for its kind. Tech stacks may differ per sub-project.
- Each sub-project is a separate git repository, managed here as a git submodule.
- All submodules point to this same repository, each tracking its own branch. Every sub-project history starts from the `01-01-init` tag.
- Branches and tags of a sub-project are prefixed with its name: `example/main`, `example/dev`, `example-001-tag`.
- A top-level folder that is not a submodule is part of this repository: devx or whole-project oriented, not a project or a library.
- A sub-project shares code through its `src/lib`: sources only, importing nothing but its own files and declared packages. Another sub-project links it into its own `src` under the name of the role, not `lib`, which it has for itself: `nui-web/src/api -> ../../nui-api/src/lib`. It provides those packages at the same versions. The root commits states of both sub-projects together, so the relative links resolve in every one of them.

## Tooling

- Nushell is the first-class shell language: for scripts, commands and examples.
- `justfile` is the public gateway to all functionality of the `cli/` hub: nushell scripts following `cli/readme.md`.
- Commands form a tree, mostly 3 levels deep: `just <action> <target> [...args]`. The action is a general verb, overloaded by the target. `just <target>` lists the actions of a target.
- Features are the targets: `cli/<target>/`, one script per action.
- `devx.nu` runs shortcuts for boring commands from `devx/`, free of the `cli/` conventions: `nu devx.nu <command>`, or `use devx.nu` and `devx <command>`.
- Create a sub-project with `just create submodule --name=<name> --apply`.
- Code-review comments are notes marked in any file, so a place in the code speaks for itself: `cli/code-review/readme.md`.
- `prompt/<name>/` holds agent prompts in the skill format, used only when referenced explicitly, e.g. `./prompt/code-review`.

# Agentic instructions

## Common

- Act only on explicit user intent. Nothing implicit unless it was explicitly allowed.
- Work in explicitly defined, incremental steps. Clarify until agree on each step with the user before moving on.
- Keep output and writes minimal. If not writing gives the same result, don't write.
- Focus on quality where quality is defined as efficient and sophisticated solution.

## Chat

- Be concise. No filler or unrequested elaboration.
- Raise any unplanned improvement, issue or warning as a short notice. Expand only if the user asks.

## Coding

## Responsibilities

- Before any write, state what will change and where. Write only after approval.
- Every action must be traceable to a user task or intention.

