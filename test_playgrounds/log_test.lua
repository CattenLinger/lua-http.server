package.path = './lib/?.lua;'..package.path

local log = (require'./lib/log':set_defaults {
    use_color=true;
    --date_format='[%d/%b/%Y:%H:%M:%S %z]';
})()
local function table_tostring(tb)
    local lines = {}
    for k, v in pairs(tb) do table.insert(lines, k..'="'..tostring(v)..'"') end
    return '{ '..table.concat(lines, '; ')..' }'
end

function print_all_level()
    io.stderr:write('======== LEVEL: ', tostring(log.level), ' (', log:get_level_name() , ')','\n')
    log("Print default")
    log:error("Print error")
    log:warn("Print warn")
    log:info("Print info: LUA_VERSION=%s", _VERSION)
    log:debug("Print debug: %s", table_tostring(package))
    log:trace("Print trace: %s", table_tostring(_G))
end

for i = 0, 5 do
    log.level = i
    log:reconfigure()
    print_all_level()
end
