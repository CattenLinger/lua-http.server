--[[ Server response wrapper ]]
local table          = require'utils'.table
local http_util      = require'http.util'
local new_headers    = require'http.headers'.new
local http_version   = require'http.version'
local default_server = string.format("%s/%s", http_version.name, http_version.version)

local function get_is_finished(self)
    return (self['.finish'] or {})[1] or false
end

local function assert_context_not_finished(self)
    if get_is_finished(self)
    then error('try to act on a finished context', 3)
    end
end

local function create_new_header(self)
    assert_context_not_finished(self)

    local headers = new_headers()
    headers:append("server", default_server)
    headers:append("date", http_util.imf_date())
    return headers
end

local function set_content_type(self, ct)
    assert_context_not_finished(self)
    self.headers:append('content-type', tostring(ct))
    return self
end

local function set_status(self, st)
    assert_context_not_finished(self)
    self.headers:append(":status", tostring(st))
    return self
end

local function add_header(self, key, value)
    assert_context_not_finished(self)
    self.headers:append(key:lower(), tostring(value))
    return self
end

--[[
    Various finish methods
--]]

local function _finish_userdata(stream, userdata)
    return { true; function()
        stream:write_body_from_file(userdata)
        userdata:close()
    end }
end

local function _finish_values(stream, value, args)
    if not value then
        return {true; function()
            stream:write_chunk('', true)
        end}
    end
    if #args <= 0 then
        return {true; function()
            stream:write_chunk(tostring(value), true)
        end}
    end
    return {true; function()
        stream:write_chunk(tostring(value), false)
        if not args then goto close end
        for _, k in ipairs(args) do
            stream:write_chunk(tostring(k), false)
        end
        ::close::
        stream:write_chunk('', true)
    end}
end

local function _finish_writer(stream, acceptor, args)
    local writer = function(chunk)
        return stream:write_chunk(chunk, false)
    end
    return { true; function()
        acceptor(writer, table.unpack(args))
        stream:write_chunk('', true)
    end }
end

local function finish(self, value, ...)
    assert_context_not_finished(self)

    local stream = self.stream
    local args = table.pack(...)

    local value_t = type(value)
    if value_t == 'userdata'        -- if is a file
    then self['.finish'] = _finish_userdata(stream, value)
    elseif value_t == 'function'    -- if is a function
    then self['.finish'] = _finish_writer(stream, value, args)
    else self['.finish'] = _finish_values(stream, value, args)
    end
end

local getters = {
    -- Properties
    headers      = create_new_header;
    -- Methods
    is_finished  = function() return get_is_finished  end;
    content_type = function() return set_content_type end;
    status       = function() return set_status end;
    header       = function() return add_header end;
    finish       = function() return finish end;
}
local __mt = { __index=getters }

return function (server, stream)
    return table.lazy(setmetatable({
        stream       = stream;
    }, __mt ))
end