package.path = './src/?.lua;'..package.path
local LOG = require'log':set_defaults {
    use_color=true;
    --date_format='[%d/%b/%Y:%H:%M:%S %z]';
    level = 'INFO';
}

local function table_tostring(tb)
    local lines = {}
    for k, v in pairs(tb) do table.insert(lines, k..'="'..tostring(v)..'"') end
    return '{ '..table.concat(lines, '; ')..' }'
end


local log = LOG()

local function print_all_level()
    io.stderr:write('======== LEVEL: ', tostring(log.level), ' (', log:get_level_name() , ')','\n')
    log("Print default")
    log:error("Print error")
    log:warn("Print warn")
    log:info("Print info: LUA_VERSION=%s", _VERSION)
    log:debug("Print debug: %s", table_tostring(package))
    log:trace("Print trace: %s", table_tostring(_G))
end
print_all_level()
log.level = 'INFO';
log:reconfigure()
print_all_level()
-- Test behavior of new instances
--log = require'log'()
--
--for i = 0, 5 do
--    log.level = i
--    log:reconfigure()
--    print_all_level()
--end
--
--for _, lvl in ipairs { 'ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE' } do
--    log.level = lvl
--    log:reconfigure()
--    print_all_level()
--end