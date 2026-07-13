--[[
    Text utility functions
--]]

local extext = setmetatable({}, {__index=string})

---Repeat a text sequence in num times.
---Usually is for spacing when formatting.
---
---@param num number @repeat count
---@param c string | nil @optional text, default is ' '
---@return string @a string
function extext.nchar(num, c)
    c = c or ' '
    local str = ''
    for i=1, num do str = str..tostring(c) end
    return str
end

--[[
    Remove leading and tailing space of a string
]]
function extext.trim(str)
    local res = str
    local idxs, idxe = string.find(res, '^[%s]+')
    if idxs then res = string.sub(res, idxe + 1) end
    idxs, idxe = string.find(res, '[%s]+$')
    if idxs then res = string.sub(res, 1, idxs - 1) end
    return res
end

return extext