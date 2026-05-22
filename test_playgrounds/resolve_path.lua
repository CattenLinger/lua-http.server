local exos = require'./lib/utils'.os

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
for k, v in ipairs(testcases) do
    print(v, '->', exos.resolve(v))
end