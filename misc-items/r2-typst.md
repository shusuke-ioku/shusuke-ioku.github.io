::: {.item-intro}
### r2-typst

LaTeX-like minimalist Typst template for academic papers and presentation slides. One style file powers both.

[Open Repository](https://github.com/shusuke-ioku/r2-typst)

<span class="item-updated">Last Updated: 2026-03-22</span>
:::

::: {.item-more}
#### Quick Start

```typst
#import "./style.typ": paper, theorem, proof, prop, lem, asp

#show: doc => paper(
  title: [My Paper],
  authors: ((name: [Author], affiliation: [University]),),
  abstract: [Your abstract here.],
  doc,
)
```

#### Features

- Paper layout with title block, abstract, numbered sections, bibliography
- Polylux slides with matching style from the same file
- Theorem environments (Proposition, Lemma, Assumption, Proof)
- Publication-ready table helpers (`caption-with-note`, `table-note`)
- Customizable design tokens for fonts, colors, spacing
:::
