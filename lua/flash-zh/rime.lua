--- Rime dict.yaml data source for flash-zh.
--- Parses one or more `*.dict.yaml` tables, optionally filters entries to a
--- character set loaded from a Rime `lua` module (e.g. `yuhao_charsets.lua`),
--- and builds a code trie for the parser.
local M = {}

local DEFAULT_SETS = { "ubiquitous", "common", "tonggui", "harmonic" }

local function set_to_string(set)
	local buf, n = {}, 0
	for k in pairs(set) do
		n = n + 1
		buf[n] = k
	end
	return table.concat(buf)
end

local function class_of(raw)
	if raw == nil or raw == "" then
		return nil
	end
	return "[" .. raw:gsub("[%]%^%-\\]", "\\%0") .. "]"
end

function M.exact_class(node)
	if not node._ec then
		node._ec = class_of(node.exact_raw)
	end
	return node._ec
end

-- Aggregate, lazily, the exact codes found anywhere in this subtree. This is
-- the set of characters whose code has the current node's path as a prefix.
function M.prefix_raw(node)
	if not node._pr then
		local seen, buf, n = {}, {}, 0
		local function walk(nd)
			if nd.exact_raw then
				for ch in nd.exact_raw:gmatch(".[\128-\191]*") do
					if not seen[ch] then
						seen[ch] = true
						n = n + 1
						buf[n] = ch
					end
				end
			end
			for _, child in pairs(nd.children) do
				walk(child)
			end
		end
		walk(node)
		node._pr = table.concat(buf)
	end
	return node._pr
end

function M.prefix_class(node)
	if not node._pc then
		node._pc = class_of(M.prefix_raw(node))
	end
	return node._pc
end

local function load_charsets(path, sets)
	local chunk = loadfile(path)
	if not chunk then
		return nil
	end
	local ok, module = pcall(chunk)
	if not ok or type(module) ~= "table" then
		return nil
	end
	local names = sets or DEFAULT_SETS
	if type(names) == "string" then
		names = { names }
	end
	local set = {}
	for _, name in ipairs(names) do
		local body = module[name]
		if type(body) == "string" then
			for line in body:gmatch("[^\r\n]+") do
				line = line:gsub("^%s+", ""):gsub("%s+$", "")
				if line ~= "" then
					set[line] = true
				end
			end
		end
	end
	return set
end

