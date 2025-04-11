local utils = require("run.utils")
local M = {}

M.run_sync_new = function(cmd)
    cmd = utils.split(cmd, " ")
    -- Using newer vim.system API (Neovim 0.10+)
    local result = vim.system(cmd):wait()

    -- Handle results
    vim.notify(result.stdout, vim.log.levels.INFO)
    vim.notify(result.stderr, vim.log.levels.ERROR)
    if result.code == 0 then
        vim.notify("\nCommand succeeded", vim.log.levels.INFO)
    else
        vim.notify("\nCommand failed with code: " .. result.code, vim.log.levels.ERROR)
    end
end

M.run_async = function(cmd)
    cmd = utils.split(cmd, " ")

    -- Using vim.fn.jobstart
    local stdout = {}
    local stderr = {}

    local job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data, _)
            for _, line in ipairs(data) do
                -- if line ~= "" then
                table.insert(stdout, line)
                -- end
            end
        end,
        on_stderr = function(_, data, _)
            for _, line in ipairs(data) do
                -- if line ~= "" then
                table.insert(stderr, line)
                -- end
            end
        end,
        on_exit = function(_, exit_code, _)
            if #stdout > 0 then
                vim.notify(table.concat(stdout, "\n"), vim.log.levels.INFO)
            end
            if #stderr > 0 then
                vim.notify(table.concat(stderr, "\n"), vim.log.levels.ERROR)
            end
            if exit_code == 0 then
                vim.schedule(function()
                    vim.notify("\nCommand completed successfully", vim.log.levels.INFO)
                end)
            else
                vim.schedule(function()
                    vim.notify("\nCommand failed with exit code: " .. exit_code, vim.log.levels.ERROR)
                end)
            end
        end
    })

    return job_id
end

M.run_async_new = function(cmd)
    cmd = utils.split(cmd, " ")
    vim.system(cmd, {
        text = true, -- Return text instead of bytes
    }, function(result)
        vim.notify(result.stdout, vim.log.levels.INFO)
        vim.notify(result.stderr, vim.log.levels.ERROR)
        if result.code == 0 then
            vim.notify("\nCommand succeeded", vim.log.levels.INFO)
        else
            vim.notify("\nCommand failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
        end
    end)
end

M.run_term = function(cmd)
    -- Open a terminal buffer and run the command
    vim.cmd("botright new | terminal " .. cmd)
end

return M
