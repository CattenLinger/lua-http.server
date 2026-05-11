return function(server, stream, context)
    log("Attempted to access unsupported type: ", file_type)
    
    local res_headers = new_response_headers(403)
    assert(stream:write_headers(res_headers, true))
end