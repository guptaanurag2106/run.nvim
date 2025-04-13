local utils = require "run.utils"
local M = {}

local defaults = {
    current_browser = "oil",
    ask_confirmation = false,
    open_cmd = utils.get_open_command(),
    debug = {
        enable = true,
        log_file = vim.fn.stdpath("cache") .. utils.path_separator .. "run.nvim.log"
    },
    default_actions = {
        [".py"] = {
            command = "python %d" .. utils.path_separator .. "%f",
            description = "Run python files (with default python interpreter)"
        },
        [".bash"] = {
            command = "bash %d" .. utils.path_separator .. "%f",
            description = "Run bash files"
        },
        [".sh"] = {
            command = "sh %d" .. utils.path_separator .. "%f",
            description = "Run shell files"
        },
        [".tar.gz"] = {
            command = "tar xzvf %d/%f -C %d",
            description = "Extracts archive file"
        },
        [".exe"] = {
            command = "%d" .. utils.path_separator .. "%1",
            description = "Runs the file (windows exec)"
        },
        ["exe"] = {
            command = "%d" .. utils.path_separator .. "%1",
            description = "Runs the file (only one) if it is executable"
        },
        ["no_extension"] = {
            command = "chmod +x %d" .. utils.path_separator .. "%f",
            description = "chmod +x on the file (if no extension and not executable)"
        },
        ["dir"] = {
            command = "tar czvf %1.tar.gz -C %d %f",
            description = "tar.gz on the folder or multiple folders"
        },
        ["multiple"] = {
            command = "tar czvf %1.tar.gz -C %d %f",
            description = "tar.gz all the files/folders (if mixture of file/folder types)"
        },
        ["default"] = {
            command = "{open} %d" .. utils.path_separator .. "%f",
            description = "Open file with system default application"
        },
        [".zip"] = {
            command = "unzip %f -d %d",
            description = "Extracts zip archive"
        },
        [".rar"] = {
            command = "unrar x %f %d",
            description = "Extracts RAR archive"
        },
        [".jar"] = {
            command = "java -jar %d" .. utils.path_separator .. "%f",
            description = "Runs Java JAR file"
        },
        [".js"] = {
            command = "node %d" .. utils.path_separator .. "%f",
            description = "Runs JavaScript file with Node.js"
        },
        [".ts"] = {
            command = "ts-node %d" .. utils.path_separator .. "%f",
            description = "Runs TypeScript file with ts-node"
        },
        [".go"] = {
            command = "go run %d" .. utils.path_separator .. "%f",
            description = "Runs Go file"
        },
        [".c"] = {
            command = "gcc %d" ..
                utils.path_separator ..
                "%f -o %d" .. utils.path_separator .. "a.out && %d" .. utils.path_separator .. "a.out",
            description = "Compiles and runs C file"
        },
        [".cpp"] = {
            command = "g++ %d" ..
                utils.path_separator ..
                "%f -o %d" .. utils.path_separator .. "a.out && %d" .. utils.path_separator .. "a.out",
            description = "Compiles and runs C++ file"
        },
        [".java"] = {
            command = "javac %d" .. utils.path_separator .. "%f && java -cp %d %1",
            description = "Compiles and runs Java file"
        },
        [".md"] = {
            command = "pandoc %d" ..
                utils.path_separator .. "%f -o %1.html && {open} %d" .. utils.path_separator .. "%1.html",
            description = "Converts Markdown to HTML and opens it"
        },
        [".json"] = {
            command = "jq . %d" .. utils.path_separator .. "%f | less",
            description = "Pretty-prints JSON file"
        },
        [".csv"] = {
            command = "column -t -s, %d" .. utils.path_separator .. "%f | less -S",
            description = "Displays CSV file in columns"
        },
        [".mp4"] = {
            command = "vlc %d" .. utils.path_separator .. "%f",
            description = "Plays video file with VLC"
        },
        [".mp3"] = {
            command = "vlc %d" .. utils.path_separator .. "%f",
            description = "Plays audio file with vlc"
        },
        [".html"] = {
            command = "{open} %d" .. utils.path_separator .. "%f",
            description = "Opens HTML file in default browser"
        },
        [".pdf"] = {
            command = "{open} %d" .. utils.path_separator .. "%f",
            description = "Opens PDF file in default viewer"
        }
    }
}

M.setup = function(opts)
    if opts ~= nil then
        opts["debug"] = nil
    end
    M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
    if M.options.open_cmd == nil or M.options.open_cmd:len() == 0 then
        M.options.open_cmd = utils.get_open_command()
    end
end

return M
