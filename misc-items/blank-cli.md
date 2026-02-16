::: {.item-intro}
### blank CLI

A CLI scaffolder for research projects driven by agentic AI workflows.

[Open Repository](https://github.com/shusuke-ioku/blank)

<span class="item-updated">Last Updated: 2026-02-12</span>
:::

::: {.item-more}
#### Install

```bash
# From PyPI
pipx install blank-agentic-cli
```
```bash
# From GitHub
pipx install git+https://github.com/shusuke-ioku/blank.git
```

#### Usage

```bash
blank init
blank init my-project
blank init my-project --project-name "My Project"
blank init my-project --dry-run
blank init my-project --force
blank init my-project --no-agents
blank init my-project --paper-template latex
blank init my-project --paper-template blank
```

#### Generated Scaffold

- `analysis/scripts/`
- `analysis/data/`
- `analysis/output/`
- `paper/`
- `idea/`
- `.codex/` and `.claude/` by default
:::
