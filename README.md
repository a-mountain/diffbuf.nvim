# diffbuf.nvim

`diffbuf.nvim` reviews a branch from inside Neovim. One review session fixes the base revision, and every surface reads it, so they cannot disagree:

- **Inline diff** — every file of the repository diffed against the base through [mini.diff](https://github.com/nvim-mini/mini.diff); `:DiffBufOverlay` adds the overview, which shows removed lines inside the real file.
- **Changed-files panel** — a sidebar of everything that differs from the base, in a tree or flat layout.
- **Composite buffer** — every changed file in one read-only buffer.

```text
Review  origin/main…a1b2c3d (merge base)
6 files  +5  -2  [tree]

▾ lib
    newname.txt ← lib/renamed.txt        R
▾ src
  ▾ deep/nested
      b.txt                              M +1
    a.txt                                M +3 -1
    added.txt                            A +1
    gone.txt                             D -1
    untracked.txt                        ?
```

## Requirements

- Neovim 0.13+
- Git
- [mini.diff](https://github.com/nvim-mini/mini.diff) for the inline diff
- [mini.icons](https://github.com/nvim-mini/mini.icons) for panel file icons (optional)
- A normally configured LSP server for `gd` in the composite buffer

## Installation

With `vim.pack`:

```lua
vim.pack.add({
  "https://github.com/nvim-mini/mini.diff",
  "https://github.com/a-mountain/diffbuf.nvim",
})
require("mini.diff").setup()
```

With lazy.nvim:

```lua
{
  "a-mountain/diffbuf.nvim",
  dependencies = { "nvim-mini/mini.diff" },
  opts = {},
}
```

## Usage

`:DiffBufReview` starts review mode against the repository default branch, the way a GitHub pull request compares: the base commit is the merge base of the default branch and `HEAD`, so commits that landed on the base branch after your branch forked stay out. An explicit revision is also accepted, with completion over branches and tags:

```vim
:DiffBufReview origin/release-2
```

| Command | Effect |
| --- | --- |
| `:DiffBufReview [rev]` | Start review mode, or switch the base |
| `:DiffBufReviewToggle` | Start or stop review mode |
| `:DiffBufReviewStop` | Stop review mode and release every surface |
| `:DiffBufReviewRefresh` | Re-resolve the base and reload everything |
| `:DiffBufPanel` | Toggle the changed-files panel |
| `:DiffBufOverlay` | Toggle the inline overview |
| `:DiffBufOpen [rev]` | Open the composite diff buffer |

`:DiffBufPanel` and `:DiffBufOverlay` start review mode themselves, so a single mapping is enough to enter review.

No global mappings are set. A typical configuration:

```lua
vim.keymap.set("n", "<leader>grr", "<cmd>DiffBufReviewToggle<cr>", { desc = "Review mode" })
vim.keymap.set("n", "<leader>grb", ":DiffBufReview ", { desc = "Review against…" })
vim.keymap.set("n", "<leader>grf", "<cmd>DiffBufPanel<cr>", { desc = "Changed files" })
vim.keymap.set("n", "<leader>gro", "<cmd>DiffBufOverlay<cr>", { desc = "Inline overview" })
vim.keymap.set("n", "<leader>grd", "<cmd>DiffBufOpen<cr>", { desc = "Composite diff" })
```

### Panel keys

| Key | Action |
| --- | --- |
| `<CR>` / `o` / `l` | Open the file, or expand and collapse the directory |
| `<Tab>` | Open the file and keep the cursor in the panel |
| `h` | Collapse the directory, or move to the parent |
| `H` / `L` | Collapse / expand every directory |
| `t` | Toggle the tree and flat layout |
| `r` / `R` | Reload the file list / re-resolve the base |
| `d` | Open the composite diff buffer |
| `O` | Toggle the inline overview |
| `q` | Close the panel |

### Composite buffer keys

| Key | Action |
| --- | --- |
| `gd` | Go to the definition at the mapped working-tree location |
| `<CR>` | Open the mapped source line |
| `]f` / `[f` | Next / previous changed file |
| `]c` / `[c` | Next / previous hunk |
| `r` | Refresh |
| `q` | Close |

### Configuration

Setup is optional; these are the defaults:

```lua
require("diffbuf").setup({
  context = 3,
  lsp_attach_timeout_ms = 3000,
  review = {
    base = nil,          -- nil resolves the repository default branch
    merge_base = true,   -- GitHub-style three-dot comparison
    untracked = true,    -- untracked files count as fully added
    inline = true,       -- mini.diff inline diff on session start
    overlay = false,     -- start sessions with the overview visible
    panel = true,        -- open the panel on session start
  },
  panel = {
    position = "right",
    width = 0.3,         -- fraction of 'columns', or a column count above 1
    layout = "tree",     -- "tree" or "flat"
    group_dirs = true,
    follow = true,
    icons = true,
  },
})
```

`require("diffbuf").status()` returns `origin/main…a1b2c3d` while a session is active and `""` otherwise, for statuslines. `User` events (`DiffBufReviewStarted`, `DiffBufReviewStopped`, `DiffBufReviewRefreshed`, `DiffBufReviewFilesChanged`) carry `{ root, ref, commit }`.

Review mode owns `MiniDiff.config.source` and `vim.g.minidiff_disable` only while a session is active and restores both afterwards, so a configuration that keeps mini.diff off by default stays off.

See `:help diffbuf` for the complete contract.

## Development

```sh
make test          # fresh-Neovim cases, with mini.diff pinned in .test-deps
make deps          # clone the pinned mini.diff only
make test-live     # run against a real repository: DIFFBUF_LIVE_CWD=…
```

The reproducible compatibility baseline is Neovim commit `e02755cd9ff29277d14421c9df627e5dc48e4f67`. CI builds that commit and runs the current nightly separately as a drift check.
