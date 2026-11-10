-- JSON in and out for the war server's answers and the mission reports. Plain Lua, so it reads the
-- same in the game and in the offline tests: null becomes nil, so a list with nulls keeps its length in
-- `n`, and numbers stay numbers.
local M = {}

local byte, sub, find, char, concat = string.byte, string.sub, string.find, string.char, table.concat
local tonumber, tostring, type, pairs, ipairs, floor = tonumber, tostring, type, pairs, ipairs, math.floor

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8(code)
	if code < 0x80 then return char(code) end
	if code < 0x800 then return char(0xC0 + floor(code / 0x40), 0x80 + code % 0x40) end
	if code < 0x10000 then
		return char(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return char(0xF0 + floor(code / 0x40000), 0x80 + floor(code / 0x1000) % 0x40, 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function fail(s, i, what)
	error("json: " .. what .. " at " .. i .. " near '" .. sub(s, i, i + 12) .. "'", 0)
end

local function skip(s, i)
	local _, e = find(s, "^[ \t\r\n]*", i)
	return e + 1
end

local value

local function str(s, i)
	local out, start = {}, i + 1
	local j = start
	while true do
		local c = byte(s, j)
		if not c then fail(s, i, "unclosed text") end
		if c == 34 then
			out[#out + 1] = sub(s, start, j - 1)
			return concat(out), j + 1
		elseif c == 92 then
			out[#out + 1] = sub(s, start, j - 1)
			local e = sub(s, j + 1, j + 1)
			if e == "u" then
				local code = tonumber(sub(s, j + 2, j + 5), 16)
				if not code then fail(s, j, "bad escape") end
				j = j + 6
				-- A surrogate pair.
				if code >= 0xD800 and code <= 0xDBFF and sub(s, j, j + 1) == "\\u" then
					local low = tonumber(sub(s, j + 2, j + 5), 16)
					if low and low >= 0xDC00 and low <= 0xDFFF then
						code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
						j = j + 6
					end
				end
				out[#out + 1] = utf8(code)
			else
				local r = ESCAPES[e]
				if not r then fail(s, j, "bad escape") end
				out[#out + 1] = r
				j = j + 2
			end
			start = j
		else
			j = j + 1
		end
	end
end

local function arr(s, i)
	local out, n = {}, 0
	i = skip(s, i + 1)
	if sub(s, i, i) == "]" then
		out.n = 0
		return out, i + 1
	end
	while true do
		local v
		v, i = value(s, i)
		n = n + 1
		out[n] = v
		i = skip(s, i)
		local c = sub(s, i, i)
		if c == "]" then
			out.n = n
			return out, i + 1
		end
		if c ~= "," then fail(s, i, "expected , or ]") end
		i = skip(s, i + 1)
	end
end

local function obj(s, i)
	local out = {}
	i = skip(s, i + 1)
	if sub(s, i, i) == "}" then return out, i + 1 end
	while true do
		if sub(s, i, i) ~= '"' then fail(s, i, "expected a key") end
		local k
		k, i = str(s, i)
		i = skip(s, i)
		if sub(s, i, i) ~= ":" then fail(s, i, "expected :") end
		local v
		v, i = value(s, skip(s, i + 1))
		out[k] = v
		i = skip(s, i)
		local c = sub(s, i, i)
		if c == "}" then return out, i + 1 end
		if c ~= "," then fail(s, i, "expected , or }") end
		i = skip(s, i + 1)
	end
end

value = function(s, i)
	i = skip(s, i)
	local c = sub(s, i, i)
	if c == "{" then return obj(s, i) end
	if c == "[" then return arr(s, i) end
	if c == '"' then return str(s, i) end
	if sub(s, i, i + 3) == "true" then return true, i + 4 end
	if sub(s, i, i + 4) == "false" then return false, i + 5 end
	if sub(s, i, i + 3) == "null" then return nil, i + 4 end
	local _, e = find(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
	if e then
		local v = tonumber(sub(s, i, e))
		if v then return v, e + 1 end
	end
	fail(s, i, "unexpected text")
end

-- The value of a JSON text, or nil and the reason.
function M.decode(s)
	if type(s) ~= "string" then return nil, "not text" end
	local ok, v, i = pcall(value, s, 1)
	if not ok then return nil, v end
	if skip(s, i) <= #s then return nil, "json: text after the value" end
	return v
end

local function quote(s)
	return '"' .. (s:gsub('[%c"\\]', function(c)
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return string.format("\\u%04x", byte(c))
	end)) .. '"'
end

local encode

local function is_list(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
		n = n + 1
	end
	for k = 1, n do
		if t[k] == nil then return false end
	end
	return true, n
end

encode = function(v, out)
	local kind = type(v)
	if kind == "nil" then
		out[#out + 1] = "null"
	elseif kind == "boolean" then
		out[#out + 1] = v and "true" or "false"
	elseif kind == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			out[#out + 1] = "null"
		elseif v % 1 == 0 and v > -1e15 and v < 1e15 then
			out[#out + 1] = string.format("%d", v)
		else
			out[#out + 1] = string.format("%.6g", v)
		end
	elseif kind == "string" then
		out[#out + 1] = quote(v)
	elseif kind == "table" then
		local list, n = is_list(v)
		if list and n > 0 then
			out[#out + 1] = "["
			for k = 1, n do
				if k > 1 then out[#out + 1] = "," end
				encode(v[k], out)
			end
			out[#out + 1] = "]"
		else
			local keys = {}
			for k in pairs(v) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			out[#out + 1] = "{"
			for k, key in ipairs(keys) do
				if k > 1 then out[#out + 1] = "," end
				out[#out + 1] = quote(key)
				out[#out + 1] = ":"
				encode(v[key] == nil and v[tonumber(key)] or v[key], out)
			end
			out[#out + 1] = "}"
		end
	else
		error("json: can't write a " .. kind, 0)
	end
end

function M.encode(v)
	local out = {}
	encode(v, out)
	return concat(out)
end

return M
