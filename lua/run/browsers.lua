local M = {}

M.browsers = {}

M.browsers["oil"] = {
    ---Gets current files name under cursor for oil
    ---@param range table Range of selection (from user_command `command` params)
    ---@param bufnr integer The buffer number
    ---@return table|nil
    get_current_files = function(range, bufnr)
        local result = {}
        if range ~= nil and range["line1"] ~= nil and range["line2"] ~= nil then
            for line = range["line1"], range["line2"] do
                local entry = require("oil").get_entry_on_line(bufnr, line)
                if entry and entry.name then
                    table.insert(result, entry.name)
                end
            end
        else
            --Manually get line numbers
            -- Get mode
            local mode = vim.api.nvim_get_mode().mode
            if mode == "v" or mode == "V" or mode == "\22" then
                local start_pos = vim.fn.getpos("'<")
                local end_pos = vim.fn.getpos("'>")
                local start_line = start_pos[2]
                local end_line = end_pos[2]

                for line = start_line, end_line do
                    local entry = require("oil").get_entry_on_line(bufnr, line)
                    if entry and entry.name then
                        table.insert(result, entry.name)
                    end
                end
            else
                local entry = require("oil").get_cursor_entry()
                if entry and entry.name then
                    table.insert(result, entry.name)
                end
            end
        end

        return result
    end,

    ---Gets current open directory name for oil
    ---@param bufnr integer The buffer number
    ---@return string|nil
    get_current_dir = function(bufnr)
        local dir = require("oil").get_current_dir(bufnr)
        return dir
    end,
}

---Register get_current_files, get_current_dir functions for a browser
---Register adapter functions for a browser implementation.
---@param browser_name string The name of the browser e.g. oil/netrw
---@param func_name string Either 'get_current_files' or 'get_current_dir'
---@param func function The implementation function
---@return nil
M.register = function(browser_name, func_name, func)
    if func_name ~= "get_current_files" and func_name ~= "get_current_dir" then
        error("Can't set function " .. func_name)
    end
    if not browser_name or string.len(browser_name) == 0 then
        error("Browser Name cannot be empty")
    end
    -- ensure browser table exists so callers can register new browsers
    M.browsers[browser_name] = M.browsers[browser_name] or {}
    M.browsers[browser_name][func_name] = func
end

---Sets the current browser in use
---The functions should be implemented first. See `register(browser_name, func_name, func)`
---@param browser_name string The name of the browser you want to set as current
---@return nil
M.set_current_browser = function(browser_name)
    if M.browsers and M.browsers[browser_name] then
        M.current_browser = browser_name
    else
        error("Browser " .. browser_name .. " is not implemented")
    end
end

---Gets current file names under cursor/selection using the `current_browser`
---@param range table Range of selection (from user_command `command` params)
---@param bufnr integer The buffer number
---@return table|nil list of filenames or nil on error
M.get_current_files = function(range, bufnr)
    local browser = M.browsers[M.current_browser]
    if not browser then
        error("Browser " .. M.current_browser .. " is not implemented")
        return nil
    end
    if browser.get_current_files then
        local files = M.browsers[M.current_browser].get_current_files(range, bufnr)
        if files and #files ~= 0 then
            return files
        else
            error(M.current_browser .. " returned empty file_name list")
        end
    else
        error("Browser " .. M.current_browser .. " does not implement get_current_files")
        return nil
    end
end

---Gets current open directory in the `current_browser`
---@param bufnr integer The buffer number
---@return string|nil current directory or nil on error
M.get_current_dir = function(bufnr)
    local browser = M.browsers[M.current_browser]
    if not browser then
        error("Browser " .. M.current_browser .. " is not implemented")
        return nil
    end
    if browser.get_current_dir then
        local dir = M.browsers[M.current_browser].get_current_dir(bufnr)
        if dir and string.len(dir) ~= 0 then
            return dir
        else
            error(M.current_browser .. " returned empty dir_name")
        end
    else
        error("Browser " .. M.current_browser .. " does not implement get_current_dir")
        return nil
    end
end

return M
