local utils = require("run.utils")
local M = {}

M.stop_job = function(job_id)
    if job_id then
        vim.fn.jobstop(job_id)
        M.job_id = nil
    end
end

local parse_qf_list = function(data)
    local entries = {}

    for _, line in ipairs(data) do
        local filename, lnum, col, message = string.match(line, "(.-):(%d+):(%d+):(.*)")
        if filename and lnum and col then
            lnum = tonumber(lnum)
            col = tonumber(col)

            local entry = {
                filename = filename,
                lnum = lnum,
                col = col,
                text = message
            }

            table.insert(entries, entry)
        end
    end

    return entries
end

M.run_sync = function(cmd, curr_dir, populate_qflist, open_qflist)
    cmd = utils.split(cmd, " ")
    -- Using newer vim.system API (Neovim 0.10+)
    local opts = {
        detach = false,
        cwd = curr_dir
    }
    local result = vim.system(cmd, opts):wait()

    -- Handle results
    vim.notify(result.stdout, vim.log.levels.INFO)
    vim.notify(result.stderr, vim.log.levels.ERROR)
    if result.code == 0 then
        vim.notify("\nCommand succeeded", vim.log.levels.INFO)
    else
        vim.notify("\nCommand failed with code: " .. result.code, vim.log.levels.ERROR)
    end

    if populate_qflist then
        vim.fn.setqflist(parse_qf_list({ result.stdout, result.stderr }), "r")
    end

    if open_qflist then
        vim.cmd('copen')
    end
end

-- M.run_async_new = function(cmd)
--     cmd = utils.split(cmd, " ")
--     vim.system(cmd, {
--         text = true, -- Return text instead of bytes
--     }, function(result)
--         vim.notify(result.stdout, vim.log.levels.INFO)
--         vim.notify(result.stderr, vim.log.levels.ERROR)
--         if result.code == 0 then
--             vim.notify("\nStatus: Completed Successfully (exit code 0)", vim.log.levels.INFO)
--         else
--             vim.notify("\nStatus: Completed Successfully (exit code " .. result.code .. ")",
--                 vim.log.levels.ERROR)
--         end
--     end)
-- end

local create_reuse_win = function(window_name)
    local orig_win = vim.api.nvim_get_current_win()
    local buf
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b)
            and vim.api.nvim_buf_get_name(b) == window_name then
            buf = b
            break
        end
    end

    if not buf then
        buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, window_name)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "hide"
        vim.bo[buf].swapfile = false
        vim.bo[buf].modifiable = true
    end

    local existing_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win)
            and vim.api.nvim_win_get_buf(win) == buf then
            existing_win = win
            break
        end
    end

    local win
    if existing_win then
        win = existing_win
    else
        vim.cmd("botright 15split")
        win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
    end
    local group = vim.api.nvim_create_augroup("RunNvim_BufferCloseHandler", { clear = true })

    -- Set up an autocommand for the BufDelete event
    vim.api.nvim_create_autocmd("BufDelete", {
        group = group,
        buffer = buf,
        callback = function()
            M.stop_job(M.job_id)
        end,
    })
    vim.api.nvim_set_current_win(orig_win)

    return buf, win
end
M.job_id = nil

