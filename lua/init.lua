--[[
    lua-http.server Init
    
    If there has any bootloader methods, they should live inside `package`.
    After the bootstrapping, the standard `package` field will be unaccessable,
    and replaced by a dummy.

    This file both used by the embedded and non-embedded version of lua-http.server.
    In embedded version, after starts, the key `package.chunks.core.init` should be remove, 
    to prevent unintentional access.
--]]
local package_   = package;
local require_   = require;

-- indicating if it is launchs from binary bundle
-- codes of binary bundles will be store under `package.chunks`
local is_embedded = (package_.chunks ~= nil)

local homedir = assert(os.getenv('LUA_HTTP_SERVER_HOME_DIR'), 'LUA_HTTP_SERVER_HOME_DIR Missing')
if is_embedded then
    --
    -- load core codes
    --
    -- embedded codes are store under package.chunks
    -- entry is named `server` under `core`
    local core_chunks  = package_.chunks.core
    local loader_chunk = assert(core_chunks.loader, 'unexpected chunk "core.loader" not found')
    local entry_chunk  = assert(core_chunks.server, 'unexpceted chunk "core.init" not found')
    core_chunks.init   = nil; --[[ not needed ]]
    core_chunks.server = nil; --[[ not needed ]]
    
    -- loader should be loaded before anything
    package_.loaded['loader'] = assert(load(loader_chunk, 'core.loader', 'bt', _ENV))('loader')
    package_.cpath = string.format("%s/lib/?.so;%s", homedir, package_.cpath)
    package_.entry = assert(load(entry_chunk, 'core.init', "bt", _ENV)); 

    --
    -- register vendor preloads
    --
    local vendor_chunks = package_.chunks.vendor
    local preload_indexer = function(self, key)
        local chunk = vendor_chunks[key] if not chunk then return nil end
        local loader = assert(load(chunk, 'vendor.'..key, "bt", _ENV))
        rawset(self, key, loader)
        return loader
    end
    setmetatable(package_.preload, { __index = preload_indexer })
else
    -- init script package environment
    package_.entry   = assert(loadfile(homedir..'/lua/server.lua', "bt"))
    -- loader should be loaded before anything
    package_.loaded['loader']  = assert(loadfile(homedir..'/lua/loader.lua', 'bt')('loader'))
end
package_.homedir = homedir

--[[
    Initialize Code Loaders
--]]
local Loader = require'loader'

---System module loader
local systemloader = Loader {
    require = require_;
    loaded  = package_.loaded;
    loaders = {
        function(modname)
            local ok, mod = pcall(require_, modname)
            if ok == false then return nil, mod end;
            return mod
        end
    };
}

---Create a server module loader
---Server's module loader exposed in the `loaded` table
local serverloader = (function()

    local context = {
        env = setmetatable({}, { __index=function(_, key) return _G[key] end })
    }
    local loaded = {}

    local code_provider if is_embedded then
        -- if is inside embedded codes
        -- load codes from bundle
        local chunks = package_.chunks.core
        code_provider = function(name)
            local chunk = chunks[name]
            if not chunk then return nil, 'bundled "core": not found' end
            
            return load(chunk, 'core.'..name, "bt", context.env)
        end
    else
        local home   = package_.homedir --[[ only exists under script environment ]]
        context.path = home..'/lua/?.lua;'..home..'/lua/?/init.lua;'

        -- load codes from file
        code_provider = function(name)
            local path, err = package_.searchpath(name, context.path)
            if not path then return nil, err end;

            return loadfile(path, 'bt', context.env)
        end
    end

    local serverloader = function(modname)
        local mod = loaded[modname]
        if mod ~= nil then return mod end;
        if string.sub(1, 1) == '@' then return nil, 'forbidden name: '..modname end

        local factory, err = code_provider(modname)
        if not factory then return nil, err end;

        local mod = factory(modname)
        loaded[modname] = mod
        return mod
    end

    local obj = Loader {
        loaded  = loaded;
        loaders = { systemloader; serverloader; };
        context = context;
    }
    
    loaded['loader'] = Loader
    loaded['@luahttpserver.loader'] = obj
    loaded['@luahttpserver.systemloader'] = systemloader;

    return obj
end)()

--[[
    Set up global 
--]]
require = serverloader.require
package = require'utils.meta'.new_void_table()

--[[
    Start
--]]
package_.entry()