local M = {}

---Validate configuration table shape and basic types.
---@param opts table
---@return boolean, string|nil true if valid, otherwise false and error message
M.validate_config = function(opts)
    if type(opts) ~= "table" then
        return false, "options must be a table"
    end
    if opts.current_browser ~= nil and type(opts.current_browser) ~= "string" then
        return false, "current_browser must be a string"
    end
    if opts.ask_confirmation ~= nil and type(opts.ask_confirmation) ~= "boolean" then
        return false, "ask_confirmation must be a boolean"
    end
    if opts.use_custom_ui ~= nil and type(opts.use_custom_ui) ~= "boolean" then
        return false, "use_custom_ui must be a boolean"
    end
    if opts.ui ~= nil and type(opts.ui) ~= "table" then
        return false, "ui must be a table"
    end
    if opts.output_window_cmd ~= nil and type(opts.output_window_cmd) ~= "string" then
        return false, "output_window_cmd must be a string"
    end
    if opts.open_cmd ~= nil and type(opts.open_cmd) ~= "string" then
        return false, "open_cmd must be a string or nil"
    end
    if opts.populate_qflist_sync ~= nil and type(opts.populate_qflist_sync) ~= "boolean" then
        return false, "populate_qflist_sync must be a boolean"
    end
    if opts.populate_qflist_async ~= nil and type(opts.populate_qflist_async) ~= "boolean" then
        return false, "populate_qflist_async must be a boolean"
    end
    if opts.history ~= nil and type(opts.history) ~= "table" then
        return false, "history must be a table"
    end
    if opts.default_actions ~= nil and type(opts.default_actions) ~= "table" then
        return false, "default_actions must be a table"
    end
    if opts.action_function ~= nil and type(opts.action_function) ~= "function" then
        return false, "action_function must be a function or nil"
    end
    return true, nil
end

return M
