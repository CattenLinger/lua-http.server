local render_error = pages'error.ltpl'

return function (request, response)
	response:status(404)
	        :content_type('text/html;charset=utf-8')

	response:finish(render_error {
		page_title  = "Not found: " .. request.path;
		title       = 'Not found';
		description = "The content you request is not exists.";
	})
end