local M = {}

---The file system path separator for the current platform.
M.path_separator = "/"
M.is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win32unix") == 1
if M.is_windows == true then
    M.path_separator = "\\"
end

M.get_open_command = function()
    local is_macos = vim.fn.has('mac') == 1

    if M.is_windows then
        return "start"
    elseif is_macos then
        return "open"
    else
        return "xdg-open"
    end
end

---Split string into a table of strings using a separator.
---@param inputString string The string to split.
---@param sep string The separator to use.
---@return table table A table of strings.
M.split = function(inputString, sep)
    local fields = {}

    local pattern = string.format("([^%s]+)", sep)
    local _ = string.gsub(inputString, pattern, function(c)
        fields[#fields + 1] = c
    end)

    return fields
end

---Joins arbitrary number of paths together.
---@param ... string The paths to join.
---@return string
M.path_join = function(...)
    local args = { ... }
    if #args == 0 then
        return ""
    end

    local all_parts = {}
    if type(args[1]) == "string" and args[1]:sub(1, 1) == M.path_separator then
        all_parts[1] = ""
    end

    for _, arg in ipairs(args) do
        local arg_parts = M.split(arg, M.path_separator)
        vim.list_extend(all_parts, arg_parts)
    end
    return table.concat(all_parts, M.path_separator)
end

---Check if string ends with suffix
---@param str string
---@param suffix string
---@return boolean
M.ends_with = function(str, suffix)
    return str:sub(- #suffix) == suffix
end

--- Get the file extension from a given filename.
---@param filename string: The name of the file (including its extension).
---@return string|nil: The file extension, or nil if no extension exists.
M.get_file_extension = function(filename)
    if filename then
        local dot_position = filename:find("%.")
        if dot_position then
            return filename:sub(dot_position + 1)
        end
    end
    return nil
end

return M
