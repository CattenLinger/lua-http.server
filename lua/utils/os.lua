--[[
    OS utility (currently does not supporting windows) 
--]] 
---@class ExOSLib

---@type ExOSLib
local exos = setmetatable({}, { __index=os })

---Resolve a path to absolute real path
---@param path string @path
---@return string @path resolved
function exos.realpath(path)
    local fd = io.popen("realpath '"..path.."'")
    if not fd then error('could not execute shell command for realpath') end
    local line = fd:read('l')
    fd:close()
    return line
end

---Split a path to list of segments
---
---It does a very naive seperation with '/', so
---directory will be ends with '/' .
---@param path string
---@return string
function exos.pathsegs(path)
    if not path then  return path end
    if #path < 1 then return nil  end
    local segs = {}
    local nidx = 0
    while true do
        local cidx = string.find(path, '/', nidx, true)
        if not cidx then break end
        table.insert(segs, string.sub(path, nidx, cidx))
        nidx = cidx + 1
    end
    if nidx <= #path then table.insert(segs, string.sub(path, nidx)) end
    return segs
end

---resolve a relative path.
---@param path string
---@return string
function exos.resolve(path)
    local segs = exos.pathsegs(path)
    if #segs == 0 then return nil end;

    local npath = {}
    for idx, seg in ipairs(segs) do
        -- filter out any part with only '.' and '/'
        local rel = string.match(seg, '^[%./]+$')
        if not rel then goto insert end;
        if rel == '/' then
            -- ignore any '/' between segments
            if idx > 1 then goto continue end
            goto insert
        end
        if rel == '.' or rel == './'  then
            if idx > 1 then goto continue end
            seg = './'; -- normalize '.'
            goto insert;
        end
        if rel == '..' or rel == '../' then
            table.remove(npath)
            if #npath > 0 then goto continue end
            seg = './'; -- use './' if has no parent (chroot-ed)
            goto insert;
        end
        -- things like '...../' is illegal
        do return nil end
        ::insert::
        table.insert(npath, seg)
        ::continue::
    end
    -- empty path just same as nil
    if #npath == 0 then return nil end
    return table.concat(npath)
end

---@class Path

local path_mt_ = {
    ---@type Path
    __index = {
        --- Resole path
        ---@vararg string
        ---@return string
        resolve = function(self, ...)
            local root = assert(self[1], 'bad self')
            local all = { ... }
            if #all == 0 then return root .. '/' end

            local buf = {}
            for _, seg in ipairs { ... } do
                for str in string.gmatch(seg, '[^/]+') do
                    if str == '.' or str == '' then goto continue end
                    if str == '..' then table.remove(buf); goto continue; end
                    table.insert(buf, str)
                    ::continue::
                end
            end

            return root .. '/' .. table.concat(buf, '/')
        end;
        
        --- Get basename of this path
        ---@return string
        basename = function(self)
            local root = assert(self[1], 'bad self')
            return string.match(root, '[^/]+$')
        end;

        --- Get parent path object of this path
        ---@return Path
        parent = function(self)
            return self('..')
        end;
    };
    __tostring = function(self) return self.name or self[1] end;
    __call     = function(self, ...) return exos.path(self:resolve(...)) end;
    __concat   = function(self, str) return tostring(self) .. str end;
}

--- Create a path object for resolving paths later
---@param path string
---@return Path
function exos.path(path)
    assert(path)
    -- Reslove twice 
    path = exos.resolve(assert(exos.resolve(path), 'illegal path'))
    local dname = nil
    if path ~= '/' then
        if string.sub(path, -1) == '/' then
            path = string.sub(path, 1, -2)
        end
        if path == '' then path = '.' end
    else
        path = ''; dname = '/';
    end
    return setmetatable({ path, name=dname; }, path_mt_)
end

return exos