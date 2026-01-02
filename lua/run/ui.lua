local config = require("run.config")
local M = {}

---Creates a floating input window at the bottom
---@param opts table { prompt: string, default: string, history: table }
---@param on_confirm function Callback(input: string|nil)
---@return nil
M.input = function(opts, on_confirm)
    local buf = vim.api.nvim_create_buf(false, true)
    local width = vim.o.columns
    local height = 1

    -- Position at the very bottom
    local row = vim.o.lines - height - 1 -- -1 for command line
    if vim.o.cmdheight == 0 then
        row = vim.o.lines - height
    end
    local col = 0

    local win_opts = {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = config.options.ui.border, -- No border to look like command line
    }

    local win = vim.api.nvim_open_win(buf, true, win_opts)

    if opts.prompt then
        -- Use extmark "virtual text" on the left
        -- Ensure prompt has a little separation
        local prompt_text = opts.prompt
        if string.sub(prompt_text, -1) ~= " " then
            prompt_text = prompt_text .. " "
        end

        vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("run_input"), 0, 0, {
            virt_text = { { prompt_text, config.options.ui.prompt_hl } },
            virt_text_pos = "inline",
            right_gravity = false,
        })
    end
    if opts.default then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default })
        vim.api.nvim_win_set_cursor(win, { 1, #opts.default })
    end

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "run_input"

    local history = opts.history or {}
    local history_index = #history + 1
    local current_input = opts.default or ""

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    local map = function(mode, lhs, rhs)
        vim.keymap.set(mode, lhs, rhs, { buffer = buf, nowait = true, silent = true })
    end

    map({ "i", "n" }, "<CR>", function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
        vim.cmd("stopinsert")
        close()
        on_confirm(lines[1] or "")
    end)

    map("i", "<C-c>", function()
        vim.cmd("stopinsert")
        close()
        on_confirm(nil)
    end)

    map("n", "<Esc>", function()
        close()
        on_confirm(nil)
    end)

    map("n", "q", function()
        close()
        on_confirm(nil)
    end)

    map({ "i", "n" }, "<Up>", function()
        if #history == 0 then
            return
        end

        if history_index == #history + 1 then
            current_input = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
        end

        if history_index > 1 then
            history_index = history_index - 1
            local item = history[history_index]
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { item })
            vim.api.nvim_win_set_cursor(win, { 1, #item })
        end
    end)

    map({ "i", "n" }, "<Down>", function()
        if history_index <= #history then
            history_index = history_index + 1

            local text
            if history_index == #history + 1 then
                text = current_input
            else
                text = history[history_index]
            end

            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
            vim.api.nvim_win_set_cursor(win, { 1, #text })
        end
    end)

    -- Completion (Tab)
    -- Set CWD locally for this window so native file completion works
    if opts.cwd and opts.cwd ~= "" then
        vim.api.nvim_win_call(win, function()
            vim.cmd.lcd(opts.cwd)
        end)
    end

    -- Map Tab to native file completion (<C-x><C-f>)
    map("i", "<Tab>", function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-f>", true, false, true), "n", true)
    end)
end

return M
