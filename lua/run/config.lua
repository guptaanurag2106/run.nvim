local M = {}

local defaults = {
    current_browser = "oil",
    ask_confirmation = true,
    debug = {
        enable = true,
        log_file = vim.fn.stdpath("cache") .. "/run.nvim.log"
    },
    default_actions = {
    }
}

M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

return M
