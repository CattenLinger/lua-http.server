local search_jump_table = require'utils'.search_jump_table

--[[
    Simple mime db. It reads records from file (usually nginx's mime.type).

    Internal entry format: { mime_name, ext_array[], catalog_string }
    it comes a meta table to provide some utility
--]]

--[[ MIME Entity ]]--
local Entity do
    local __proto = {}
    function __proto.get_id(self)       return self[1] end
    function __proto.get_name(self)     return self[2] end
    function __proto.get_exts(self)     return self[3] end
    function __proto.get_catalog(self)  return self[4] end
    function __proto.get_subtype(self)  return self[5] end

    local __mt = {
        __index    = __proto;
        __tostring = function(self) return self:get_name() end;
        __call     = function(self, param_string)
            return
            tostring(self)..'; '..param_string
        end;
    }
    local M = {}
    function M.create(id, name, exts)
        local catalog = string.match(name, '[^/]+') or ''
        local subtype = string.match(name, '[^/]+$' or '')
        local data = { id, name, exts, catalog, subtype }
        return setmetatable(data, __mt)
    end
    Entity = setmetatable({}, {
        __call = function(self, ...) return M.create(...) end
    })
end

-- [[ MIME Database Object ]]--
local Db do
    local __proto = {}

    -- register to extension name index
    local function ext_reg(self, id, exts)
        local _idx_ext = self._idx_ext
        for _, ext in ipairs(exts) do
            local ext_l = _idx_ext[ext]
            if not ext_l then
                ext_l = {}
                _idx_ext[ext] = ext_l
            end
            table.insert(ext_l, id)
        end
    end
    -- register to id index
    local function idx_reg(self, id, entity)
        -- add entity to collection
        self._rows[id] = entity
        -- register to name-id index
        self._idx_type[entity:get_name()] = id
        return entity
    end

    -- register a mime type with extensio name to db, if not exists
    function __proto.register(self, name, exts)
        -- get index
        local idx = self._idx_type[name]
        if not idx then -- increase the index for new entity
            idx = self._idx
            self._idx = idx + 1
        end

        local entity = self._rows[idx]
        if not entity -- if is new entity, create and insert to index
        then entity = idx_reg(self, idx, Entity(idx, name, exts))
        end
        -- insert exts to index
        if #exts > 0 then ext_reg(self, idx, exts) end
    end

    -- resolve content type of a filename
    -- return first content type name, and list of index
    -- that might match
    function __proto.content_type_of(self, filename)
        local ext = filename:match('%.[^%.]*$') or ''
        if not ext then return nil end
        ext = string.sub(ext, 2)

        local idxs = self._idx_ext[ext]
        if not idxs then return nil end
        return self._rows[idxs[1]], idxs
    end

    -- Get one by internal id ref
    function __proto.get_by_id(self, id)
        return self._rows[id]
    end

    -- Get entity by full name
    function __proto.entity_by_name(self, name)
        local idx = self._idx_type[name]
        if not idx then return nil end
        return self._rows[idx]
    end
    local function create_db()
        return setmetatable(
                { _idx=1, _idx_ext = {}, _idx_type={}, _rows={} },
                { __index=__proto, __call=__proto.entity_by_name }
        )
    end

    --[[ MIME Module ]]--

    local M = {}
    --[[
    Load MIME database from file handle
    --]]
    function M.load_file(file)
        local mime_db = create_db()
        for line in file:lines() do
            local mime_def = string.match(line, '[^;}]+')
            if not mime_def then goto continue end
            local lb = string.find(mime_def, '{')
            if lb then mime_def = string.sub(mime_def, lb + 1) end

            local values = {};
            for item in string.gmatch(mime_def, '[%S]+') do
                table.insert(values, item)
            end
            if #values == 0 then goto continue end
            local name = values[1]
            table.remove(values, 1)
            mime_db:register(name, values)
            ::continue::
        end
        return mime_db
    end

    Db = setmetatable({}, {
        __index=M,
        __call=function(_, ...) return M.load_file(...) end
    })
end

return Db