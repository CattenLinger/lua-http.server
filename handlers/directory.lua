local http_util = require "http.util"
local human = require'utils'.human

return function (server, stream, context)
	local headers, method = context.headers, context.method
	local real_path, path = context.real_path, context.path

	-- directory listing
	path = path:gsub("/+$", "") .. "/"
	headers:upsert(":status", "200")
	headers:append("content-type", "text/html; charset=utf-8")
	assert(stream:write_headers(headers, method == "HEAD"))
	
	if req_method == 'HEAD' then return; end

	local files = {}
	local model = { path=path, files=files }
	
	-- lfs doesn't provide a way to get an errno for attempting to open a directory
	-- See https://github.com/keplerproject/luafilesystem/issues/87
	for filename in lfs.dir(real_path) do
		-- Exclude parent directory entry listing from top level
		if (filename == ".." and path == "/") then goto continue; end

		local stats = lfs.attributes(real_path .. "/" .. filename)
		if stats.mode == "directory" then
			filename = filename .. "/"
		end

		table.insert(files, {
			css_cls  = stats.mode:gsub("%s", "-");
			href     = http_util.encodeURI(path .. filename);
			filename = filename;
			size     = stats.size;
			size_h   = human(stats.size);
			time     = os.date("!%Y-%m-%d %X", stats.modification)
		})
		::continue::
	end

	pages'index.ltpl'(model, function(s) assert(stream:write_chunk(s)); end)
	stream:write_chunk('\n', true)
end