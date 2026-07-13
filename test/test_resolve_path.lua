local exos = require'src.utils'.os

local testcases = {
    '.', './', '../', '/', '..', './..', '../.', './.', '//', '././.', '/./././.', '/////////';
    '/home/user/';
    'user/local';
    'tmp';
    '/dev/null';
    '/dev/../null';
    '../dev/../null';
    '///////dev/../null';
    '/dev//////../null';
    '/dev/../////null';
    '/dev/../null/////';
    '/dev/../null/.../././././//..';
    '/dev../../..null//.//../.';
}
print(':::::::: Path segs')
for k, v in ipairs(testcases) do
    print(v, '->', '['..table.concat(exos.pathsegs(v), ', ')..']')
end

print(':::::::: Path resolve')
local path = exos.path'/'
for k, v in ipairs(testcases) do
    print(v, '->', tostring(exos.resolve(v)) .. ', ' .. path:resolve(v))
end