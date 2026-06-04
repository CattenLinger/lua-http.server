package.path = './lua/?.lua;'..package.path

local cache = require'examples.libraries.cache'.new { cache_ttl = 3 }
local function print_cache_info()
    print('Cache.now: '..tostring(cache:clock())..', Cache.birth: '..tostring(cache.birth))
end

local cqueues = require'cqueues'
local cq = cqueues.new()

cq:wrap(function()
    print_cache_info()

    local value = 'hello'
    local function check_value()
        print('cache:get("value"): ', tostring(cache:get("value")))
    end
    print('put value "hello"')
    cache:put('value', value)
    print('wait 1s')
    cqueues.sleep(1)
    check_value()
    print_cache_info()
    print('wait 4s')
    cqueues.sleep(4)
    check_value()
    print_cache_info()
end)
cq:loop()