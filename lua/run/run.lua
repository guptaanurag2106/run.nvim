local utils = require("run.utils")
local M = {}

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
        vim.fn.setqflist({ result.stdout, result.stderr }, "r")
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
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == window_name then
            -- If buffer is valid, check if it's in a window
            for _, win in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_get_buf(win) == buf then
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
                    return buf, win
                end
            end

            vim.cmd("botright 15new")
            local win = vim.api.nvim_get_current_win()
            vim.api.nvim_win_set_buf(win, buf)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
            return buf, win
        end
    end

    vim.cmd("botright 15new")
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()

    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = ''
    vim.bo[buf].buflisted = true
    vim.bo[buf].swapfile = false
    vim.api.nvim_buf_set_name(buf, window_name)

    local group = vim.api.nvim_create_augroup("RunNvim_BufferCloseHandler", { clear = true })

    -- Set up an autocommand for the BufDelete event
    vim.api.nvim_create_autocmd("BufDelete", {
        group = group,
        buffer = buf,
        callback = function()
            M.stop_job(M.job_id)
        end,
    })

    return buf, win
end
M.job_id = nil

M.run_async = function(cmd, curr_dir, populate_qflist, open_qflist)
    if M.job_id ~= nil then
        print("\nA previous command is already running, please exit and run again")
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
            if #data == 0 then
                return
            end

            vim.schedule(function()
                if not vim.api.nvim_buf_is_loaded(buf) then
                    return
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

                if populate_qflist then
                    table.insert(qf_list, { text = table.concat(data, "\n") })
                end
            end)
        end,
        on_stderr = function(_, data)
            if not data or #data == 0 then
                return
            end
            vim.schedule(function()
                if not vim.api.nvim_buf_is_loaded(buf) then
                    return
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

                if populate_qflist then
                    table.insert(qf_list, { text = table.concat(data, "\n") })
                end
            end)
        end,
        on_exit = function(_, exit_code)
            vim.schedule(function()
                M.job_id = nil
                if vim.api.nvim_buf_is_loaded(buf) then
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
                        "Command finished. Press 'q' to exit"
                    })
                    vim.hl.range(buf, ns_id, "Comment", { line_count + 1, 0 }, { line_count + 2, -1 },
                        { inclusive = true })
                    vim.api.nvim_win_set_cursor(win, { line_count + 2 - 1, 0 })

                    if exit_code ~= 0 then
                        vim.api.nvim_set_current_win(win)
                    end
                end
                if populate_qflist then
                    vim.fn.setqflist(qf_list, "r")
                end
                if open_qflist then
                    vim.cmd("copen")
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

M.stop_job = function(job_id)
    if job_id then
        vim.fn.jobstop(job_id)
    end
end

return M
