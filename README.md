# diffbuf.nvim

`diffbuf.nvim` renders every tracked working-tree change against the default branch in one read-only Neovim buffer. The view includes committed branch changes, staged changes, and unstaged changes without modifying the repository.

```text
src/example/Thing.java --- 1/2
   21    21 │ class Thing {
         22 │     NewType value;
   22    23 │ }
```

The buffer keeps a row-to-source mapping. Pressing `gd` lazily loads the real source buffer and sends `textDocument/definition` through the LSP client attached to that file, so the synthetic diff coordinates never reach the language server.

## Requirements

- Neovim 0.13+
- Git
- A normally configured LSP server for `gd`

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

Run `:DiffBufOpen` inside a Git worktree. By default the plugin compares the working tree to `refs/remotes/origin/HEAD`, with `main` and `master` fallbacks. An explicit base is also accepted:

```vim
:DiffBufOpen origin/main
```

Buffer-local actions:

| Key | Action |
| --- | --- |
| `gd` | Go to the definition at the mapped working-tree location |
| `<CR>` | Open the mapped source line |
| `]f` / `[f` | Next / previous changed file |
| `]c` / `[c` | Next / previous hunk |
| `r` | Refresh |
| `q` | Close |
| `?` | Help |

Optional configuration:

```lua
require("diffbuf").setup({
  context = 3,
  lsp_attach_timeout_ms = 3000,
})
```

Only tracked files participate in an ordinary Git diff; untracked files are not shown. The initial version highlights diff structure but does not yet project per-language Tree-sitter highlighting into the composite buffer.

## Development

Run the isolated fresh-Neovim tests with:

```sh
make test
```

See `:help diffbuf` for the complete contract.

The reproducible compatibility baseline is Neovim commit `e02755cd9ff29277d14421c9df627e5dc48e4f67`. CI builds that commit and runs the current nightly separately as a drift check.
