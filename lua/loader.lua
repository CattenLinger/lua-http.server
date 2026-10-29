--[[
Module Loader
===

This module is aim to be self-contained under standard lua environment.

After a loader was create and configured, host script usually keeps this object 
to controls module loading behavior, leaving just the 'require' method to guest 
script environment.

Fields of the loader can be use separately since they are all just exposed
references from the internal closure.

```lua
local loader = require'loader' {
    loaded  = {};  -- optional, replace the default module cache
    loaders = { -- list of custom loaders
        function(modname)
            local mod, err = do_loading(modname)
            if success return mod else return nil, err end
        end
    };
}
```

The `load` method is an error safe version of `require`.
returns nil and an loading history if any error happends.
```lua
--- This will throw an error if module not found
local module = loader.require('module.name')
--- This won't
local module, err = loader.load('module.name')
```

You can combine loaders together
```lua
local system_loader = require'loader' { ... }
local special_loader = require'loader' { ... }

local guest_loader = require'loader' {
    -- remember, they are searched in reverse order
    loaders = { system_loader; special_loader; }
}

```

Usage
---

### Wrap up the lua standard `require`
```lua
local require_ = require
local package_ = package
local systemloader = Loader {
    loaded  = package_.loaded;
    loaders = {
        -- write custom loading logic to controll how modules are loaded
        function(modname)
            local ok, mod, file = pcall(require_, modname)
            if ok == false then return nil, mod end;
            return mod
        end;
    };
}
-- replace the standard `require`
require = systemloader.require

-- use it as usuall
local json = require'json'
```
--]]
local require, package = require, package;
local rawset = function(t, k, v) rawset(t, k, v); return v end;

local type, error    = type, error
local setmetatable   = setmetatable
local insert, concat = table.insert, table.concat

-- The final module reference
local M = {}

--[[
    Prototype and methods
--]]
local getters = {}

---Create a 'require' method mimic standard lua 'require'
---function base on a loader
local function build_legacy_require(self)
    local loaded, load = self.loaded, self.load

    return function(modname)
        local mod, err

        mod = loaded[modname] if mod ~= nil then return mod end;
        mod, err = load(modname) if not mod and err then error(err) end

        -- caching the module if success
        -- if loader returns empty then mark it as loaded using 'true'
        loaded[modname] = mod or true

        return mod
    end
end

---Create a loader method
local function build_load_method(self)
    local loaders = self.loaders

    local function each_loader()
        local idx=#loaders + 1
        return function()
            idx = idx - 1
            local v = loaders[idx]
            if not v then return nil end
            return idx, v
        end
    end

    return function(modname)
        local errs = {}

        -- Scan loader list in reverse order
        for _, loader in each_loader() do
            local mod, err = loader(modname)
            -- if module returns no value, mark it as 'true' (means loaded)
            if not err then return mod or true end
            insert(errs, err)
        end

        return nil, concat(errs, '\n\t')
    end
end

---Returns legacy `require` to mimic standard lua api.
---Loader's 'require' method can be overrided via passing an custom 'require' method.
function getters:require(key) return rawset(self, key, build_legacy_require(self)) end

---Return a method to load a module
---Loader's 'load' method can be overrided via passing an custom 'load' method.
function getters:load(key) return rawset(self, key, build_load_method(self)) end

---Return a empty loader list if not set
---When resolving module, loaders are searched in reverse order
function getters:loaders(key) return rawset(self, key, {}) end

---Return a default empty loaded table if not set
function getters:loaded(key)  return rawset(self, key, {}) end


local loader_mt = {
    __index = function(self, key)
        local v = getters[key] or getters['*']
        if type(v) == 'function' then return v(self, key) end
        return v
    end;

    __call     = function(self, ...) return self.require(...) end;
    __newindex = function() --[[ Not allow modifications ]]   end;
}

--[[
    Module methods
--]]

function M.create(data)
    --- All options here are allowed to be empty for later configuration
    return setmetatable(data, loader_mt)
end

local M_mt = {
    __index    = M,
    __newindex = function() error('attempted to write to readonly module') end,
    __call     = function(self, ...) return self.create(...) end
}

return setmetatable({}, M_mt)