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
        border = config.options.ui.border,
    }

    local win = vim.api.nvim_open_win(buf, true, win_opts)

    local lines = {}
    if opts.history then
        for _, item in ipairs(opts.history) do
            table.insert(lines, item)
        end
    end

    if #opts.default > 0 then
        table.insert(lines, opts.default)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local function apply_prompt()
        if not opts.prompt then return end

        local prompt_text = opts.prompt
        if string.sub(prompt_text, -1) ~= " " then
            prompt_text = prompt_text .. " "
        end

        local ns_id = vim.api.nvim_create_namespace("run_input")
        vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

        local line_count = vim.api.nvim_buf_line_count(buf)
        for i = 0, line_count - 1 do
            vim.api.nvim_buf_set_extmark(buf, ns_id, i, 0, {
                virt_text = { { prompt_text, config.options.ui.prompt_hl } },
                virt_text_pos = "inline",
                right_gravity = false,
            })
        end
    end

    apply_prompt()

    -- Re-apply prompt on text change (e.g., adding new lines)
    local group = vim.api.nvim_create_augroup("RunInputPrompt", { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = apply_prompt,
        group = group,
    })

    if #lines > 0 then
        vim.api.nvim_win_set_cursor(win, { #lines, #lines[#lines] })
    end

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "run_input"

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    local map = function(mode, lhs, rhs)
        vim.keymap.set(mode, lhs, rhs, { buffer = buf, nowait = true, silent = true })
    end

    map({ "i", "n" }, "<CR>", function()
        local line = vim.api.nvim_get_current_line()
        vim.cmd("stopinsert")
        close()
        on_confirm(line)
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

    -- Set CWD locally for this window so native file completion works
    if opts.cwd and opts.cwd ~= "" then
        vim.api.nvim_win_call(win, function()
            vim.cmd.lcd(opts.cwd)
        end)
    end
end

return M
