local clock = require'utils'.clock

local __proto = { last=0, interval=1, clock=clock }

function __proto.debounce(self)
    local last, interval, now = self.last, self.interval, self.clock()
    if (now - last) < interval then return true end
    self.last = now
end

local __mt_debounce = {
    __index = __proto;
    __call  = function(self) return self:debounce() end;
}

local M = {}
function M.create(options)
    options = options or {}
    return setmetatable(options, __mt_debounce)
end

return setmetatable({}, {
    __index = M,
    __call = function(_, ...) return M.create(...) end }
)