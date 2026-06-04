local table = require'utils'.table

local function bad_request(response, msg)
    response:status(400)
            :content_type('text/plain;charset=utf-8')
            :finish('Bad request: '..msg or '')
end

local function internal_server_error(response, msg)
    response:status(500)
            :content_type('text/plain;charset=utf-8')
            :finish('Internal server error: '..msg or '')
end

local command_mappings = {
    ls     = function() return 'ls -alh .' end;
    ffmpeg = function() return 'ffmpeg --help 2>&1'  end;
}

return function (request, response)
    local queries = table.from_entries(request.query)
    local command = queries['cmd']
    if not command then return bad_request(response, 'command required') end
    local script = command_mappings[command]
    if not script then return bad_request(response, 'unknown command') end

    local exec = script()
    local fd, err = io.popen(exec)
    if not fd then return internal_server_error(response, err) end
    log:info("Start execute: %s", exec)
    local function bulk_stdout(writer)
        local ok, bulk_err = pcall(function()
            ::bulk::
            local buff, buff_err = fd:read(128)
            if not buff then goto finish end
            writer(buff)
            goto bulk
            ::finish::
            if buff_err then error(buff_err) end
        end)

        local state, exit_code = fd:close()
        log:info('Command `%s` finished, success: %s, exit code: %s',
                 exec, tostring(state), tostring(exit_code))

        if not ok then error(bulk_err) end
    end

    response:status(200)
            :content_type('text/plain;charset=utf-8')
            :finish(bulk_stdout)
end