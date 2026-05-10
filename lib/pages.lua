local template = require"template"
local search_jump_table = require'utils'.search_jump_table
--[[
    Page Manager
]]--
local M = { path="" }

local DefaultOptions = setmetatable({}, {
    __index    = { minify=false, no_cache=false };
    __newindex = function() error('DefaultOptions is readonly') end;
})
M.DefaultOptions = DefaultOptions

local template_cache = {}

local template_type_of do

    local suffix_mapping = {
        ['']      = function(file_path, options)
            local fd, e = io.open(file_path, 'r')
            if not fd then error('fail to open text template: ' .. tostring(e)); end
            local v = template.compile(fd:read'a', options.minify)
            fd:close()
            return v
        end;
        ['.ltpl'] = '';
        ['.html'] = '';

        ['.lua']  = function (file_path)
            local fd, e = io.open(file_path, 'r')
            if not fd then error('fail to open script template: ' .. tostring(e)); end
            print('Loaded compiled lua script: ' .. file_path)
            local v = load(fd:read'a', file_path, 't')()
            fd:close()
            return v
        end;
    }
    
    template_type_of = function(name)
        print("Template name: " .. name)
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
    return function(data, callback)
        template.print(render, data, callback)
    end, path
end

function M.flush_cache()
    template_cache = {}
end

function M.load(self, name, options)
    local render
    options = options or DefaultOptions
    if options.no_cache then goto rawload; end

    render = template_cache[name]
    if not render then goto rawload; end
    if (not self.cache_ttl or ((os.clock() - render.birth) < M.cache_ttl)) then
        return render.render;
    end

    ::rawload::
    local path
    render, path = self:load_raw(name, options)
    template_cache[name] = {render=render, birth=os.clock(), path=path}
    return render
end

return function(options)
    return setmetatable(options or {}, {
        __index = M;
        __call = function(...) return M.load(...) end;
    })
end