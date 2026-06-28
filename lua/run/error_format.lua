--- Error format matching for compiler/tool output.
--- Taking patterns from Emacs' compilation patterns
---     https://github.com/emacs-mirror/emacs/blob/master/etc/compilation.txt

--- WARN: Some of these regexes and patterns have been written by AI

local M = {}

local function is_valid_filename(str)
    if not str or str == "" then
        return false
    end
    -- Must not be purely numeric
    if str:match("^%d+$") then
        return false
    end
    local basename = str:match("([^/\\]+)$") or str
    -- Basename must contain at least one letter
    if not basename:match("%a") then
        return false
    end
    -- If bare name (no separators), must not start with dash (likely a flag)
    if not str:match("[/\\]") and basename:match("^%-") then
        return false
    end
    -- Basename must not contain brackets (make error artifacts, etc.)
    if basename:match("[%[%]]") then
        return false
    end
    -- Basename must not contain quotes or pipes (diff/string literals)
    if basename:match("[\"|]") then
        return false
    end
    -- If has separators, must not end with one
    if str:match("[/\\]$") then
        return false
    end
    -- If filename is 'zsh'
    if str:match("zsh") then
        return false
    end
    return true
end

---Matches singular line against list of regexes for pattern of error report
---@param line string
---@return table|nil {file, lnum, col, text, loc_start, loc_end}
M.match = function(line)
    do
        -- Generic filename:line:col: msg
        local file, lnum, col, msg =
            line:match("^(.-):(%d+):(%d+):%s*(.+)$")
        if file and lnum and col and msg and is_valid_filename(file) then
            return {
                file = file,
                lnum = lnum,
                col = col,
                text = msg,
                loc_start = 0,
                loc_end = #file + #lnum + #col + 3,
            }
        end
    end

    do
        -- Clang sanitizer frame:     #0 0x558c87a3dde1 in compare /path/file.c:19:12
        local file, lnum, col =
            line:match("^%s*#%d+%s+0x[0-9a-fA-F]+%s+in%s+.*%s+(/%S+):(%d+):(%d+)$")
        if file and lnum and col then
            local loc_start = line:find(file, 1, true) - 1
            return {
                file = file,
                lnum = lnum,
                col = col,
                text = "",
                loc_start = loc_start,
                loc_end = loc_start + #file + #lnum + #col + 2,
            }
        end
    end

    do
        -- Clang sanitizer frame (with msg):     #0 0x... in foo /path/file.c:19: msg here
        local file, lnum, msg =
            line:match("^%s*#%d+%s+0x[0-9a-fA-F]+%s+in%s+.*%s+(/%S+):(%d+):%s*(.+)$")
        if file and lnum and msg then
            local loc_start = line:find(file, 1, true) - 1
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = msg,
                loc_start = loc_start,
                loc_end = loc_start + #file + #lnum + 1,
            }
        end
    end

    do
        -- Clang sanitizer frame (bare line):     #0 0x... in foo /path/file.c:19
        local file, lnum = line:match("^%s*#%d+%s+0x[0-9a-fA-F]+%s+in%s+.*%s+(/%S+):(%d+)$")
        if file and lnum then
            local loc_start = line:find(file, 1, true) - 1
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = "",
                loc_start = loc_start,
                loc_end = loc_start + #file + #lnum + 1,
            }
        end
    end

    do
        -- Clang sanitizer SUMMARY:     SUMMARY: MemorySanitizer: use-of-uninit /path/file.c:19:12 in ...
        local file, lnum, col = line:match("^SUMMARY:[^/]+(/[^:]+):(%d+):(%d+)")
        if file and lnum and col then
            local loc_start = line:find(file, 1, true) - 1
            return {
                file = file,
                lnum = lnum,
                col = col,
                text = "",
                loc_start = loc_start,
                loc_end = loc_start + #file + #lnum + #col + 2,
            }
        end
    end

    do
        -- Lua: /usr/bin/lua: database.lua:31: assertion failed!
        local exec, file, lnum, msg =
            line:match("^(.-):%s*([^:]-%.[^:]+):(%d+):%s*(.+)$")
        if exec and file and lnum and msg then
            local loc_start = line:match("^.-:%s*()") - 1
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = msg,
                loc_start = loc_start,
                loc_end = loc_start + #file + 1 + #lnum,
            }
        end
    end

    do
        -- Lua stack traceback: database.lua:31: in field 'statement'
        local file, lnum, msg =
            line:match("^(.-):(%d+):%s*in%s+(.+)$")
        if file and lnum and msg then
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = msg,
                loc_start = 0,
                loc_end = #file + #lnum + 2,
            }
        end
    end

    do
        -- Go panic: \t/tmp/main.go:4 +0x25
        local file, lnum =
            line:match("^%s*([^:]+):(%d+)%s*%+[0-9a-fA-Fx]+$")
        if file and lnum then
            local loc_start = line:match("^%s*()") - 1
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = "",
                loc_start = loc_start,
                loc_end = loc_start + #file + 1 + #lnum,
            }
        end
    end

    do
        -- Go test:     foo_test.go:42: expected X, got Y
        local file, lnum, msg =
            line:match("^%s*([^:]+%.go):(%d+):%s*(.+)$")
        if file and lnum and msg then
            local loc_start = line:match("^%s*()") - 1
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = msg,
                loc_start = loc_start,
                loc_end = loc_start + #file + 1 + #lnum + 1,
            }
        end
    end

    do
        -- Generic filename:line: msg
        local file, lnum, msg =
            line:match("^(.-):(%d+):%s*(.+)$")
        if file and lnum and msg and is_valid_filename(file) then
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = msg,
                loc_start = 0,
                loc_end = #file + #lnum + 2,
            }
        end
    end

    do
        -- gcc include
        local file, lnum, col =
            line:match("^%s*from%s+([^:]+):(%d+):(%d+),?%s*$")

        if file and lnum and col then
            local loc_start = line:find(file, 1, true) - 1
            return {
                file = file,
                lnum = lnum,
                col = col,
                text = "",
                loc_start = loc_start,
                loc_end = loc_start + #file + #lnum + #col + 2,
            }
        end
        do
            local file2, lnum2 =
                line:match("^%s*from%s+([^:]+):(%d+):%s*$")

            if file2 and lnum2 then
                local loc_start = line:find(file2, 1, true) - 1
                return {
                    file = file2,
                    lnum = lnum2,
                    col = "0",
                    text = "",
                    loc_start = loc_start,
                    loc_end = loc_start + #file2 + #lnum2 + 1,
                }
            end
        end
    end

    do
        -- Python
        -- Traceback (most recent call last):
        --   File "/tmp/test.py", line 1, in <module>
        --     prin("asdf")
        --     ^^^^
        -- NameError: name 'prin' is not defined. Did you mean: 'print'?
        local file, lnum, msg =
            line:match('^%s*File "?([^",]+)"?, line (%d+),?%s*(.*)$')

        if file and lnum then
            local _, loc_end = line:find('^%s*File "?[^",]+"?, line %d+')
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = msg,
                loc_start = 0,
                loc_end = loc_end,
            }
        end
    end

    do
        -- Java
        -- Exception in thread "main" java.lang.Exception: e
        --         at Main.temp(Main.java:3)
        --         at Main.main(Main.java:6)
        local file, lnum =
            line:match("^%s*at%s+.-%(([^:]+):(%d+)%)$")

        if file and lnum then
            local loc_start = line:find("%(") -- 1-based
            loc_start = loc_start and (loc_start) or 0
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = "",
                loc_start = loc_start,
                loc_end = loc_start + #file + #lnum + 1,
            }
        end
    end

    do
        -- Bash
        -- /tmp/bash.sh: line 1: asd: command not found
        -- local file, lnum, col = line:match("^%s*at%s+([^:]+):(%d+):(%d+)%s*$")
        local file, lnum, msg = line:match("^(.-): line (%d+): (.+)$")
        if file and lnum and msg then
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = msg,
                loc_start = 0,
                loc_end = #file + #lnum + 8,
            }
        end
    end

    do
        -- Ocaml
        -- File "foobar.ml", lines 5-8, characters 20-155: blah blah
        local file, lnum, col, msg =
            line:match('^File "([^"]+)", lines (%d+)%-%d+, characters (%d+)%-%d+:%s*(.+)$')
        if file and lnum and col and msg then
            return {
                file = file,
                lnum = lnum,
                col = col,
                text = msg,
                loc_start = 0,
                loc_end = line:find(":%s", 1) - 1,
            }
        end
    end

    do
        -- Ocaml
        -- File "F:\ocaml\sorting.ml", line 65, characters 2-145:
        local file, lnum, col =
            line:match('^File "([^"]+)", line (%d+), characters (%d+)%-%d+:%s*$')
        if file and lnum and col then
            return {
                file = file,
                lnum = lnum,
                col = col,
                text = "",
                loc_start = 0,
                loc_end = #line,
            }
        end
    end

    do
        -- Valgrind
        -- ==1332==    at 0x4040743C: System::getErrorString() (../src/Lib/System.cpp:217)
        local file, lnum =
            line:match("^==%d+==%s+at .-%(([^:]+):(%d+)%)$")

        if file and lnum then
            local loc_start = line:find("%(")
            return {
                file = file,
                lnum = lnum,
                col = "0",
                text = "",
                loc_start = loc_start and (loc_start - 1) or 0,
                loc_end = (loc_start and (loc_start - 1) or 0) + #file + #lnum + 1,
            }
        end
    end
    return nil
end

---Convenience wrapper around `match()` for `append_to_qflist`.
---@param line string
---@return table|nil  { entry = {filename,lnum,col,text}, location = {start,finish} }
M.to_qf_entry = function(line)
    local m = M.match(line)
    if not m then
        return nil
    end
    local entry = {
        filename = m.file,
        lnum = tonumber(m.lnum),
        col = tonumber(m.col),
        text = m.text,
    }
    local location = {
        start = m.loc_start,
        finish = m.loc_end,
    }
    return { entry = entry, location = location }
end

return M
