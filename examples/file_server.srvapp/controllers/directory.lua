local human = require'utils'.human
local http_util = require "http.util"
local lfs = require'lfs'

local render_index = pages'index.ltpl'

local function on_index_page_found(request, response)
	local file = io.open(request.model.index_file, 'rb')
	response:status(200)
	        :content_type('text/html;charset=utf-8')
	        :finish(file)
end

return function (request, response)
	local method = request.method
	if method == 'HEAD' then return response:status(200):finish() end
	if method ~= 'GET'  then return response:status(405):finish() end

	local real_path, path = request.real_path, request.path

	local files = {}
	local model = { path=http_util.decodeURIComponent(path), files=files }
	
	-- lfs doesn't provide a way to get an errno for attempting to open a directory
	-- See https://github.com/keplerproject/luafilesystem/issues/87
	for filename in lfs.dir(real_path) do
		-- Exclude parent directory entry listing from top level
		if (filename == ".." and path == "/") then goto continue; end
		if string.find(filename, 'index.htm', 0, true) == 1 then
			model.index_file = real_path..'/'..filename
		end

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
	if model.index_file then
		request.model = model
		return on_index_page_found(request, response)
	end

	response:status(200)
			:content_type('text/html;charset=utf-8')
			:finish(render_index(model))
end