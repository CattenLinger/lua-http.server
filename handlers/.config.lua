--[[
    Handler _ENV configuration
]]--

-- load mime as global object
mime_mapping = require'mime'

-- Configure template engine
pages = require"pages" { 
	path=CONFIG:resolve('pages/');
	no_cache = CONFIG.no_page_cache;
}
RegisterCacheCleaner { "pages", function() return pages.cache; end }

local http_version = require "http.version"
local new_headers  = require "http.headers".new
local http_util    = require "http.util"

local default_server = string.format("%s/%s", http_version.name, http_version.version)

function new_response_headers(status)
    local headers = new_headers()
    headers:append(":status", status)
    headers:append("server", default_server)
    headers:append("date", http_util.imf_date())
    return headers
end