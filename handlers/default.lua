return function (server, stream, context)
	local headers = context.headers
	headers:upsert(":status", "404")
	assert(stream:write_headers(headers, false))
	pages'error.ltpl'({ path=context.path, code="404" }, function(e) stream:write_chunk(e) end)
	stream:write_chunk('\n', true)
end