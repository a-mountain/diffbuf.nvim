# diffbuf.nvim

`diffbuf.nvim` shows a branch diff in one focused read-only buffer. Every changed file, highlighted per file (Tree-sitter, falling back to Vim syntax) and folded per file and per hunk.

Generated files — the ones GitHub and GitLab collapse for you, marked `linguist-generated` or `gitlab-generated` in `.gitattributes` — sort to the end of the buffer and arrive collapsed there.

## Requirements

- Neovim 0.13+
- Git
- A normally configured LSP server for `gd` in the composite buffer

## Installation

With `vim.pack`:

```lua
vim.pack.add({ "https://github.com/a-mountain/diffbuf.nvim" })
```

With lazy.nvim:

```lua
{
  "a-mountain/diffbuf.nvim",
  opts = {},
}
```

## Usage

`:DiffBufOpen` compares the working tree against the repository default branch, the way a GitHub pull request compares: the base commit is the merge base of the default branch and `HEAD`, so commits that landed on the base branch after your branch forked stay out. An explicit revision is also accepted, with completion over branches and tags:

```vim
:DiffBufOpen origin/release-2
```

| Command | Effect |
| --- | --- |
| `:DiffBufOpen [rev]` | Open the composite diff buffer |
| `:DiffBufRefresh` | Refresh the current buffer |
| `:DiffBufGenerated` | Collapse or expand every generated file |

### Composite buffer keys

| Key | Action |
| --- | --- |
| `gd` | Go to the definition at the mapped working-tree location |
| `<CR>` | Open the mapped source line |
| `]f` / `[f` | Next / previous changed file |
| `]c` / `[c` | Next / previous hunk |
| `zc` / `zo` | Collapse / expand the hunk, then its file |
| `zM` / `zR` | Collapse / expand everything |
| `gh` | Collapse or expand every generated file |
| `r` | Refresh |
| `q` | Close |

### Configuration

Setup is optional; these are the defaults:

```lua
require("diffbuf").setup({
  context = 3,           -- unchanged lines around each hunk
  lsp_attach_timeout_ms = 3000,
  syntax = true,         -- highlight the buffer per file
  filetypes = {},        -- vim.filetype.add() rules for paths Neovim cannot name
  base = nil,            -- nil resolves the repository default branch
  merge_base = true,     -- GitHub-style three-dot comparison
  generated = {
    -- .gitattributes markers; {} turns the detection off
    attributes = { "linguist-generated", "gitlab-generated" },
    collapse = true,     -- generated files load folded
    sort_last = true,    -- behind every hand-written file
  },
})
```

See `:help diffbuf` for the complete contract.

## Development

```sh
make test          # fresh-Neovim cases
make test-live     # run against a real repository: DIFFBUF_LIVE_CWD=…
```

The reproducible compatibility baseline is Neovim commit `e02755cd9ff29277d14421c9df627e5dc48e4f67`. CI builds that commit and runs the current nightly separately as a drift check.
