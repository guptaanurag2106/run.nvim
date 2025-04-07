local M = {}

local defaults = {
    current_browser = "oil",
    ask_confirmation = true,
    debug = {
        enable = true,
        log_file = vim.fn.stdpath("cache") .. "/run.nvim.log"
    },
    default_actions = {
        [".py"] = {
            command = "python %f",
            description = "Run python files (with default python interpreter)"
        },
        [".bash"] = {
            command = "bash %f",
            description = "Run bash files"
        },
        [".tar.gz"] = {
            command = "tar -xvf %f",
            description = "Extracts archive file"
        },
        ["exe"] = {
            command = "%1",
            description = "Runs the file (only one) if it is executable"
        },
        ["no_extension"] = {
            command = "chmod +x %f",
            description = "chmod +x on the file (if no extension and not executable)"
        },
        ["dir"] = {
            command = "tar czvf %1.tar.gz %f",
            description = "tar.gz on the folder or multiple folders"
        },
        ["multiple"] = {
            command = "tar czvf %1.tar.gz %f",
            description = "tar.gz all the files/folders (if mixture of file/folder types)"
        },
        ["default"] = {
            command = "xdg-open %f",
            description = "xdg-open the file"
        },
    }
}

M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

return M
