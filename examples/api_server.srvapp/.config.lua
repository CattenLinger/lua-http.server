local log = require'log'()
local lfs = require'lfs'
local Cache = require'lib.cache'.install_cleaner()

local cache = Cache.new { }
Cache.cleaner.register { 'handlers', function() return cache end }

local resolve_action = (function()
    local api_path = CONFIG:resolve_handler('api')
    return function(path)
        return api_path..'/'..path..'.lua'
    end
end)()

local function load_action(action_path)
    local attr = lfs.attributes(action_path, "mode")
    if not attr then return nil, 'access denied' end
    if attr ~= 'file' then return nil, 'not a regular file' end
    local newenv = setmetatable({ log=log }, { __index=_ENV })
    local func, err = loadfile(action_path, 't', newenv)
    if not func then return nil, err end;
    return { func, env }
end

local function on_notfound(request, response)
    log:info("Could not load action '%s': %s", table.unpack(request.model))
    response:status(404)
            :content_type('text/plain;charset=utf-8')
            :finish()
end

local function on_reply(request, response)
    local action = request.path;
    log:debug('Call [%s] %s', request.method, action)
    local file_path = resolve_action(action)
    local code, err = cache:get_or_computed(file_path, load_action)
    if not code then
        request.model = { file_path, err }
        return on_notfound(request, response)
    end

    local ok
    ok, err = pcall(code[1], request, response)
    if ok then return end

    log:error('Execute action %s failed: %s', action, err)
    response:status(500)
            :content_type('text/plain;charset=utf-8')
            :finish()
    return
end

return function(_, _, ...) return on_reply(...) end