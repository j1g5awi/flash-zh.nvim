local flash = require("flash")
local rime = require("flash-zh.rime")

local M = {}

local function with_fast_engine(fn, opts)
	local prev = vim.o.regexpengine
	if prev == 1 then
		return fn(opts)
	end
	vim.o.regexpengine = 1
	local ok, res = xpcall(fn, debug.traceback, opts)
	vim.o.regexpengine = prev
	if not ok then
		error(res, 0)
	end
	return res
end

function M.jump(opts)
	opts = opts or {}
	opts = vim.tbl_deep_extend("force", {
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = {
			mode = M.mix_mode,
		},
		labeler = function(_, state)
			require("flash-zh.labeler").new(state):update()
		end,
	}, opts)
	with_fast_engine(flash.jump, opts)
end

function M.remote(opts)
	opts = opts or {}
	opts = vim.tbl_deep_extend("force", {
		labels = "asdfghjklqwertyuiopzxcvbnm",
		search = {
			mode = M.mix_mode,
		},
		labeler = function(_, state)
			require("flash-zh.labeler").new(state):update()
		end,
	}, opts)
	with_fast_engine(flash.remote, opts)
end

-- ===========================================================================
-- code trie parser
-- ===========================================================================

local to_escape = "\\^$*+?.%|[]()"

-- One alternative matching `str` as plain English text (lowercase letters
-- also match their uppercase form).
local function english_split(str)
	local acc = {}
	for i = 1, #str do
		local c = str:sub(i, i)
		acc[#acc + 1] = c:match("%l") and { type = "alpha", str = c } or { type = "other", str = c }
	end
	return acc
end

-- Enumerate the possible segmentations of `str` against the code trie.
-- Each split is a list of nodes consumed by `M.regex`.
local function trie_parse(str)
	local source = rime.source()
	if not source then
		return {}
	end
	local root = source.trie
	local splits = {}

	local function emit(acc)
		local copy = {}
		for i = 1, #acc do
			copy[i] = acc[i]
		end
		splits[#splits + 1] = copy
	end

	local function rec(pos, acc)
		if pos > #str then
			emit(acc)
			return
		end
		local ch = str:sub(pos, pos)
		if ch:match("%l") then
			-- walk the trie from the root, collecting every complete code
			local node = root
			local i = pos
			local terminals
			while i <= #str do
				local c = str:sub(i, i)
				if not c:match("%l") then
					break
				end
				local nxt = node.children[c]
				if not nxt then
					break
				end
				node = nxt
				if node.exact_raw then
					terminals = terminals or {}
					terminals[#terminals + 1] = node
				end
				i = i + 1
			end
			if terminals then
				for _, term in ipairs(terminals) do
					acc[#acc + 1] = { type = "raw", str = rime.exact_class(term) }
					rec(pos + term.depth, acc)
					acc[#acc] = nil
				end
			end
			-- Remaining input is a prefix of some code: match every character
			-- whose code starts with it. Skip when it is a leaf, since the
			-- exact branch above already covers that identical character set.
			if i > #str and node ~= root and not (node.exact_raw and next(node.children) == nil) then
				acc[#acc + 1] = { type = "raw", str = rime.prefix_class(node) }
				emit(acc)
				acc[#acc] = nil
			end
		else
			-- any other character is matched literally
			acc[#acc + 1] = { type = "other", str = ch }
			rec(pos + 1, acc)
			acc[#acc] = nil
		end
	end

	rec(1, {})
	splits[#splits + 1] = english_split(str)
	return splits
end

local function build_trie_regex(str)
	local splits = trie_parse(str)
	if #splits == 0 then
		return [[\%^\%$]]
	elseif #splits == 1 then
		return M.regex(splits[1])
	end
	local regexs = { [[\(]] }
	for i, split in ipairs(splits) do
		regexs[#regexs + 1] = M.regex(split)
		if i < #splits then
			regexs[#regexs + 1] = [[\|]]
		end
	end
	regexs[#regexs + 1] = [[\)]]
	return table.concat(regexs)
end

local nodes = {
	alpha = function(str)
		return "[" .. str .. string.upper(str) .. "]"
	end,
	other = function(str)
		return vim.fn.escape(str, to_escape)
	end,
	raw = function(str)
		return str
	end,
}

function M.regex(parser)
	local regexs = {}
	for _, v in ipairs(parser) do
		regexs[#regexs + 1] = nodes[v.type](v.str)
	end
	return table.concat(regexs)
end

local no_match = [[\%^\%$]]
local configured = false
local warned = false

local function resolve(str)
	local source = rime.source()
	if not source then
		if not configured and not warned then
			warned = true
			vim.notify("flash-zh: no dict configured, Chinese matching disabled", vim.log.levels.WARN)
		end
		return no_match, no_match
	end
	local ret = build_trie_regex(str)
	return ret, ret
end

function M.mix_mode(str)
	return resolve(str)
end

-- @param opts table
-- @field opts.dict string|table Rime dict.yaml path(s). A string, a list of
--             paths, or `{ paths = {...}, filter_charset = true|false }`.
--             `filter_charset` (default true) restricts entries to the built-in
--             common character set; set false to keep every character.
function M.setup(opts)
	opts = opts or {}
	if opts.dict then
		rime.configure(opts.dict)
		configured = true
		warned = false
	end
end

return M
