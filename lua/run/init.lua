local _browsers = require("run.browsers")
local config = require("run.config")

local M = {}

M.setup = function(opts)
    config.setup(opts)
    _browsers.set_current_browser(config.options.current_browser)

    if config.options.browsers then
        for browser_name, funcs in pairs(config.options.browsers) do
            for func_name, func in pairs(funcs) do
                _browsers.register(browser_name, func_name, func)
            end
        end
    end
end

M.setup(nil)

vim.api.nvim_create_user_command("RunFile", function()
    M.runfile()
end, { desc = "Run `command` on selected/hovered files" })

vim.api.nvim_create_user_command("RunDir", function()
    M.rundir()
end, { desc = "Run `command` on directory open in browser" })

M.runfile = function()
    local bufnr = vim.api.nvim_get_current_buf()

    local ok, curr_file = pcall(M.get_current_file, bufnr)
    if not ok then
        print("Cannot get current file. Please ensure you are in the file browser: " .. config.options.current_browser)
        print(curr_file)
    end

    local type = M._get_selected_type({ curr_file })
    local command = config.options.default_actions[type].command or "xdg-open %f"
    local prompt = "Run " .. command

    local input = vim.fn.input(prompt)
    if not input or string.len(input) == 0 then
        input = command
    end

    print("Chosen " .. input)

    -- Fill values for %f %1 etc. Add %f at end if no %.. found
    input = M._fill_input(input, { curr_file })
    -- Run `input`
end

M.rundir = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, curr_dir = pcall(M.get_current_dir, bufnr)
    if not ok then
        print("Cannot get current directory. Please ensure you are in the file browser: " ..
            config.options.current_browser)
        print(curr_dir)
    end

    local type = "dir"
    local command = config.options.default_actions[type].command or "tar czvf %1.tar.gz %f"
    local prompt = "Run " .. command

    local input = vim.fn.input(prompt)
    if not input or string.len(input) == 0 then
        input = command
    end

    -- Fill values for %f %1 etc. Add %f at end if no %.. found
    input = M._fill_input(input, { curr_dir })

    print("Chosen " .. input)
    -- Run `input`
end


---Returns type for the file list. See `config.default_actions` for all possible types
---@param file_list table
---@return string
M._get_selected_type = function(file_list)
    return "default"
end

---Get path of selected file (1)
---@param bufnr integer bufnr of the open browser
---@return string|nil Path of the selected file
M.get_current_file = function(bufnr)
    return _browsers.get_current_file(bufnr)
end

---Get path of open folder in browser
---@param bufnr integer bufnr of the open browser
---@return string|nil Path of the open folder
M.get_current_dir = function(bufnr)
    return _browsers.get_current_dir(bufnr)
end

M.get_line = function(bufnr)
    print(vim.api.nvim_get_current_line())
    print(vim.api.nvim_get_current_buf())
end

return M
