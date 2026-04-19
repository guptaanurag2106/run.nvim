local Path = require("plenary.path")
local _browsers = require("run.browsers")
local config = require("run.config")
local utils = require("run.utils")
local run = require("run.run")

local M = {}

M.last_run = {
    command = "",
    cwd = "",
    async = false
}

local history_cache = {
    path = nil,
    mtime_sec = nil,
    mtime_nsec = nil,
    history = nil,
}

local extension_suffix_cache = {
    default_actions_ref = nil,
    suffixes = nil,
}

local get_extension_suffixes = function()
    local default_actions = config.options.default_actions or {}
    if extension_suffix_cache.default_actions_ref == default_actions and extension_suffix_cache.suffixes ~= nil then
        return extension_suffix_cache.suffixes
    end

    local suffixes = {}
    for ext, _ in pairs(default_actions) do
        if ext:sub(1, 1) == "." then
            suffixes[#suffixes + 1] = ext
        end
    end

    extension_suffix_cache.default_actions_ref = default_actions
    extension_suffix_cache.suffixes = suffixes
    return suffixes
end

local resolve_fallback_cwd = function(bufnr)
    local global_cwd = vim.fn.getcwd()
    if config.options.cwd_fallback_scope ~= "buffer" then
        return global_cwd
    end

    if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
        return global_cwd
    end

    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == "" then
        return global_cwd
    end

    local dir = vim.fn.fnamemodify(bufname, ":p:h")
    if dir == "" then
        return global_cwd
    end

    local stat = vim.uv.fs_stat(dir)
    if stat and stat.type == "directory" then
        return dir
    end

    return global_cwd
end

---Setup the plugin with user-provided options.
---@param opts table User configuration overrides
---@return nil
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

    vim.api.nvim_create_user_command("RunLast", function()
        M.runLast()
    end, { desc = "Re-run previous command" })
end

---Run command on the selected file list
---@param range table Range of selection (from user_command `command` params)
---@param async boolean Run command in async mode or not
---@return nil
M.runfile = function(range, async)
    local bufnr = vim.api.nvim_get_current_buf()
    local current_filetype = vim.bo[bufnr].filetype

    local default_command = "{open} %f"
    local need_completion = true
    local out_of_browser = false

    local skip_browser_lookup = config.options.current_browser == "oil" and current_filetype ~= "oil"

    local ok = false
    local file_list = {}
    local curr_dir = ""
    if skip_browser_lookup then
        default_command = "" -- Default incase using from somewhere else
        curr_dir = resolve_fallback_cwd(bufnr)
        out_of_browser = true
    else
        ok, file_list = pcall(M._get_current_files, range, bufnr)
    end

    if not skip_browser_lookup and (not ok or file_list == nil) then
        -- print("Cannot get current files. Please ensure you are in the file browser: " ..
        --     config.options.current_browser .. "\n" .. file_list)
        -- return
        default_command = "" -- Default incase using from somewhere else
        file_list = {}
        curr_dir = resolve_fallback_cwd(bufnr)
        out_of_browser = true
    elseif not skip_browser_lookup then
        local ok1, browser_cwd = pcall(M._get_current_dir, bufnr)
        if not ok1 or browser_cwd == nil or browser_cwd:len() == 0 then
            -- print("Cannot get current directory. Please ensure you are in the file browser: " ..
            --     config.options.current_browser .. "\n" .. browser_cwd)
            -- return
            default_command = "" -- Default incase using from somewhere else
            curr_dir = resolve_fallback_cwd(bufnr)
            out_of_browser = true
        else
            curr_dir = browser_cwd
        end

        if #file_list > 0 then
            local filtered_file_list = {}
            for _, file in ipairs(file_list) do
                if file ~= ".." then
                    filtered_file_list[#filtered_file_list + 1] = file
                end
            end
            file_list = filtered_file_list
        end
    end

    local has_action_function_command = false
    if not out_of_browser and config.options.action_function ~= nil then
        local ok, action_function_command, func_need_completion =
            pcall(config.options.action_function, file_list, curr_dir)
        if ok and action_function_command ~= nil then
            default_command = action_function_command
            need_completion = func_need_completion
            has_action_function_command = true
        end
    end

    if not out_of_browser and not has_action_function_command then
        local type = M._get_selected_type(curr_dir, file_list)
        if config.options.default_actions[type] ~= nil then
            default_command = config.options.default_actions[type].command
        end
        need_completion = true
    end

    local suggestion_hist = {}
    local history = {}
    local history_key = out_of_browser and "__run_out_of_browser__" or default_command

    if config.options.history ~= nil and config.options.history.enable then
        ok, suggestion_hist, history = pcall(M._get, history_key, config.options.history.history_file)
        if ok then
            if not suggestion_hist then
                suggestion_hist = {}
            end
        else
            suggestion_hist = {}
            history = {}
        end
    end

    local prompt
    if out_of_browser then
        prompt = "[Run]: "
    else
        prompt = "[Run (Default: " .. default_command .. ") on " .. table.concat(file_list, ", ") .. "]: "
    end

    local ui_history = #suggestion_hist > 1 and vim.list_slice(suggestion_hist, 1, #suggestion_hist - 1) or {}

    local default_suggestion = suggestion_hist[#suggestion_hist] or default_command

    local on_confirm = function(input)
        -- Continue execution inside callback since it's async
        if not input then
            return
        end

        local command = ""
        if string.len(input) == 0 then
            command = default_command
        else
            command = input
            need_completion = true --TODO:pass in commands that don't need completion (`make`)
        end

        if not out_of_browser and need_completion then
            command = M._fill_input(command, curr_dir, file_list)
        end
        command = command:gsub("%s+", " "):gsub("[\r\n]", "")

        local execute = true
        if config.options.ask_confirmation then
            while true do
                local message = ("Run [" .. command .. "] (Y/n): ")
                local response = vim.fn.input(message)
                local response_lower = response:lower()

                if response_lower == "y" or string.len(response) == 0 then
                    execute = true
                    break
                elseif response_lower == "n" then
                    execute = false
                    break
                else
                    print("\nInvalid input. Please enter 'y' or 'n'.")
                end
            end
        end

        if not execute then
            vim.notify("\nRun: Cancelled", vim.log.levels.ERROR)
            return
        end

        if config.options.history ~= nil and config.options.history.enable then
            if default_command ~= input and default_suggestion ~= input and string.len(input) ~= 0 then
                M._save(history_key, input, config.options.history.history_file, history, default_command) -- Key is command (deterministic) and user choice is input (from prompt)
            end
        end

        M.last_run = {
            command = command,
            cwd = curr_dir,
            async = async
        }

        -- Run `input`
        if async then
            local job_id =
                run.run_async(command, curr_dir, config.options.populate_qflist_async, config.options.open_qflist_async)
            _ = job_id
        else
            print("\n")
            run.run_sync(command, curr_dir, config.options.populate_qflist_sync, config.options.open_qflist_sync)
        end
    end

    -- Use custom UI or standard vim.ui.input
    if config.options.use_custom_ui then
        require("run.ui").input({
            prompt = prompt,
            default = default_suggestion,
            history = ui_history,
            cwd = curr_dir,
        }, on_confirm)
    else
        vim.ui.input({ prompt = prompt, default = default_suggestion, completion = "file" }, on_confirm)
    end
end

M.runLast = function()
    local command = M.last_run.command
    if command ~= nil and command ~= "" then
        -- Run `input`
        if M.last_run.async then
            local job_id =
                run.run_async(command, M.last_run.cwd, config.options.populate_qflist_async,
                    config.options.open_qflist_async)
            _ = job_id
        else
            print("\n")
            run.run_sync(command, M.last_run.cwd, config.options.populate_qflist_sync, config.options.open_qflist_sync)
        end
    else
        vim.notify("Run: No last command found", vim.log.levels.WARN)
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
    if file_list == nil or #file_list == 0 then
        return "default"
    end
    local type = nil
    local default_actions = config.options.default_actions or {}
    local suffixes = get_extension_suffixes()

    for _, file in ipairs(file_list) do
        local type1 = nil
        local extension = utils.get_file_extension(file)
        if extension == nil then
            type1 = "no_extension"
        else
            local exact_ext = "." .. extension
            if default_actions[exact_ext] ~= nil then
                type1 = exact_ext
            else
                for _, ext in ipairs(suffixes) do
                    if utils.ends_with(file, ext) then
                        type1 = ext
                        break
                    end
                end
            end
        end

        if type1 == nil or type1 == "no_extension" then
            local abs_path = utils.path_join(curr_dir, file)
            local stat = vim.uv.fs_stat(abs_path)
            if stat then
                if stat.type == "directory" then
                    type1 = "dir"
                elseif stat.type == "file" and vim.fn.executable(abs_path) == 1 then --TODO:check stat.mode bitwise?? cross platform??
                    type1 = "exe"
                end
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
---Format command input by replacing placeholders with actual paths/names.
---@param input string User input command
---@param curr_dir string current directory
---@param file_list table file list (names only, not full paths)
---@return string formmatted user input
M._fill_input = function(input, curr_dir, file_list)
    -- Sanitize curr_dir to remove trailing whitespace/newlines
    curr_dir = curr_dir:gsub("%s*$", "")

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
        local paths = {}
        for _, file in ipairs(file_list) do
            table.insert(paths, curr_dir .. utils.path_separator .. file)
        end
        local path_string = table.concat(paths, " ")
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
        local paths = {}
        for _, file in ipairs(file_list) do
            table.insert(paths, curr_dir .. utils.path_separator .. file)
        end
        local path_string = table.concat(paths, " ")
        if result:sub(-1) ~= " " then
            result = result .. " "
        end
        result = result .. path_string
    end

    return result
end

---get last user prompt for given command
---Retrieve history entries for a given key from history file.
---@param key string the command determined from default_actions
---@param path string the history file path
---@return table|nil, table history list for key (or nil) and full history table
M._get = function(key, path)
    local stat = vim.uv.fs_stat(path)
    local mtime_sec = stat and stat.mtime and stat.mtime.sec or nil
    local mtime_nsec = stat and stat.mtime and stat.mtime.nsec or nil

    local history = {}
    if history_cache.path == path and history_cache.history ~= nil and history_cache.mtime_sec == mtime_sec
        and history_cache.mtime_nsec == mtime_nsec then
        history = history_cache.history
    else
        history = {}
        if stat and stat.type == "file" then
            local p = Path:new(path)
            local ok, content = pcall(function()
                return p:read()
            end)
            if ok and content and #content > 0 then
                local ok2, decoded = pcall(vim.json.decode, content)
                if ok2 and type(decoded) == "table" then
                    history = decoded
                end
            end
        end
        history_cache.path = path
        history_cache.mtime_sec = mtime_sec
        history_cache.mtime_nsec = mtime_nsec
        history_cache.history = history
    end

    local val = history[key]
    if type(val) == "string" then --Old style
        val = { val }
    end
    return val, history
end

---Save a user-entered command into history for a given key.
---@param key string the command determined from default_actions
---@param value string user command for the given prompt
---@param path string the history file path
---@param history table the old history, (_save will modify it)
---@param seed string|nil default suggestion for this key
---@return nil
M._save = function(key, value, path, history, seed)
    if history[key] == nil then
        history[key] = {}
    end

    -- If history is empty, save the default command (key) first so it is preserved
    local default_seed = seed
    if default_seed == nil then
        default_seed = key
    end
    if #history[key] == 0 and #default_seed > 0 then
        table.insert(history[key], default_seed)
    end

    table.insert(history[key], value)

    while #history[key] > 10 do
        table.remove(history[key], 1)
    end

    Path:new(path):write(vim.fn.json_encode(history), "w")

    local stat = vim.uv.fs_stat(path)
    history_cache.path = path
    history_cache.mtime_sec = stat and stat.mtime and stat.mtime.sec or nil
    history_cache.mtime_nsec = stat and stat.mtime and stat.mtime.nsec or nil
    history_cache.history = history
end

--------------------------------------------------------
---Functions for end-user configuration
--------------------------------------------------------

---Return true if `str` ends with `suffix`. (for file extensions)
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

--TODO:no need for fill input
--TODO:multiple action per file (options) add to config
