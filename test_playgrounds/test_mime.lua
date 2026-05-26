package.path = './lua/?.lua;'..package.path

local mime = require'examples/libraries/mime'
local fd, err = io.open('examples/file_server.srvapp/mime.type.txt')
if not fd then error(err) end
local db = mime.load_file(fd)
fd:close()
local first_type, idx = db:content_type_of('hello.html')
print(first_type, '{'..table.concat(idx, ', ')..'}')

local mime_entity = db('application/json')
print('Name', mime_entity:get_name())
print('Ref',tostring(mime_entity:get_id()))
print('Exts', '{'..table.concat(mime_entity:get_exts(), ', ')..'}')
print('Catalog', mime_entity:get_catalog())
print('Subtype', mime_entity:get_subtype())
print('With params: ', mime_entity'chatset=utf-8')
