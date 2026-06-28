local error_format = require("run.error_format")
local config = require("run.config")
local M = {}
local ns_id = vim.api.nvim_create_namespace("RunNvimOutput")

M.job_id = nil
local qflist_replace_next = false

---Stop a running job by id.
---@return nil
M.stop_job = function()
    if M.job_id and M.job_id > 0 then
        pcall(vim.fn.jobstop, M.job_id)
    end
    M.job_id = nil
end

---Parse lines of text and appends to quickfix list
---@param data table Array of text blocks (stdout/stderr lines)
local append_to_qflist = function(data, populate_qflist)
    local entries = {}
    local locations = {}
    for i, block in ipairs(data) do
        -- \r may not come as a new line so manually split on that
        local lines = vim.split(block, "[\r\n]+", { trimempty = true })
        for _, line in ipairs(lines) do
            local qf_entries = error_format.to_qf_entry(line)
            if qf_entries ~= nil then
                table.insert(entries, qf_entries.entry)
                table.insert(locations, {
                    index = i,
                    start = qf_entries.location.start,
                    finish = qf_entries.location.finish,
                })
            end
        end
    end

    if populate_qflist then
        if qflist_replace_next then
            vim.fn.setqflist(entries, "r")
            qflist_replace_next = false
        else
            vim.fn.setqflist(entries, "a")
        end
    end

    return locations
end

---Run a command synchronously using `vim.system`.
---@param cmd string|table command or list of args
---@param curr_dir string working directory
---@param populate_qflist boolean whether to populate quickfix from output
---@param open_qflist boolean whether to open quickfix on failure
---@return nil
M.run_sync = function(cmd, curr_dir, populate_qflist, open_qflist)
    local cmd_list = { vim.o.shell, vim.o.shellcmdflag, cmd }
    -- Using newer vim.system API (Neovim 0.10+)
    local opts = {
        detach = false,
        cwd = curr_dir,
    }

    local ok, result = pcall(function()
        return vim.system(cmd_list, opts):wait()
    end)

    if not ok then
        vim.notify("Failed to execute command: " .. tostring(result), vim.log.levels.ERROR)
        return
    end

    -- Handle results
    vim.notify(result.stdout, vim.log.levels.INFO)
    vim.notify(result.stderr, vim.log.levels.INFO)
    if result.code == 0 then
        vim.notify("\nCommand succeeded", vim.log.levels.INFO)
    else
        vim.notify("\nCommand failed with code: " .. result.code, vim.log.levels.ERROR)
    end

    if populate_qflist then
        qflist_replace_next = true
        append_to_qflist({ result.stdout, result.stderr }, true)
    end

    if result.code ~= 0 and populate_qflist then
        vim.cmd("silent! cfirst")
    end

    if result.code ~= 0 and open_qflist then
        -- open trouble.nvim quickfix otherwise just copen
        local ok1, trouble = pcall(require, "trouble")
        if ok1 then
            trouble.open("quickfix")
        else
            vim.cmd("copen")
        end
    end
end

---Create or reuse an output buffer/window for command output.
---@param window_name string buffer name to use
---@return number buf, number win
local create_reuse_win = function(window_name)
    local orig_win = vim.api.nvim_get_current_win()
    local buf = vim.fn.bufnr(window_name)

    if buf == -1 then
        buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, window_name)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "hide"
        vim.bo[buf].swapfile = false
        vim.bo[buf].modifiable = true
    end

    local existing_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
            existing_win = win
            break
        end
    end

    local win
    if existing_win then
        win = existing_win
    else
        vim.cmd(config.options.output_window_cmd)
        win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
    end
    local group = vim.api.nvim_create_augroup("RunNvim_BufferCloseHandler", { clear = true })

    -- Set up an autocommand for the BufDelete event
    vim.api.nvim_create_autocmd("BufDelete", {
        group = group,
        buffer = buf,
        callback = function()
            M.stop_job()
        end,
    })
    vim.api.nvim_set_current_win(orig_win)
    vim.b[buf].run_orig_win = orig_win

    return buf, win
end

