local M = {}

---The file system path separator for the current platform.
M.path_separator = "/"
M.is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win32unix") == 1
if M.is_windows == true then
    M.path_separator = "\\"
end

M.get_open_command = function()
    ---Return a platform-appropriate 'open' command (`open`, `start`, `xdg-open`).
    ---@return string
    local is_macos = vim.fn.has("mac") == 1

    if M.is_windows then
        return "start"
    elseif is_macos then
        return "open"
    else
        return "xdg-open"
    end
end

---Joins arbitrary number of paths together.
---@param ... string The paths to join.
---@return string
M.path_join = function(...)
    local args = { ... }
    if #args == 0 then
        return ""
    end

    local function normalize_sep(s)
        if not s then
            return ""
        end
        if M.path_separator == "\\" then
            return s:gsub("/", "\\")
        else
            return s:gsub("\\", "/")
        end
    end

    local result = ""
    for _, part in ipairs(args) do
        part = normalize_sep(part)
        if part == "" then
            goto continue
        end

        if result == "" then
            result = part
        else
            -- remove trailing separators from result
            result = result:gsub(M.path_separator .. "+$", "")
            -- remove leading separators from part
            part = part:gsub("^" .. M.path_separator .. "+", "")
            result = result .. M.path_separator .. part
        end
        ::continue::
    end

    return result
end

---Check if string ends with suffix
---@param str string
---@param suffix string
---@return boolean
M.ends_with = function(str, suffix)
    return str:sub(- #suffix) == suffix
end

---Get the file extension from a given filename.
---Return the extension (text after the last dot) or nil when none.
---@param filename string The name of the file (including its extension).
---@return string|nil The file extension, or nil if no extension exists.
M.get_file_extension = function(filename)
    return filename and filename:match("%.([^%.]+)$")
end

return M
