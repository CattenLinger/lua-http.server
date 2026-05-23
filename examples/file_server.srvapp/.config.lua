
local lfs = require'lfs'

local log = require'log'()
local Cache = require'lib.cache'.install_cleaner()

local resolve_controller = (function()
    local path = CONFIG:resolve_handler('controllers')..'/'
    return function(name) return path..name..'.lua' end
end)()

-- Handler caches
local cache = Cache.new { }
Cache.cleaner.register { 'handlers', function() return cache end }

-- Template caches
local templates = require'lib.pages' {
    path=CONFIG:resolve_handler('pages')
}
Cache.cleaner.register { 'templates', function() return templates.cache end }

-- Export a template getter as name 'pages'
pages = function(name)
    local p, e = templates('/'..name)
    if not p then error('Load template '..name..'failed: '..e) end

    -- Render other template in place
    local function include(n, model)
        local t, err = templates('/'..n)
        if not t then error('include"'..n..'" in "'..name..'" failed: '..err) end
        log:trace("[Template] Include '%s' from '%s'", n, name)
        local buf = {}
        t(model, function(c) table.insert(buf, c) end)
        return table.concat(buf)
    end

    return function(model)
        model = model or {}
        -- set the include method in model to allow it find other templates
        -- it's recommended to copy values or overlay model between calls
        model.include = function(n, nm)
            if nm then nm.include = model.include end
            return include(n, nm or model)
        end
        return function(w) return p(model, w) end
    end
end

--- Load handler code by name
---
--- @param name string handler name
--- @return table { handler, _ENV, factory }
local function load_handler(name)
    local path = resolve_controller(name)
    local env = setmetatable({}, { __index=_ENV })
    local factory, err = loadfile(path, 't', env) -- load codes
    if not factory and err then return nil, err end;
    -- execute the code to get a handler
    local handler = factory()
    if type(handler) ~= 'function' then
        return nil, 'controller file does not return a function: '..name
    end
    return { handler, env, factory }
end

-- detect file type using lfs and set `file_type`
-- in request context
local function detect_file_type(request)
    local real_path = request.real_path
    if not real_path then return end
    request.file_type = lfs.attributes(request.real_path, "mode")
end

local function on_reply(_, _, request, response)
    detect_file_type(request)
    local name = request.file_type or ''
    if name == '' then name = 'not_found'; end

    -- Dynamically load handler codes
    local res, err = cache:get_or_computed(name, load_handler)
    if not res and err then
        error('Fail to load handler "'..name..'". '..err)
    end
    if res then return res[1](request, response) end
end

return on_reply