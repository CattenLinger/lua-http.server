local template = require"lib.template"

--[[ Page Manager ]]
local M = { path="pages/" }
local DefaultOptions = setmetatable({}, {
    __index    = { minify=false, no_cache=false, };
    __newindex = function() error('DefaultOptions is readonly') end;
})
M.DefaultOptions = DefaultOptions

local template_type_of do
    local search_jump_table = require'utils'.search_jump_table

    local suffix_mapping = {
        -- Text Template
        ['']      = function(file_path, options)
            local fd, e = io.open(file_path, 'r')
            if not fd then error('fail to open text template: ' .. tostring(e)); end
            local v = template.compile(fd:read'a', options.minify)
            fd:close()
            return v
        end;
        ['.ltpl'] = '';
        ['.html'] = '';

        -- Function Template
        ['.lua']  = function (file_path)
            local v, e = loadfile(file_path, 't')()
            if not v then error('fail to open script template: ' .. tostring(e)); end
            print('Loaded compiled lua script: ' .. file_path)
            return v
        end;
        ['.luac'] = '.lua';
    }
    
    template_type_of = function(name)
        local suffix = string.match(name, "%.[^%.]*$") or ''
        return search_jump_table(suffix_mapping, suffix)
    end
    
end

function M.load_raw(self, name, options)
    options = options or DefaultOptions
    -- path + name, load via suffix
    local loader, typename = template_type_of(name)
    if not loader then error('could not find suitable loader'); end

    local path = self.path .. name
    local render = loader(path, options)
    return (function(data, callback) template.print(render, data, callback); end), path
end

function M.evict_cache(self)
    if not self.cache then return nil; end
    return self.cache:evict_cache()
end

function M.load(self, name, options)
    local render
    options = options or DefaultOptions

    local no_cache = options.no_cache or (not self.cache)
    if no_cache then goto rawload; end

    render = self.cache(name)
    if not render then goto rawload; end

    ::rawload::
    local path
    render, path = self:load_raw(name, options)
    if not no_cache then
        self.cache:put(name, {render=render, path=path}); 
    end
    return render
end

--[[
avaliable options:
- path:     string, template directory path
- no_cache: boolean, use cache or not
]]--
return function(options)
    local data = options or {}
    if not data.no_cache then
        data.cache = require'lib.cache'.new(data.cache_options or {})
    end
    setmetatable(data, {
        __index = M;
        __call = function(...) return M.load(...) end;
    })
    if string.sub(data.path, #data.path-1) ~= '/' then
        data.path = data.path..'/'
    end
    return data
end