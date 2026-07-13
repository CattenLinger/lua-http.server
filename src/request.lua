--[[ Server request wrapper ]]
local http_util = require "http.util"
local lpeg      = require "lpeg"
local uri_patts = require "lpeg_patterns.uri"
local uri_ref   = uri_patts.uri_reference * lpeg.P(-1)
local table     = require'utils'.table

local log = Logger
local dbgmod_api = IsDebugMode'api'

local getters = {}
local __mt = { __index=getters }

--[[
    All Property Getter Definition
--]]

--- Get headers from stream
function getters.headers(self)
    return assert(self.stream:get_headers())
end

--- Get request method 
function getters.method(self)
    return assert(self.headers:get':method')
end

--- Get content type of request
function getters.content_type(self)
    return self.headers:get'content-type' or ''
end

--- Get full path (the uri) of the path
function getters.uri(self)
    return assert(self.headers:get':path')
end

--- Get only the path (uri without query string) of the request
function getters.path(self)
    local path = self.uri
    local uri_t = assert(uri_ref:match(path), "invalid path")
    return http_util.resolve_relative_path("/", uri_t.path)
end

--- Get only the query string (uri without the path) of the request
function getters.query_string(self)
    local uri = self.uri
    local idx = string.find(uri, '?', 1, true)
    if not idx then return '' end
    return string.sub(uri, idx + 1)
end

--- Get all query params and collect them to a map.
--- values will be uri-decoded.
function getters.query(self)
    local query_string = self.query_string
    local queries = {}
    if query_string == '' then return queries end
    for k, v in http_util.query_args(query_string) do
        table.insert(queries, {k, http_util.decodeURIComponent(v)})
    end
    return queries
end

--- Get the decoded path of url (deprecated)
function getters.real_path(self)
    if dbgmod_api then
    log:warn('[Framework API] `Request.real_path` is deprecated, use `Request.path_decoded` instead. %s', require'debug'.traceback())
    end
    return self.path_decoded
end

--- Get the decoded path of url.
function getters.path_decoded(self)
    return http_util.decodeURIComponent(self.path)
end

return function (server, stream)
    return table.lazy(setmetatable({ stream = stream }, __mt ));
end