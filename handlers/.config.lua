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