local function parse_header_column(line, state)
	if line:match("^columns%s*:") then
		state.in_columns = true
		return
	elseif state.in_columns then
		local name = line:match("^%s*%-%s*([%w_]+)")
		if name then
			state.cols[#state.cols + 1] = name
		elseif line:match("^%S") then
			state.in_columns = false
		end
	end
end

local function parse_dict(path, charset_set)
	local f = io.open(path, "rb")
	if not f then
		error("flash-zh: cannot open dict file: " .. path)
	end
	local data = f:read("*a")
	f:close()

	local started = false
	local col_state = { in_columns = false, cols = {} }
	local text_idx, code_idx = 1, 2
	local rows = {}

	for line in data:gmatch("[^\r\n]+") do
		if not started then
			if line == "..." then
				started = true
				for i, name in ipairs(col_state.cols) do
					if name == "text" then
						text_idx = i
					elseif name == "code" then
						code_idx = i
					end
				end
			else
				parse_header_column(line, col_state)
			end
		elseif line:sub(1, 1) ~= "#" then
			local text, code
			if text_idx == 1 and code_idx == 2 then
				local c1 = line:find("\t", 1, true)
				if c1 then
					text = line:sub(1, c1 - 1)
					code = line:sub(c1 + 1):match("^([^\t]*)") or ""
				end
			else
				local fields = {}
				for field in (line .. "\t"):gmatch("([^\t]*)\t") do
					fields[#fields + 1] = field
				end
				text = fields[text_idx]
				code = fields[code_idx]
			end
			if text and code and code ~= "" and (not charset_set or charset_set[text]) then
				local b = text:byte(1)
				local exp = (not b and 0) or (b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4)
				if #text == exp and code:match("^%l+$") then
					rows[#rows + 1] = text
					rows[#rows + 1] = code
				end
			end
		end
	end
	return rows
end

local function finalize(node)
	if node.term then
		node.exact_raw = set_to_string(node.term)
		node.term = nil
	end
	for _, child in pairs(node.children) do
		finalize(child)
	end
end

local function insert_row(root, codes_by_char, seen_char, seen_code, text, code)
	local b = text:byte(1)
	local exp = (not b and 0) or (b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4)
	if #text ~= exp or not code:match("^%l+$") then
		return
	end
	local node = root
	for i = 1, #code do
		local c = code:sub(i, i)
		local nxt = node.children[c]
		if not nxt then
			nxt = { children = {} }
			node.children[c] = nxt
		end
		node = nxt
	end
	if not node.term then
		node.term = {}
		node.depth = #code
	end
	node.term[text] = true
	seen_char[text] = true
	seen_code[code] = true
	local list = codes_by_char[text]
	if not list then
		list = {}
		codes_by_char[text] = list
	end
	for _, c in ipairs(list) do
		if c == code then
			return
		end
	end
	list[#list + 1] = code
end

local function stat_key(cfg)
	local parts = {}
	for _, p in ipairs(cfg.paths) do
		parts[#parts + 1] = p .. ":" .. tostring(vim.fn.getftime(p))
	end
	if cfg.charsets then
		parts[#parts + 1] = cfg.charsets .. ":" .. tostring(vim.fn.getftime(cfg.charsets))
	end
	parts[#parts + 1] = table.concat(cfg.sets or {}, ",")
	return table.concat(parts, "|")
end

-- Compile a stable, mtime-keyed cache path for the filtered rows. Returns nil
-- when the cache directory cannot be created.
local function cache_file(cfg)
	local key = stat_key(cfg)
	local h = 5381
	for i = 1, #key do
		h = (h * 33 + key:byte(i)) % 4294967296
	end
	local dir = vim.fn.stdpath("cache") .. "/flash-zh"
	vim.fn.mkdir(dir, "p")
	return string.format("%s/dict-%x.tsv", dir, h)
end

local function load_rows_from_cache(cpath, root, codes_by_char, seen_char, seen_code)
	local f = io.open(cpath, "rb")
	if not f then
		return false
	end
	local data = f:read("*a")
	f:close()
	for line in data:gmatch("[^\r\n]+") do
		local c1 = line:find("\t", 1, true)
		if c1 then
			insert_row(root, codes_by_char, seen_char, seen_code, line:sub(1, c1 - 1), line:sub(c1 + 1))
		end
	end
	return true
end

local function load(cfg)
	local root = { children = {} }
	local codes_by_char = {}
	local seen_char, seen_code = {}, {}

	local cpath = cache_file(cfg)
	if not load_rows_from_cache(cpath, root, codes_by_char, seen_char, seen_code) then
		local charset_set = nil
		if cfg.charsets then
			charset_set = load_charsets(cfg.charsets, cfg.sets)
		end
		local tmp = cpath .. ".tmp"
		local wf = io.open(tmp, "wb")
		for _, path in ipairs(cfg.paths) do
			local rows = parse_dict(path, charset_set)
			for i = 1, #rows, 2 do
				insert_row(root, codes_by_char, seen_char, seen_code, rows[i], rows[i + 1])
				if wf then
					wf:write(rows[i], "\t", rows[i + 1], "\n")
				end
			end
		end
		if wf then
			wf:close()
			os.remove(cpath)
			if not os.rename(tmp, cpath) then
				os.remove(tmp)
			end
		end
	end

	finalize(root)
	local count_chars, count_codes = 0, 0
	for _ in pairs(seen_char) do
		count_chars = count_chars + 1
	end
	for _ in pairs(seen_code) do
		count_codes = count_codes + 1
	end
	return {
		trie = root,
		codes_by_char = codes_by_char,
		char_count = count_chars,
		code_count = count_codes,
	}
end

M._cfg = nil
M._source = nil
M._failed = false
M._cache = {}

---@param dict string|table a path, a list of paths, or { paths = {...}, charsets = "...", charset_sets = {...} }
function M.configure(dict)
	local paths, charsets, sets
	if type(dict) == "string" then
		paths = { dict }
	elseif type(dict) == "table" then
		if dict.paths then
			paths = dict.paths
			charsets = dict.charsets
			sets = dict.charset_sets
		else
			paths = dict
		end
	end
	if type(paths) == "string" then
		paths = { paths }
	end
	M._cfg = { paths = paths or {}, charsets = charsets, sets = sets }
	M._source = nil
	M._failed = false
end

function M.is_active()
	return M._cfg ~= nil and #M._cfg.paths > 0 and not M._failed
end

function M.source()
	if not M.is_active() then
		return nil
	end
	if M._source then
		return M._source
	end
	local key = stat_key(M._cfg)
	local cached = M._cache[key]
	if not cached then
		local ok, res = pcall(load, M._cfg)
		if not ok then
			M._failed = true
			vim.notify("flash-zh: failed to load dict: " .. tostring(res), vim.log.levels.WARN)
			return nil
		end
		cached = res
		M._cache[key] = cached
	end
	M._source = cached
	return M._source
end

return M
