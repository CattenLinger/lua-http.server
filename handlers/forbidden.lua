log("Attempted to access unsupported type: ", file_type)
res_headers:upsert(":status", "403")
assert(stream:write_headers(res_headers, true))