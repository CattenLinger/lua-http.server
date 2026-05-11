return function (server, stream, context)

    local res_headers = new_response_headers(404)
	assert(stream:write_headers(res_headers, false))
    
	pages'error.ltpl'({ path=context.path, code="404" }, function(e) stream:write_chunk(e) end)
	stream:write_chunk('\n', true)
end