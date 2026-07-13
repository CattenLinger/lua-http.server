-- New feature: an app configurator will be pass to arguments
local app_path, app_cfg, app_meta = ...

local lfs = require'lfs'
local log = require'log'()
local os  = require'utils'.os

local Cache = require'lib.cache'.install_cleaner()
Application = {
    webroot = os.path(app_cfg.webroot or critical('webroot is required. Please specify the `--webroot` or `-d` option.'));
    apphome = os.path(app_path);

    configuration = app_cfg;
}
Logger:info('[File App] Serving at directory "%s"', Application.webroot)

local resolver = os.path(app_path)
resolve = setmetatable({
    webroot = Application.webroot;
    apphome = Application.apphome;
}, {
    __index = function(self, key)
        rawset(self, key, resolver(key))
        return rawget(self, key)
    end;
    __call = function(self, ...) return os.resolve(...) end
})

-- Handler caches
local cache = Cache.new { cache_ttl=1 }
Cache.cleaner.register { 'handlers', function() return cache end }

-- Template caches
local templates = require'lib.pages' {
    path = tostring(resolve.pages())
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
--- @return table
local function load_handler(name)
    local path = resolve.controllers:resolve(name) .. '.lua'
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
    local path = request.path_decoded
    if not path then return end
    
    local file_info = request.file_info
    path = resolve.webroot:resolve(path)
    file_info.path = path
    file_info.type = lfs.attributes(path, "mode")
end

local function on_reply(_, _, request, response)
    local file_info = {}; request.file_info = file_info;

    detect_file_type(request)

    local name = file_info.type or ''
    if name == '' then name = 'not_found'; end

    -- Dynamically load handler codes
    local res, err = cache:get_or_computed(name, load_handler)
    if not res and err then
        error('Fail to load handler "'..name..'". '..err)
    end
    if res then return res[1](request, response) end
end

return on_reply