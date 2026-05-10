local clock = require'utils'.clock

--[[
    Cache pool object
]]--
local Cache = { __cls__ = 'cache_pool'; cache_ttl = 1; cache_rebuild_interval = 60; }

--[[
    Members
]]--
function Cache.get(self, key)
    local now = clock()
    local element = self.elements[key]
    if not element then return nil; end
    
    local birth, value = table.unpack(element)
    if (now - birth) > self.cache_ttl then
        elements[key] = nil
        return nil
    end

    return value
end

function Cache.put(self, key, value)
    local old = self.elements[key]
    self.elements[key] = { clock(), value }
    return old
end

function Cache.flush(self)
    self.elements = {}
end

local function Cache_scan_elements(self, now)
    local t = self.elements
    local cnt = 0
    for k, v in pairs(t) do
        if (now - v[1]) <= self.cache_ttl then goto continue; end
        cnt = cnt + 1
        t[k] = nil
        ::continue::
    end
    return cnt
end

local function Cache_rebuild_cache(self, now)
    local new_t = {}
    local cnt = 0
    for k, v in pairs(t) do
        if (now - v[1]) > self.cache_ttl then goto continue; end
        cnt = cnt + 1
        new_t[k] = v
        ::continue::
    end
    self.elements = new_t
    return cnt
end

function Cache.evict_cache(self)
    local now = clock()
    local delta = now - self.birth
    if delta < self.cache_rebuild_interval
    then return Cache_scan_elements(self, now)
    else return Cache_rebuild_cache(self, now)
    end
end

--[[
    Static Methods
]]--
function Cache.is(self)
    return self.__cls__ == Cache_proto.__cls__
end

function Cache.new(options)
    local data = options or {}
    data.elements = {};
    data.birth = clock();

    return setmetatable(data, { 
        __index = Cache;
        __call = function(self, ...) return self:get(...); end;
    })
end

return Cache;