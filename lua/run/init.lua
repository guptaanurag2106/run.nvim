local Path = require("plenary.path")
local _browsers = require("run.browsers")
local config = require("run.config")
local utils = require("run.utils")
local run = require("run.run")

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
    vim.api.nvim_create_user_command("RunFile", function(args)
        M.runfile({ ["line1"] = args.line1, ["line2"] = args.line2 }, true)
    end, { desc = "Run `command` asynchronously on selected/hovered files", range = true })

    vim.api.nvim_create_user_command("RunFileSync", function(args)
        M.runfile({ ["line1"] = args.line1, ["line2"] = args.line2 }, false)
    end, { desc = "Run `command` on selected/hovered files", range = true })
end

---Run command on the selected file list
---@param range table Range of selection (from user_command `command` params)
---@param async boolean Run command in async mode or not
---@return nil
M.runfile = function(range, async)
    local bufnr = vim.api.nvim_get_current_buf()

    local default_command = "{open} %f"
    local need_completion = true
    local skip_get_command = false
    local out_of_browser = false

    local ok, file_list = pcall(M._get_current_files, range, bufnr)
    if not ok or file_list == nil then
        -- print("Cannot get current files. Please ensure you are in the file browser: " ..
        --     config.options.current_browser .. "\n" .. file_list)
        -- return
        default_command = "" -- Default incase using from somewhere else
        file_list = {}
        out_of_browser = true
    end

    local ok1, curr_dir = pcall(M._get_current_dir, bufnr)
    if not ok1 or curr_dir == nil or curr_dir:len() == 0 then
        -- print("Cannot get current directory. Please ensure you are in the file browser: " ..
        --     config.options.current_browser .. "\n" .. curr_dir)
        -- return
        default_command = "" -- Default incase using from somewhere else
        curr_dir = ""
        out_of_browser = true
    end

    for i, file in ipairs(file_list) do
        if file == ".." then
            table.remove(file_list, i)
        end
    end

    if not out_of_browser and not skip_get_command and config.options.action_function ~= nil then
        local ok, action_function_command, func_need_completion =
            pcall(config.options.action_function, file_list, curr_dir)
        if ok and action_function_command ~= nil then
            default_command = action_function_command
            need_completion = func_need_completion
        else
            local type = M._get_selected_type(curr_dir, file_list)
            if config.options.default_actions[type] ~= nil then
                default_command = config.options.default_actions[type].command
            end
            need_completion = true
        end
    end

    local suggestion_hist = {}
    local history = {}

    if config.options.history ~= nil and config.options.history.enable then
        ok, suggestion_hist, history = pcall(M._get, default_command, config.options.history.history_file)
        if ok then
            if not suggestion_hist then
                suggestion_hist = {}
            end
        else
            suggestion_hist = {}
            history = {}
        end
    end

    local prompt = "[Run (Default: " .. default_command .. ") on " .. table.concat(file_list, ", ") .. "]: "
    if out_of_browser then
        prompt = "[Run]: "
    end

    local input
    local done = false

    local default_suggestion = ""
    if #suggestion_hist > 0 then
        default_suggestion = suggestion_hist[#suggestion_hist]
    end

    vim.ui.input(
        { prompt = prompt, default = default_suggestion, completion = "file" },
        function(inp)
            input = inp
            done = true
        end)
    vim.wait(10000, function() return done end)

    -- input = vim.fn.input(prompt, suggestion_hist, "file")
    local command = ""
    if not input then
        return
    elseif string.len(input) == 0 then
        command = default_command
    else
        command = input
        need_completion = true --TODO:pass in commands that don't need completion (`make`)
    end

    if not out_of_browser and need_completion then
        command = M._fill_input(command, curr_dir, file_list)
    end
    command = command:gsub("%s+", " ")

    local execute = true
    if config.options.ask_confirmation then
        while true do
            local message = ("Run [" .. command .. "] (Y/n): ")
            local response = vim.fn.input(message)

            if response:lower() == "y" or response:lower() == "Y" or string.len(response) == 0 then
                execute = true
                break
            elseif response:lower() == "n" or response:lower() == "N" then
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

    if config.options.history ~= nil and config.options.history.enable then
        if default_command ~= input and default_suggestion ~= input and string.len(input) ~= 0 then
            M._save(default_command, input, config.options.history.history_file, history) -- Key is command (deterministic) and user choice is input (from prompt)
        end
    end

    -- Run `input`
    if async then
            local job_id =
                run.run_async(command, curr_dir, config.options.populate_qflist_async, config.options.open_qflist_async)
        _ = job_id
    else
        print("\n")
        run.run_sync(command, curr_dir, config.options.populate_qflist_sync,
            config.options.open_qflist_sync)
    end
end

--------------------------------------------------------
---HELPER FUNCTIONS
--------------------------------------------------------

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
        local type1 = nil
        local extension = utils.get_file_extension(file)
        if extension == nil then
            type1 = "no_extension"
        else
            for ext, _ in pairs(config.options.default_actions) do
                if ext:sub(1, 1) == "." and utils.ends_with(file, ext) then
                    type1 = ext
                    break
                end
            end
        end

        local stat = vim.uv.fs_stat(utils.path_join(curr_dir, file))
        if stat then
            if stat.type == "directory" then
                type1 = "dir"
            elseif stat.type == "file" and vim.fn.executable(utils.path_join(curr_dir, file)) == 1 then --TODO:check stat.mode bitwise?? cross platform??
                type1 = "exe"
            end
        end

        if type1 == nil then
            type1 = "default"
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
        local path_string = ""
        for i, file in ipairs(file_list) do
            if i > 1 then
                path_string = path_string .. " " -- Add a space between elements
            end
            path_string = path_string .. curr_dir .. utils.path_separator .. file
        end
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
        local path_string = ""
        for i, file in ipairs(file_list) do
            if i > 1 then
                path_string = path_string .. " " -- Add a space between elements
            end
            path_string = path_string .. curr_dir .. utils.path_separator .. file
        end
        if result:sub(-1) ~= " " then
            result = result .. " "
        end
        result = result .. path_string
    end

    return result
end

---get last user prompt for given command
---@param key string the command determined from default_actions
---@param path string the history file path
---@return table, table
M._get = function(key, path)
    local history = vim.json.decode(Path:new(path):read())
    if type(history[key]) == "string" then
        history[key] = { history[key] }
    end
    return history[key], history
end

---save user prompt for given command
---@param key string the command determined from default_actions
---@param value string user command for the given prompt
---@param path string the history file path
---@param history table the old history, (_save will modify it)
---@return nil
M._save = function(key, value, path, history)
    if history[key] == nil then
        history[key] = {}
    end

    table.insert(history[key], value)

    while #history[key] > 20 do
        table.remove(history[key], 1)
    end

    Path:new(path):write(vim.fn.json_encode(history), "w")
end

--------------------------------------------------------
---Functions for end-user configuration
--------------------------------------------------------

---Checks if a str ends with a suffix or not (useful for file extensions)
---@param str string
---@param suffix string
---@return boolean true if str ends with suffix
M.ends_with = function(str, suffix)
    return utils.ends_with(str, suffix)
end

---Split string into a table of strings using a separator.
---@param str string The string to split.
---@param sep string The separator to use.
---@return table table A table of strings.
M.split = function(str, sep)
    return utils.split(str, sep)
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

--------------------------------------------------------
---Internal Functions, not needed to be used by the user
--------------------------------------------------------

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

M._stop_job = function(job_id)
    run.stop_job(job_id)
end

return M

--TODO:Weird escape behaviour on first Run (Default:...) Prompt
--TODO:no need for fill input
--TODO:multiple action per file (options)
