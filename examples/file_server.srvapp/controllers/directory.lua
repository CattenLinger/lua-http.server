--- Convert byte to human friendly format
--- @param n number the byte to convert
--- @return string the human friendly format
local human = (function()
    local suffixes = {
        [0] = "";
        [1] = "K";
        [2] = "M";
        [3] = "G";
        [4] = "T";
        [5] = "P";
    }

    local log = math.log
    if _VERSION:match("%d+%.?%d*") < "5.1" then
        log = require "compat53.module".math.log
    end

    return function (n)
        if n == 0 then return "0" end
        local order = math.floor(log(n, 2) / 10)
        if order > 5 then order = 5 end
        n = math.ceil(n / 2^(order*10))
        return string.format("%d%s", n, suffixes[order])
    end
end)()

local http_util = require "http.util"
local lfs = require'lfs'

local render_index = pages'index.ltpl'

local function on_index_page_found(request, response)
	local file = io.open(request.model.index_file, 'rb')
	response:status(200)
	        :content_type('text/html;charset=utf-8')
	        :finish(file)
end

local weboot = resolve.webroot
return function (request, response)
	local method = request.method
	if method == 'HEAD' then return response:status(200):finish() end
	if method ~= 'GET'  then return response:status(405):finish() end

	local file_info = request.file_info
	local real_path, path = file_info.path, request.path_decoded

	local files = {}
	local model = { path=real_path, files=files }
	
	-- lfs doesn't provide a way to get an errno for attempting to open a directory
	-- See https://github.com/keplerproject/luafilesystem/issues/87
	for filename in lfs.dir(real_path) do
		-- Exclude parent directory entry listing from top level
		if (filename == ".." and path == "/") then goto continue; end
		if string.find(filename, 'index.htm', 0, true) == 1 then
			model.index_file = real_path..'/'..filename
		end

		local stats = lfs.attributes(weboot:resolve(real_path .. "/" .. filename))
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