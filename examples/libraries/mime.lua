local search_jump_table = require'utils'.search_jump_table

local mime_mapping = {
    [''] = {"application/octet-stream"};
    -- images
    ['.jpg']  = {'image/jpeg'};
    ['.jpeg'] = '.jpg';
    ['.png']  = {'image/png'};
    ['.webp'] = {'image/webp'};
    ['.svg']  = {'image/svg'};

    -- text
    ['.txt'] = {'text/plain; charset=utf8'};
    ['.lua'] = '.txt';
    ['.md']  = '.txt';

    -- web
    ['.html'] = {'text/html; charset=utf8'};
    ['.htm']  = '.html';

    ['.css']  = {'text/css; charset=utf8'};
    ['.js']   = {'text/javascript; charset=utf8'};
    ['.json'] = {'application/json; charset=utf8'};
    ['.xml']  = {'application/xml; chatset=utf8'};
}

local unpack = table.unpack

return function(filename)
    if not filename then return unpack(mime_mapping['']); end

    local ext = filename:match('%.[^%.]*$') or ''
    local type_info = search_jump_table(mime_mapping, ext:lower(), 10) or mime_mapping['']
    return unpack(type_info)
end