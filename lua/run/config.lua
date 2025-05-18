local utils = require "run.utils"
local M = {}

local defaults = {
    current_browser = "oil",
    ask_confirmation = true,
    open_cmd = utils.get_open_command(),
    populate_qflist_sync = false,
    populate_qflist_async = true,
    open_qflist_sync = false,
    open_qflist_async = false,
    history = {
        enable = true,
        history_file = vim.fn.stdpath("data") .. utils.path_separator .. "run.nvim.json"
    },
    default_actions = {
        [".py"] = {
            command = "python %f",
            description = "Run python files (with default python interpreter)"
        },
        [".lua"] = {
            command = "luajit %f",
            description = "Run lua files via luajit"
        },
        [".bash"] = {
            command = "bash %f",
            description = "Run bash files"
        },
        [".sh"] = {
            command = "sh %f",
            description = "Run shell files"
        },
        [".tar.gz"] = {
            command = "tar xzvf %1 -C %d",
            description = "Extracts archive file"
        },
        [".exe"] = {
            command = "%1",
            description = "Runs the file (windows exec)"
        },
        ["exe"] = {
            command = "." .. utils.path_separator .. "%1",
            description = "Runs the file (only one) if it is executable"
        },
        ["no_extension"] = {
            command = "chmod +x %f",
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
            command = "{open} %f",
            description = "Open file with system default application"
        },
        [".jar"] = {
            command = "java -jar %f",
            description = "Runs Java JAR file"
        },
        [".js"] = {
            command = "node %f",
            description = "Runs JavaScript file with Node.js"
        },
        [".ts"] = {
            command = "ts-node %f",
            description = "Runs TypeScript file with ts-node"
        },
        [".go"] = {
            command = "go run %f",
            description = "Runs Go file"
        },
        [".c"] = {
            command = "gcc %f -o a.out",
            description = "Compiles and runs C file"
        },
        [".cpp"] = {
            command = "g++ %f -o a.out",
            description = "Compiles and runs C++ file"
        },
        [".java"] = {
            command = "javac %f && java -cp %d %1",
            description = "Compiles and runs Java file"
        },
        [".md"] = {
            command = "pandoc %f -o %1.html",
            description = "Converts Markdown to HTML and opens it"
        },
        [".json"] = {
            command = "jq . %f",
            description = "Pretty-prints JSON file"
        },
        [".csv"] = {
            command = "column -t -s, %f",
            description = "Displays CSV file in columns"
        },
        [".mp4"] = {
            command = "vlc %f",
            description = "Plays video file with VLC"
        },
        [".mp3"] = {
            command = "vlc %f",
            description = "Plays audio file with vlc"
        },
        [".html"] = {
            command = "{open} %f",
            description = "Opens HTML file in default browser"
        },
        [".pdf"] = {
            command = "{open} %f",
            description = "Opens PDF file in default viewer"
        }
    },
    action_function = function(file_list, curr_dir)
        -- return <cmd>, <requires_completion>
        if #file_list == 1 and file_list[1] == "Makefile" then
            return "make -B", false
        end

        local is_go_mod = true
        for _, file in ipairs(file_list) do
            if file ~= "go.mod" and file ~= "go.sum" then
                is_go_mod = false
            end
        end
        if is_go_mod then
            return "go run .", false
        end
        return nil, false
    end
}

M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
    if M.options.open_cmd == nil or M.options.open_cmd:len() == 0 then
        M.options.open_cmd = utils.get_open_command()
    end
    if not M.options.populate_qflist_async then
        M.options.open_qflist_async = false
    end
    if not M.options.populate_qflist_sync then
        M.options.open_qflist_sync = false
    end
end

return M