M.run_async = function(cmd, curr_dir, populate_qflist, open_qflist)
    if M.job_id ~= nil then
        print("\nStopping the previous running command")
        M.stop_job(M.job_id)
        return
    end
    local buf, win = create_reuse_win("run://Command Output")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Running: " .. vim.inspect(cmd),
        "",
        "Output",
        "--------------------------------------------------------------------------------",
        ""
    })

    local ns_id = vim.api.nvim_create_namespace("")


    vim.hl.range(buf, ns_id, "Title", { 0, 0 }, { 0, -1 },
        { inclusive = true })
    vim.hl.range(buf, ns_id, "Special", { 2, 0 }, { 2, -1 },
        { inclusive = true })

    local qf_list = {}
    local start_time = vim.uv.hrtime()

    M.job_id = vim.fn.jobstart(cmd, {
        cwd = curr_dir,
        detach = false,
        on_stdout = function(_, data)
            if not data then
                return
            end

            -- Remove trailing empty line Neovim sometimes adds
            -- if data[#data] == "" then
            --     table.remove(data, #data)
            -- end
            if #data == 0 or not vim.api.nvim_buf_is_loaded(buf) then
                return
            end

            vim.schedule(function()
                if populate_qflist then
                    qf_list = utils.appendTable(qf_list, data)
                end
                local line_count = vim.api.nvim_buf_line_count(buf)
                local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1]
                data[1] = last_line .. data[1]
                for i = 1, #data do
                    -- vim represents null as \n and new line as \r
                    -- https://vim.fandom.com/wiki/Newlines_and_nulls_in_Vim_script
                    data[i] = data[i]:gsub("\n", "")
                end
                vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, data)

                vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
            end)
        end,

        on_stderr = function(_, data)
            if not data or #data == 0 or not vim.api.nvim_buf_is_loaded(buf) then
                return
            end
            vim.schedule(function()
                if populate_qflist then
                    qf_list = utils.appendTable(qf_list, data)
                end
                local line_count = vim.api.nvim_buf_line_count(buf)
                local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1]
                data[1] = last_line .. data[1]
                for i = 1, #data do
                    -- vim represents null as \n and new line as \r
                    -- https://vim.fandom.com/wiki/Newlines_and_nulls_in_Vim_script
                    data[i] = data[i]:gsub("\n", "")
                end
                vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, data)

                vim.hl.range(buf, ns_id, "ErrorMsg", { line_count - 1, 0 }, { line_count + #data - 1, -1 },
                    { inclusive = true })
                vim.api.nvim_win_set_cursor(win, { line_count + #data - 1, 0 })
            end)
        end,

        on_exit = function(_, exit_code)
            vim.schedule(function()
                M.job_id = nil
                if vim.api.nvim_buf_is_loaded(buf) then
                    local end_time = vim.uv.hrtime()

                    local elapsed_time_ns = end_time - start_time
                    local elapsed_time_s = elapsed_time_ns / 1e9
                    local seconds = math.floor(elapsed_time_s)
                    local milliseconds = math.floor((elapsed_time_s - seconds) * 1000)

                    local line_count = vim.api.nvim_buf_line_count(buf)
                    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, {
                        exit_code == 0
                        and "Status: Completed Successfully (exit code 0)"
                        or "Status: Failed (exit code " .. exit_code .. ")"
                    })
                    vim.hl.range(buf, ns_id, exit_code == 0 and 'String' or 'ErrorMsg', { line_count, 0 },
                        { line_count, -1 },
                        { inclusive = true })

                    vim.api.nvim_buf_set_lines(buf, line_count + 1, line_count + 1, false, {
                        "",
                        string.format("Command finished in %d.%03d seconds. Press 'q' to exit", seconds, milliseconds)
                    })
                    vim.hl.range(buf, ns_id, "Comment", { line_count + 1, 0 }, { line_count + 2, -1 },
                        { inclusive = true })
                    vim.api.nvim_win_set_cursor(win, { line_count + 2 - 1, 0 })

                    if exit_code ~= 0 then
                        vim.api.nvim_set_current_win(win)
                    end
                end
                if populate_qflist then
                    vim.fn.setqflist(parse_qf_list(qf_list), "r")
                end
                if exit_code ~= 0 and open_qflist then
                    local ok, trouble = pcall(require, 'trouble')
                    if ok then
                        -- Open Trouble quickfix view
                        trouble.open('quickfix')
                    else
                        -- Fallback to the normal quickfix window
                        vim.cmd('copen')
                    end
                end
            end)
        end,
        stdout_buffered = false,
        stderr_buffered = false
    })

    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':lua require("run")._stop_job(' .. M.job_id .. ') vim.cmd("q")<CR>', {
        noremap = true,
        silent = true
    })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', ':lua require("run")._stop_job(' .. M.job_id .. ')<CR>', {
        noremap = true,
        silent = true
    })
    return M.job_id
end

return M
