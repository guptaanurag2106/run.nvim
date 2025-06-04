# Run.nvim
 
Run.nvim is a lightweight Neovim plugin that streamlines file operations within file explorers like Oil and netrw.
Inspired by the convenience of Emacs’ Dired mode([dired-do-shell-command](https://www.gnu.org/software/emacs/manual/html_node/emacs/Shell-Commands-in-Dired.html)),
Run.nvim lets you quickly execute common file commands (such as extracting archives, changing permissions, or running common file types)
directly from your file browser.

You can simply select files (by placing your cursor on the line, or visual-select a list of files),
call the plugin and run commands on those files


https://github.com/user-attachments/assets/98fd5f4e-bbe5-434d-8d4d-b7f199cfc49a


<!-- TOC -->

- [Why Run.nvim](#why-runnvim)
- [Installation](#installation)
  - [Using lazy.nvim](#using-lazynvim)
  - [Using packer.nvim](#using-packernvim)
- [Quick Start](#quick-start)
- [User Commands and Keymaps](#user-commands-and-keymaps)
- [Features](#features)
- [Configuration](#configuration)
- [Using with Other File Browsers](#using-with-other-file-browsers)
- [Command Placeholders](#command-placeholders)
- [Default Actions](#default-actions)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

<!-- /TOC -->

## Why Run.nvim
When working in Neovim, you often need to perform various operations on files -
running scripts, extracting archives, compiling code, or opening files with
external applications.

Run.nvim  makes these tasks easier by:
- Providing sensible default commands based on file types (Not having to remember the exact commands)
- Executing commands without leaving your editor
- Running commands in the directory open in the browser (irrespective of `cwd`)
- Displaying command output directly in Neovim in a separate buffer, to easily copy/modify the output
- Supporting both synchronous and asynchronous execution options
- Providing placeholder system ([Command Placeholders](#command-placeholders)) for easy typing

The plugin is particularly useful for file browser workflows, where you're already navigating
your filesystem within Neovim and want to perform operations on the files you're browsing.

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "guptaanurag2106/run.nvim",
    dependencies = { 'nvim-lua/plenary.nvim' }
    config = function()
            require("run").setup({})
    end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "guptaanurag2106/run.nvim",
    requires = { {'nvim-lua/plenary.nvim'} }
    config = function()
            require("run").setup({})
    end
}
```

## Quick Start

1. Navigate to a file in your file browser ([oil.nvim](https://github.com/stevearc/oil.nvim) by default)
2. Press `:RunFile` to run the appropriate command for that file type
3. For background execution with live output in a new buffer, use `:RunFileAsync` instead

## User Commands and Keymaps
The plugin creates two user commands `RunFile`, `RunFileAsync`. No keymaps are however
created and it's left to the user. An example keymap could be as simple as
```lua
vim.keymap.set({ "v", "n" }, "<leader>rf", ":RunFileAsync<CR>", { desc = "(Run.nvim) Async" })
```

## Features
- Quick File Detection:
    * Retrieves the full path of the file or directory under the cursor with ease.
- Predefined Commands:
    * Offers a set of ready-to-use commands like tar extraction, chmod +x, xdg-open, and more.
- Custom Actions:
    * The plugin suggests a default command, you can change it by typing your own command (after the `[Run (Default: <cmd>) on <file>]:` and making use of ([Command Placeholders](#command-placeholders)).
- Flexible Execution:
    * Choose to run commands synchronously, asynchronously and populate the qflist with the output
- Output Window
    * Unbuffered output of asynchronous commands can be seen in a new popup window which opens at the bottom
    * It support `q` to close and `<C-c>` to stop command execution
    * The buffer is reused if multiple `:RunAsync` are started
- History
    * If you provide a command other than default, it is saved to history and is suggested from then onwards for that filetype

## Configuration

Run.nvim works out of the box, but you can customize it to fit your workflow:

```lua
require("run").setup({
  -- File browser to use (default: "oil")
  current_browser = "oil",
  
  -- Ask for confirmation before executing commands
  ask_confirmation = false,
  
  -- open_cmd, default is xdg-open for linux, open for macos, start in windows
  open_cmd = 'xdg-open'
  
  -- Auto-populate quickfix list with command output for sync commands
  populate_qflist_sync = false,
  -- Auto-populate quickfix list with command output for async commands
  populate_qflist_async = true,
  
  -- Auto-open quickfix list with command output for sync commands
  open_qflist_sync = false,
  -- Auto-open quickfix list with command output for async commands
  open_qflist_async = false,
  
  -- Enable command history
  history = {
    enable = true,
    history_file = vim.fn.stdpath("cache") .. "/run.nvim.hist"
  },
  
  -- Customize default actions for specific file types
  default_actions = {
    -- Example: custom Python command
    [".py"] = {
      command = "python -m %f",
      description = "Run Python module"
    },
    -- Add your own commands here
  },
  action_function = function(file_list, curr_dir)
      -- return <cmd>, <requires_completion>
      if #file_list == 1 and file_list[1] == "Makefile" then
          return "make -B", false
      end

       for _, file in ipairs(file_list) do
           if file == "go.mod" or file == "go.sum" then
               return "go run .", false
           end
       end
      return nil, false
  end
})
```

## Using with Other File Browsers

Run.nvim works with [oil.nvim](https://github.com/stevearc/oil.nvim) by default, but you can use it with any file browser:

```lua
-- Example: Integration with nvim-tree
require("run").register("nvim-tree", "get_current_files", function(range, bufnr)
  -- range is a table {line1: int, line2:int} representing range of selected text
  -- range[line1]=range[line2]=current line if user in normal mode
  -- bufnr is the buffer number of the file browser
  -- Return list of selected file names in nvim-tree
  -- Implementation depends on nvim-tree API
  return {"file1.txt", "file2.py"}
end)

require("run").register("nvim-tree", "get_current_dir", function(bufnr)
  -- bufnr is the buffer number of the file browser
  -- Return current directory path in nvim-tree
  return "/path/to/directory"
end)

-- Set nvim-tree as current browser
require("run").set_current_browser("nvim-tree")
```

## Command Placeholders

Run.nvim uses a simple placeholder system for paths:

- `%f` - All file/folder names, space-separated
- `%d` - Current directory path
- `%1`, `%2`, etc. - Individual file/folder names
- `%d/%f` - Full paths for all files
- `%%` - Literal % character (For commands that need things like %1, sed for e.g.)
- `{open}` - System-specific open command

## Default Actions

Run.nvim comes with sensible defaults for common file types:

- **Python** (`.py`): Runs with Python interpreter
- **Bash/Shell** (`.sh`, `.bash`): Executes scripts
- **Archives** (`.tar.gz`): Extract to current directory
- **JavaScript** (`.js`): Runs with Node.js
- **Java** (`.java`, `.jar`): Compiles and runs Java files
- **C/C++** (`.c`, `.cpp`): Compiles source files
- **Markdown** (`.md`): Converts to HTML with pandoc
- **Media** (`.mp4`, `.mp3`): Opens with VLC
- **Web** (`.html`): Opens in default browser
- **And some more...**

- Special Types
    * *no_extension*: When the file has no_extension, the default suggestion is `chmod +x`
    * *dir*: When the selected entry is a directory, the default suggestion is to create a `.tar.gz`
    * *multiple*: When a combination of different file/folder types is selected, 
        the suggestion is to create a `.tar.gz`
    * *default*: When none of the above categories can be inferred, the default suggestion
        is to open it (`open` in macos, `xdg-open` in linux, `start` for windows this can be customized in `setup` function)

You can override any of these or add your own in the configuration.

## Documentation

For complete documentation, run `:help run.nvim` in Neovim after installation.

## [License](License)

MIT
