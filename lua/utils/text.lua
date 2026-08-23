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

--- Remove leading and tailing space of a string
---@param str string
---@return string
function extext.trim(str)
    local res = str
    local idxs, idxe = string.find(res, '^[%s]+')
    if idxs then res = string.sub(res, idxe + 1) end
    idxs, idxe = string.find(res, '[%s]+$')
    if idxs then res = string.sub(res, 1, idxs - 1) end
    return res
end

--- Check if a string is blank
--- `nil` is same as blank
---@param str string | nil 
---@return boolean
function extext.isblank(str)
    if not str then return true end
    return not str:match('[^%s]+')
end

--- Check if a string is empty
--- `nil` is same as empty
---@param str string | nil
---@return boolean
function extext.isempty(str)
    if not str then return true end
    return string.len(str) == 0
end

return extext