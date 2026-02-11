::: {.item-intro}
### blank CLI

`blank` is a CLI scaffolder for research projects driven by agentic AI workflows.
It bootstraps an analysis + paper workspace with optional agent folders.

[Open Repository](https://github.com/shusuke-ioku/blank)
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