local on_stream_data = function(buf, win, data, state, populate_qflist, stream_name)
    if not data or #data == 0 or (#data == 1 and data[#data] == "") then
        return
    end

    vim.schedule(function()
        if not vim.api.nvim_buf_is_loaded(buf) then
            return
        end

        if stream_name == "stdout" then
            data[1] = state.stdout_pending .. data[1]
            if #data > 1 then
                state.stdout_pending = data[#data]
                data[#data] = nil
            end
        else
            data[1] = state.stderr_pending .. data[1]
            if #data > 1 then
                state.stderr_pending = data[#data]
                data[#data] = nil
            end
        end

        for i, _ in ipairs(data) do
            -- vim represents NUL characters with \n
            data[i] = data[i]:gsub("\n", "")
        end

        local line_count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count - 1, false, data)

        local highlightLocs = append_to_qflist(data, populate_qflist)
        for _, loc in ipairs(highlightLocs) do
            if stream_name == "stdout" then
                vim.hl.range(buf, ns_id, "DiagnosticInfo", { line_count + loc.index - 2, loc.start },
                    { line_count + loc.index - 2, loc.finish })
                vim.hl.range(buf, ns_id, "Underlined", { line_count + loc.index - 2, loc.start },
                    { line_count + loc.index - 2, loc.finish })
            else
                vim.hl.range(buf, ns_id, "DiagnosticError", { line_count + loc.index - 2, loc.start },
                    { line_count + loc.index - 2, loc.finish })
                vim.hl.range(buf, ns_id, "Underlined", { line_count + loc.index - 2, loc.start },
                    { line_count + loc.index - 2, loc.finish })
            end
        end

        if stream_name == "stderr" and config.options.highlight_stderr_full then
            vim.hl.range(buf, ns_id, "DiagnosticError",
                { line_count - 1, 0 },
                { line_count + #data - 1, -1 })
        end

        local end_line = line_count + #data
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_cursor(win, { end_line, 0 })
        end
    end)
end

local flush_pending_data = function(buf, win, state, populate_qflist)
    on_stream_data(buf, win, { state.stdout_pending },
        { stdout_pending = "", stderr_pending = "" }, populate_qflist, "stdout")
    on_stream_data(buf, win, { state.stderr_pending },
        { stdout_pending = "", stderr_pending = "" }, populate_qflist, "stderr")
end

local should_focus_output_win = function(exit_code)
    local mode = config.options.focus_output
    if mode == "always" then
        return true
    end
    if exit_code ~= 0 and mode == "on_error" then
        return true
    end
    return false
end

---Run a command asynchronously using `jobstart` and stream output to buffer.
---@param cmd string command to run
---@param curr_dir string working directory
---@param populate_qflist boolean whether to collect output for quickfix
---@param open_qflist boolean whether to open quickfix on failure
---@return number|nil job id if started, otherwise nil
M.run_async = function(cmd, curr_dir, populate_qflist, open_qflist)
    if M.job_id ~= nil then
        vim.notify("A command is already running. Please stop it before starting a new one.", vim.log.levels.WARN)
        -- M.stop_job()
        return nil
    end

    local ok_win, buf, win = pcall(create_reuse_win, "run://Command Output")
    if not ok_win then
        vim.notify("Failed to create output window: " .. tostring(buf), vim.log.levels.ERROR)
        M.job_id = nil
        return nil
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Dir: " .. curr_dir,
        "Command: " .. vim.inspect(cmd),
        "",
        "Output",
        "--------------------------------------------------------------------------------",
        "",
    })

    vim.hl.range(buf, ns_id, "Directory", { 0, 0 }, { 0, -1 }, { inclusive = true })
    vim.hl.range(buf, ns_id, "Title", { 1, 0 }, { 1, -1 }, { inclusive = true })
    vim.hl.range(buf, ns_id, "Special", { 3, 0 }, { 3, -1 }, { inclusive = true })

    local start_time = vim.uv.hrtime()

    qflist_replace_next = populate_qflist

    local state = {
        stdout_pending = "",
        stderr_pending = ""
    }

    local job_id = vim.fn.jobstart(cmd, {
        cwd = curr_dir,
        detach = false,
        on_stdout = function(_, data, name)
            on_stream_data(buf, win, data, state, populate_qflist, name)
        end,

        on_stderr = function(_, data, name)
            on_stream_data(buf, win, data, state, populate_qflist, name)
        end,

        on_exit = function(id, exit_code)
            vim.schedule(function()
                if M.job_id == id then
                    M.job_id = nil
                end
                if vim.api.nvim_buf_is_loaded(buf) then
                    flush_pending_data(buf, win, state, populate_qflist)

                    local end_time = vim.uv.hrtime() -- FIX: includes time for parsing inserting etc

                    local elapsed_time_ns = end_time - start_time
                    local elapsed_time_s = elapsed_time_ns / 1e9
                    local seconds = math.floor(elapsed_time_s)
                    local milliseconds = math.floor((elapsed_time_s - seconds) * 1000)

                    local line_count = vim.api.nvim_buf_line_count(buf)
                    local message
                    if exit_code == 0 then
                        message = string.format("Command finished successfully in %d.%03d seconds",
                            seconds, milliseconds)
                    else
                        message = string.format("Command failed with exit code %d in %d.%03d seconds",
                            exit_code, seconds, milliseconds)
                    end

                    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, {
                        message })
                    vim.hl.range(
                        buf,
                        ns_id,
                        exit_code == 0 and "String" or "ErrorMsg",
                        { line_count, 0 },
                        { line_count, -1 },
                        { inclusive = true }
                    )

                    if vim.api.nvim_win_is_valid(win) then
                        vim.api.nvim_win_set_cursor(win, { line_count + 1, 0 })
                    end

                    if should_focus_output_win(exit_code) and vim.api.nvim_win_is_valid(win) then
                        vim.api.nvim_set_current_win(win)
                    end
                end

                if exit_code ~= 0 and populate_qflist then
                    vim.schedule(function()
                        vim.cmd("silent! cfirst")
                    end)
                end

                if exit_code ~= 0 and open_qflist then
                    -- open trouble.nvim quickfix otherwise just copen
                    local ok, trouble = pcall(require, "trouble")
                    if ok then
                        trouble.open("quickfix")
                    else
                        vim.cmd("copen")
                    end
                end
            end)
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if job_id <= 0 then
        vim.notify("Failed to start command: " .. cmd, vim.log.levels.ERROR)
        M.job_id = nil
        return nil
    end
    M.job_id = job_id

    vim.keymap.set("n", "<CR>", function()
        local m = error_format.match(vim.api.nvim_get_current_line())
        if m then
            local target_win = vim.b.run_orig_win
            if target_win and vim.api.nvim_win_is_valid(target_win) then
                vim.api.nvim_set_current_win(target_win)
            end
            vim.cmd(string.format("edit +%d %s", tonumber(m.lnum), m.file))
            if tonumber(m.col) > 0 then
                vim.api.nvim_win_set_cursor(0, { tonumber(m.lnum), tonumber(m.col) - 1 })
            end
        end
    end, { buffer = buf, noremap = true, silent = true })

    vim.keymap.set("n", "q", function()
        M.stop_job()
        vim.cmd("q")
    end, { buffer = buf, noremap = true, silent = true })

    vim.keymap.set("n", "<C-c>", function()
        M.stop_job()
    end, { buffer = buf, noremap = true, silent = true })

    return M.job_id
end

return M
