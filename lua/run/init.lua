local _browsers = require("run.browsers")
local config    = require("run.config")
local utils     = require("run.utils")
local uv        = vim.uv

local M         = {}

M.setup         = function(opts)
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
    ---TODO: multiple files
    ---TODO: different types async/term etc.
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
        return
    end

    local file_list = { curr_file }

    local type = M._get_selected_type(file_list)
    local command = "xdg-open %f"
    if config.options.default_actions[type] ~= nil then
        command = config.options.default_actions[type].command
    end

    local prompt = "Run: (Default: " .. command .. ") on " .. table.concat(file_list, " ") .. " "

    local input = vim.fn.input(prompt)
    if not input or string.len(input) == 0 then
        input = command
    end

    input = M._fill_input(input, file_list)
    input = input:gsub("%s+", " ")

    local execute = true
    if config.options.ask_confirmation then
        while true do
            local message = ("Run [" .. input .. "] (Y/n): ")
            execute = vim.fn.input(message)

            if execute:lower() == "y" or execute:lower() == "Y" or string.len(execute) == 0 then
                execute = true
                break
            elseif execute:lower() == "n" or execute:lower() == "N" then
                execute = false
                break
            else
                print("\nInvalid input. Please enter 'y' or 'n'.")
            end
        end
    end

    if not execute then
        print("\nCancelled")
        return
    end
    print("\nRunning")
    -- Run `input`
end

M.rundir = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, curr_dir = pcall(M.get_current_dir, bufnr)
    if not ok then
        print("Cannot get current directory. Please ensure you are in the file browser: " ..
            config.options.current_browser)
        print(curr_dir)
        return
    end
end

---Fill values for ` %f`, ` %1` etc. The placeholders %x should have a space in the beginning, otherwise they are ignored
---If you want to use %x for some other purpose escape `%` with `%%`. All `%%` will be replaced by `%`
---Add %f at end if no %.. found
---@param input string User input command
---@param file_list table file list
---@return string formmated user input
M._fill_input = function(input, file_list)
    -- Flag to track if any placeholder was found
    local placeholder_found = false
    local result = input

    -- Replace numbered placeholders surrounded by spaces " %1 ", " %2 ", etc.
    for i, file in ipairs(file_list) do
        local pattern = "%%" .. i
        if result:match(pattern) then
            result = result:gsub(pattern, " " .. file)
            placeholder_found = true
        end
    end

    -- Replace %f surrounded by spaces
    local files_string = " " .. table.concat(file_list, " ") .. " "
    if result:match("%%f") then
        result = result:gsub(" %%f", files_string)
        placeholder_found = true
    end

    if result:match("%%") then
        result = result:gsub("%%", "%")
        placeholder_found = true
    end

    -- If no placeholder was found, append files at the end
    if not placeholder_found then
        if result:sub(-1) ~= " " then
            result = result .. " "
        end
        result = result .. table.concat(file_list, " ")
    end

    return result
end


---Returns type for the file list. See `config.options.default_actions` for all possible types
---@param file_list table
---@return string
M._get_selected_type = function(file_list)
    if file_list == nil then
        return "default"
    end
    local type = nil

    for _, file in pairs(file_list) do
        local type1 = nil
        for ext, _ in pairs(config.options.default_actions) do
            if ext:sub(1, 1) == "." and utils.ends_with(file, ext) then
                type1 = ext
                break
            end
        end

        if type1 == nil then
            --TODO: check for no_extension
            local stat = uv.fs_stat(file)
            if stat then
                if stat.type == "directory" then
                    type1 = "dir"
                elseif stat.type == "file" and vim.fn.executable(file) == 1 then --TODO:check stat.mode bitwise?? cross platform??
                    type1 = "exe"
                end
            else
                type1 = "default"
            end
        end

        if type ~= nil then
            if type1 ~= type then
                type = "multiple"
                break
            end
        else
            type = type1
        end
    end

    if type == nil then
        type = "default"
    end
    return type
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

return M

--TODO:multiple action per file (options)
