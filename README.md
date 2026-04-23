# nimbook

A beautiful Jupyter notebook plugin for Neovim, designed for modern terminals.

![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.10-green?logo=neovim)
![License](https://img.shields.io/badge/License-MIT-blue)

## Why nimbook?

Existing solutions require 3-5 plugins stacked together, suffer from Python rplugin performance issues, and have fragile image rendering. Nimbook is a **single plugin** that handles everything:

- **Pure Lua** -- no Python rplugin, no `UpdateRemotePlugins`, no rplugin registration issues
- **Fast kernel communication** -- LuaJIT FFI bindings to libzmq, integrated with Neovim's libuv event loop (zero polling)
- **Beautiful rendering** -- Rich box-drawing borders around cells with execution status, timing, and output
- **Inline images** -- Kitty graphics protocol (Kitty, Ghostty, WezTerm) with Sixel fallback
- **Lossless .ipynb** -- Open, edit, save without losing outputs, metadata, or cell IDs

```
╭── markdown ───────────────────────────────────╮
│ # Data Analysis                               │
│ Load and explore the dataset.                 │
╰───────────────────────────────────────────────╯
╭── python [1] 0.3s ── ✔ ──────────────────────╮
│ import pandas as pd                          │
│ df = pd.read_csv("data.csv")                 │
│ df.head()                                    │
├── output ────────────────────────────────────┤
│   col_a  col_b  col_c                        │
│   1      foo    3.14                         │
│   2      bar    2.71                         │
╰──────────────────────────────────────────────╯
```

## Installation

### Requirements

- Neovim >= 0.10
- `libzmq5` -- kernel communication
- `ipykernel` -- Python kernel
- Treesitter parsers: `markdown`, `python`

```bash
# Ubuntu/Debian
sudo apt install libzmq5
pip install ipykernel

# macOS
brew install zmq
pip install ipykernel
```

### lazy.nvim

```lua
{
  "rfbr/nimbook",
  ft = "ipynb",
  opts = {},
}
```

### With custom config

```lua
{
  "rfbr/nimbook",
  ft = "ipynb",
  opts = {
    render = {
      border_style = "rounded", -- "rounded", "sharp", or "double"
      output_max_lines = 15,
      show_execution_count = true,
      show_execution_time = true,
    },
    kernel = {
      python_cmd = "python3",
    },
  },
}
```

## Usage

Open any `.ipynb` file. Nimbook activates automatically.

```vim
" Create a new notebook
:NimbookNew analysis.ipynb

" Or just open a non-existent .ipynb path
:e my_notebook.ipynb
```

### Kernel

| Command | Key | Description |
|---|---|---|
| `:NimbookKernelStart` | `<leader>ns` | Start a Python kernel |
| `:NimbookKernelRestart` | `<leader>nr` | Restart the kernel |
| `:NimbookKernelInterrupt` | `<leader>ni` | Interrupt execution |
| `:NimbookKernelShutdown` | | Shut down kernel |
| `:NimbookKernelAttach` | | Attach to a running kernel |

### Execution

| Command | Key | Description |
|---|---|---|
| `:NimbookExecute` | `<leader><CR>` / `<C-CR>` | Execute current cell |
| `:NimbookExecuteAndAdvance` | `<CR>` / `<S-CR>` | Execute and move to next cell |
| `:NimbookExecuteAll` | `g<CR>` / `<M-CR>` | Execute all cells |

### Navigation

| Key | Description |
|---|---|
| `]c` / `[c` | Next / previous cell |
| `]C` / `[C` | Next / previous code cell |
| `ic` | Select inner cell (text object) |
| `ac` | Select around cell (text object) |

### Cell operations

| Command | Key | Description |
|---|---|---|
| `:NimbookCellAdd` | `<leader>na` | Add code cell below |
| `:NimbookCellAddAbove` | `<leader>nA` | Add code cell above |
| `:NimbookCellDelete` | `<leader>nd` | Delete current cell |
| `:NimbookCellType` | `<leader>nt` | Toggle code/markdown |
| `:NimbookCellMoveDown` | `<leader>nj` | Move cell down |
| `:NimbookCellMoveUp` | `<leader>nk` | Move cell up |

### Output

| Command | Key | Description |
|---|---|---|
| `:NimbookOutputToggle` | `<leader>no` | Toggle output visibility |
| `:NimbookOutputToggleAll` | `<leader>nO` | Toggle all outputs |
| `:NimbookOutputExpand` | `<leader>ne` | Full output in floating window |
| `:NimbookOutputClear` | `<leader>nx` | Clear cell output |
| `:NimbookOutputClearAll` | `<leader>nX` | Clear all outputs |

### Inspect & Export

| Command | Key | Description |
|---|---|---|
| `:NimbookInspect` | `K` | Show docs for symbol under cursor |
| `:NimbookExport py` | | Export as Python script (percent format) |
| `:NimbookExport md` | | Export as Markdown |

## Features

### Inline images

On Kitty, Ghostty, or WezTerm, matplotlib/seaborn/plotly plots render inline below the code cell. Sixel fallback for foot/XTerm. Text fallback for other terminals.

### Kernel-powered completion

If [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) is installed, nimbook auto-registers as a completion source. Tab completion is powered by the running kernel -- it knows about your imported modules, variables, and methods.

### Cell folding

Cells are foldable via standard vim fold commands (`zc`, `zo`, `zM`, `zR`). Fold text shows a summary: `▸ python [1] │ import pandas as pd ✔ (5 lines)`.

### Lossless save

`:w` saves the notebook as valid `.ipynb` JSON. All metadata, cell IDs, and outputs are preserved. Open a notebook, make no changes, save -- the diff is empty.

### Statusline

```lua
-- lualine example
lualine_x = {
  { require("nimbook").statusline.kernel_status },
  { require("nimbook").statusline.cell_info },
}
```

## Health check

Run `:checkhealth nimbook` to verify all dependencies.

## Architecture

Nimbook talks directly to Jupyter kernels using LuaJIT FFI bindings to `libzmq`. ZMQ socket file descriptors are registered with Neovim's libuv event loop via `vim.uv.new_poll()` -- there are no polling timers, no threads, and no blocking calls. Messages flow from kernel to Neovim's event loop at native speed.

The buffer displays cell sources as markdown with treesitter injection for syntax highlighting. All decorations (borders, outputs, images) are extmarks that don't interfere with editing, undo, or search.

## License

MIT
