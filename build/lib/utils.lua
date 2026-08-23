local M = {}


local readargs_mt = {
    __call = function(self, fn)
        local state = {}
        for i, v in ipairs(self) do fn(state, v, i) end
        return state
    end
}
function M:readargs(args)
    local arg_list = {}
    local args = { table.unpack(arg) }
    local props = {} while true do
        local v = table.remove(args)
        if v == nil then break; end

        if string.sub(v, 1, 1) ~= '-' then
            table.insert(props, v)
        else
            table.insert(arg_list, { v, props })
            props = {}
        end
    end
    if #props > 0 then table.insert(arg_list, { '', props }); end

    return setmetatable(arg_list, readargs_mt)
end

return M