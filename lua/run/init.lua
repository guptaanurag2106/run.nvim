local browsers = require("run.browsers")
local config = require("run.config")

local M = {}

M.setup = function(opts)
    config.setup(opts)
    browsers.set_current_browser(config.options.current_browser)

    if config.options.browsers then
        for browser_name, funcs in pairs(config.options.browsers) do
            for func_name, func in pairs(funcs) do
                browsers.register(browser_name, func_name, func)
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
    local ok, ret = pcall(M.get_current_file, bufnr)
    if not ok then
        print("Cannot get current file. Please ensure you are in the file browser: " .. config.options.current_browser)
        print(ret)
    end
    ok, ret = pcall(M.get_current_dir, bufnr)
    if not ok then
        print("Cannot get current directory. Please ensure you are in the file browser: " ..
            config.options.current_browser)
        print(ret)
    end
end

M.rundir = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, ret = pcall(M.get_current_dir, bufnr)
    if not ok then
        print("Cannot get current directory. Please ensure you are in the file browser: " ..
            config.options.current_browser)
        print(ret)
    end
end


M.get_current_file = function(bufnr)
    print(browsers.get_current_file(bufnr))
end

M.get_current_dir = function(bufnr)
    print(browsers.get_current_dir(bufnr))
end

M.get_line = function(bufnr)
    print(vim.api.nvim_get_current_line())
    print(vim.api.nvim_get_current_buf())
end

return M
