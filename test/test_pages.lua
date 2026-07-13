local pages = require './pages'
pages.path = 'pages/'
local test_data = {
    path="/", 
    files={ 
        {css_class="directory"; href="/"; filename="."; size="0B"; time="1970-01-01 00:00:00"}
    }
}

local render = pages.load('index.ltpl', { minify=true })
render(test_data, function(s) io.stdout:write(s) end)
print()