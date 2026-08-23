local chunk = assert(package.chunks.core.init, 'unexpected chunk core.init not found')
assert(load(chunk, 'core.init', 'bt', _ENV))()