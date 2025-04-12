local M = {}
local util = require("run.utils")

M.browsers = {}

if package.loaded["oil"] then
    M.browsers["oil"] = {
        ---Gets current file name under cursor for oil
        ---@param bufnr integer The buffer number
        ---@return string|nil
        get_current_file = function(bufnr)
            local entry = require("oil").get_cursor_entry()
            if entry and entry.name then
                return entry.name
            else
                return nil
            end
        end,

        ---Gets current open directory name for oil
        ---@param bufnr integer The buffer number
        ---@return string|nil
        get_current_dir = function(bufnr)
            local dir = require("oil").get_current_dir(bufnr)
            return dir
        end
    }
end

---Register get_current_file, get_current_dir functions for a browser
---@param browser_name string The name of the browser e.g. oil/netrw etc.
---@param func_name string The name of the function either get_current_file/get_current_dir
---@param func function func_name functions for the `browser_name`
M.register = function(browser_name, func_name, func)
    if func_name ~= "get_current_file" and func_name ~= "get_current_dir" then
        error("Can't set function " .. func_name)
    end
    if browser_name ~= nil and string.len(browser_name) ~= 0 then
        M.browsers[browser_name][func_name] = func
    else
        error("Browser Name cannot be empty")
    end
end

---Sets the current browser in use
---The functions should be implemented first. See `register(browser_name, func_name, func)`
---@param browser_name string The name of the browser you want to set as current
M.set_current_browser = function(browser_name)
    if M.browsers and M.browsers[browser_name] then
        M.current_browser = browser_name
    else
        error("Browser " .. browser_name .. " is not implemented")
    end
end

---Gets current file name under cursor using the `current_browser`
---@param bufnr integer The buffer number
---@return string|nil
M.get_current_file = function(bufnr)
    local browser = M.browsers[M.current_browser]
    if not browser then
        error("Browser " .. M.current_browser .. " is not implemented")
        return nil
    end
    if browser.get_current_file then
        local file = M.browsers[M.current_browser].get_current_file(bufnr)
        if file and string.len(file) ~= 0 then
            return file
        else
            error(M.current_browser .. " returned empty file_name")
        end
    else
        error("Browser " .. M.current_browser .. " does not implement get_current_file")
        return nil
    end
end

---Gets current open directory in the `current_browser`
---@param bufnr integer The buffer number
---@return string|nil
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
