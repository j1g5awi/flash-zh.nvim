local rime = require("flash-zh.rime")

local M = {}

local py_table = {}

local function py_insert(char, code)
	local list = py_table[char]
	if not list then
		list = {}
		py_table[char] = list
	end
	table.insert(list, code)
end

local function get_char_size(char) --获取单个字符长度
	if not char then
		return 0
	elseif char > 240 then
		return 4
	elseif char > 225 then
		return 3
	elseif char > 192 then
		return 2
	else
		return 1
	end
end

local function utf8_len(str) --获取中文字符长度
	local len = 0
	local currentIndex = 1
	while currentIndex <= #str do
		local char = string.byte(str, currentIndex)
		currentIndex = currentIndex + get_char_size(char)
		len = len + 1
	end
	return len
end

local function utf8_sub(str, startChar, numChars) --截取中文字符串
	local startIndex = 1
	while startChar > 1 do
		local char = string.byte(str, startIndex)
		startIndex = startIndex + get_char_size(char)
		startChar = startChar - 1
	end

	local currentIndex = startIndex

	while numChars > 0 and currentIndex <= #str do
		local char = string.byte(str, currentIndex)
		currentIndex = currentIndex + get_char_size(char)
		numChars = numChars - 1
	end

	return string.sub(str, startIndex, currentIndex - 1)
end

local function build_from_dict(codes_by_char)
	for char, codes in pairs(codes_by_char) do
		if utf8_len(char) == 1 then
			for _, code in ipairs(codes) do
				py_insert(char, code)
			end
		end
	end
end

local built = false
local built_dict = nil

local function ensure()
	local dict = nil
	if rime.is_active() then
		local source = rime.source()
		if source then
			dict = source.codes_by_char
		end
	end
	if built and built_dict == dict then
		return
	end
	py_table = {}
	if dict then
		build_from_dict(dict)
	end
	built = true
	built_dict = dict
end

local function append_to_pinyins(pinyins, suffixes)
	local result = {}
	if #pinyins == 0 then
		pinyins = { "" }
	end
	for i = 1, #pinyins do
		for j = 1, #suffixes do
			table.insert(result, pinyins[i] .. suffixes[j])
		end
	end
	return result
end

-- Returns the list of code combinations for `chars`, used by the labeler to
-- avoid conflicting labels. Characters without a code fall back to themselves.
function M.pinyin(chars)
	ensure()
	local pinyins = {}
	for i = 1, utf8_len(chars) do
		local char = utf8_sub(chars, i, 1)
		if string.len(char) == 1 then
			pinyins = append_to_pinyins(pinyins, { char })
		else
			local char_pinyins = py_table[char]
			if not char_pinyins then
				pinyins = append_to_pinyins(pinyins, { char })
			else
				pinyins = append_to_pinyins(pinyins, char_pinyins)
			end
		end
	end
	local result = {}
	for i = 1, #pinyins do
		table.insert(result, pinyins[i])
	end
	return result
end

return M
