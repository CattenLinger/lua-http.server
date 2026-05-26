-- clock() returns integer seconds
local clock do
    local sysclock = require'utils'.clock
    clock = function() return sysclock() end
end

--[[ Cache pool object ]]--
local Cache = {
    cache_ttl = 1;
    cache_rebuild_interval = 60;
    clock = clock;
}

--[[ Members ]]--

--- Get cache element by key
--- @param key string cache key
--- @return any|nil cached element or nil if expired or not found
function Cache.get(self, key)
    local now = self.clock()
    local element = self.elements[key]
    if not element then return nil; end
    
    local birth, value = table.unpack(element)
    if (now - birth) <= self.cache_ttl then return value end

    self.elements[key] = nil
    return nil
end

--- Get cache element by key, if element not presented
--- call provider to get a new value
--- @param key string
--- @param provider function value provider
--- @return any|nil, any|nil
function Cache.get_or_computed(self, key, provider, ...)
    local value = self:get(key)
    if value ~= nil then return value end;

    local error
    value, error = provider(key, ...)
    if error then return nil, error end

    if value ~= nil then self:put(key, value) end
    return value
end

--- Put an element to cache associated with key
--- @param key string a key
--- @param value any value
--- @return any old cache entry or nil
function Cache.put(self, key, value)
    local old = self.elements[key]
    self.elements[key] = { self:clock(), value }
    return old
end

--- Discard all cached items
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
    for k, v in pairs(self.elements) do
        if (now - v[1]) > self.cache_ttl then goto continue; end
        cnt = cnt + 1
        new_t[k] = v
        ::continue::
    end
    self.elements = new_t
    return cnt
end

function Cache.evict_cache(self)
    local now = self.clock()
    local delta = now - self.birth
    if delta < self.cache_rebuild_interval
    then return Cache_scan_elements(self, now)
    else return Cache_rebuild_cache(self, now)
    end
end

--[[ Static Methods ]]--
local __mt = { 
    __class = '::cache_pool';
    __index = Cache;
    __call = function(self, ...) return self:get(...); end;
}

function Cache.is(self)
    if type(self) ~= 'table' then return false; end
    return ((getmetatable(self) or {}).__class == __mt.__class)
end

function Cache.new(options)
    local data = options or {}
    data.elements = {};
    setmetatable(data, __mt)

    data.birth = data:clock();
    return data
end

--[[
    Install a global cache cleaner
    options:
    - scan_interval: scanner sleep interval, in seconds
]]--
function Cache.install_cleaner(options)
    if Cache.cleaner then return Cache, Cache.cleaner end
    local cqueues = require'cqueues'
    local log = require'log'()

    options = options or {}
    local registry = {}
    local cleaner = { registry=registry, options=options }
    Cache.cleaner = cleaner

    function cleaner.register(tb)
        local name, getter = table.unpack(tb)
        local c = getter()
        if not Cache.is(c) then error("Cache '"..name.."' is not a cache instance."); end
        table.insert(registry, { name, getter });
    end

	EventQueue:wrap(function()
		log:info("Cache evict job started.")
		::begin_loop::
		cqueues.sleep(options.scan_interval or 10)

		for _, pv in ipairs(registry) do
			local name, provider = table.unpack(pv)
			local c = provider()
			if not c then goto continue; end
			local cache_evict_count = c:evict_cache()
			if cache_evict_count <= 0 then goto continue; end
			log:debug("[Cache: %s] %d evicted.", name, cache_evict_count);
			if NotifyNextGC then NotifyNextGC() end
			::continue::
		end
		goto begin_loop
	end)
    return Cache, Cache.cleaner
end

return Cache;