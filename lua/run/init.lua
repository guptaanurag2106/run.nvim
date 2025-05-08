local _browsers = require("run.browsers")
local config    = require("run.config")
local utils     = require("run.utils")
local run       = require("run.run")
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
    vim.api.nvim_create_user_command("RunFile", function(args)
        M.runfile({ ["line1"] = args.line1, ["line2"] = args.line2 }, false)
    end, { desc = "Run `command` on selected/hovered files", range = true })

    vim.api.nvim_create_user_command("RunFileAsync", function(args)
        M.runfile({ ["line1"] = args.line1, ["line2"] = args.line2 }, true)
    end, { desc = "Run `command` asynchronously on selected/hovered files", range = true })
end


---Run command on the selected file list
---@param range table Range of selection (from user_command `command` params)
---@param async boolean Run command in async mode or not
---@return nil
M.runfile = function(range, async)
    local bufnr = vim.api.nvim_get_current_buf()

    local ok, file_list = pcall(M._get_current_files, range, bufnr)
    if not ok or file_list == nil then
        print("Cannot get current files. Please ensure you are in the file browser: " ..
            config.options.current_browser .. "\n" .. file_list)
        return
    end

    local ok1, curr_dir = pcall(M._get_current_dir, bufnr)
    if not ok1 or curr_dir == nil or curr_dir:len() == 0 then
        print("Cannot get current directory. Please ensure you are in the file browser: " ..
            config.options.current_browser .. "\n" .. curr_dir)
        return
    end

    local command = "{open} %f"
    local need_completion = true
    if config.options.action_function ~= nil then
        local ok, action_function_command, func_need_completion = pcall(config.options.action_function, file_list,
            curr_dir)
        if ok and action_function_command ~= nil then
            command = action_function_command
            need_completion = func_need_completion
        else
            local type = M._get_selected_type(curr_dir, file_list)
            if config.options.default_actions[type] ~= nil then
                command = config.options.default_actions[type].command
            end
            need_completion = true
        end
    end


    local prompt = "[Run (Default: " .. command .. ") on " .. table.concat(file_list, ", ") .. "]: "

    local input = vim.fn.input(prompt)
    if not input or string.len(input) == 0 then
        input = command
    else
        need_completion = true --TODO:pass in commands that don't need completion (`make`)
    end

    if need_completion then
        input = M._fill_input(input, curr_dir, file_list)
    end
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
        vim.notify("\nCancelled", vim.log.levels.ERROR)
        return
    end

    -- Run `input`
    if async then
        run.run_async(input, curr_dir, config.options.populate_qflist_async, config.options.open_qflist_async)
    else
        print("\n")
        run.run_sync(input, curr_dir, config.options.populate_qflist_sync, config.options.open_qflist_sync)
    end
end


---Returns type for the file list. See `config.options.default_actions` for all possible types
---@param curr_dir string
---@param file_list table
---@return string
M._get_selected_type = function(curr_dir, file_list)
    if file_list == nil then
        return "default"
    end
    local type = nil

    for _, file in pairs(file_list) do
        file = utils.path_join(curr_dir, file)
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
                else
                    type1 = "default"
                end
            else
                type1 = "default"
            end
        end

        if type ~= nil then
            if type ~= type1 then
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


---Fill values for `%f`, `%1`, `%d`
---If you want to use %.. for some other purpose escape `%` with `%%`. All `%%` will be replaced by `%`
---Add `%d/%f` at end if no %.. found
---@param input string User input command
---@param curr_dir string current directory
---@param file_list table file list (just names not full paths)
---@return string formmated user input
M._fill_input = function(input, curr_dir, file_list)
    -- Flag to track if any placeholder was found
    local placeholder_found = false
    local result = input

    local path_string = ""
    for i, file in ipairs(file_list) do
        if i > 1 then
            path_string = path_string .. " " -- Add a space between elements
        end
        path_string = path_string .. curr_dir .. utils.path_separator .. file
    end

    -- Replace numbered placeholders surrounded by spaces " %1 ", " %2 ", etc.
    for i, file in ipairs(file_list) do
        local pattern = "%%" .. i
        if result:match(pattern) then
            result = result:gsub(pattern, file)
            placeholder_found = true
        end
    end

    -- Special Case: %d/%f equivalent to %d/%1 %d/%2....
    if result:match("%%d" .. utils.path_separator .. "%%f") then
        result = result:gsub("%%d" .. utils.path_separator .. "%%f", path_string)
        placeholder_found = true
    end

    -- Replace %f surrounded by spaces
    if result:match("%%f") then
        local files_string = table.concat(file_list, " ")
        result = result:gsub("%%f", files_string)
        placeholder_found = true
    end

    -- Replace %d with current directory path
    if result:match("%%d") then
        result = result:gsub("%%d", curr_dir)
        placeholder_found = true
    end

    -- Replace escaped % (%%) with %
    if result:match("%%") then
        result = result:gsub("%%", "%")
        placeholder_found = true
    end

    -- Replace open cmd
    if result:match("{open}") then
        result = result:gsub("{open}", config.options.open_cmd)
    end

    -- If no placeholder was found, append filepaths at the end
    if not placeholder_found then
        if result:sub(-1) ~= " " then
            result = result .. " "
        end
        result = result .. path_string
    end

    return result
end


---Get names of selected file
---For the path also user get_current_dir
---@param range table Range of selection (from user_command `command` params)
---@param bufnr integer bufnr of the open browser
---@return table|nil Path of the selected file
M._get_current_files = function(range, bufnr)
    return _browsers.get_current_files(range, bufnr)
end

---Get path of open folder in browser
---@param bufnr integer bufnr of the open browser
---@return string|nil Path of the open folder
M._get_current_dir = function(bufnr)
    return _browsers.get_current_dir(bufnr)
end

---Register get_current_files, get_current_dir functions for a browser
---@param browser_name string The name of the browser e.g. oil/netrw etc.
---@param func_name string The name of the function either get_current_files/get_current_dir
---@param func function func_name functions for the `browser_name`
M.register = function(browser_name, func_name, func)
    _browsers.register(browser_name, func_name, func)
end

---Sets the current browser in use
---The functions should be implemented first. See `register(browser_name, func_name, func)`
---@param browser_name string The name of the browser you want to set as current
M.set_current_browser = function(browser_name)
    _browsers.set_current_browser(string.lower(browser_name))
end

M._stop_job = function(job_id)
    run.stop_job(job_id)
end

return M

--TODO:jobs return value (valid command etc.)
--TODO:stdin
--TODO:quickfile??
--TODO:closing buffer while the program is running
--TODO:Weird escape behaviour on first Run (Default:...) Prompt
--TODO:no need for fill input
--TODO:Multiple RunFile at same time?
--TODO:command chaining? &&
--TODO:just use table of functions instead of default_actions
--TODO:per project settings
--TODO:history
--TODO:multiple action per file (options)
--TODO:passing keys (commands like "less")
