-- What the offline tests and the previews stand in for: the loader's obsidian table (modules and
-- text from locales/en.json) and a kit that records every draw call instead of drawing.
local F = {}

local loaded = {}
local texts

function F.install()
	obsidian = {
		module = function(name)
			if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
			return loaded[name]
		end,
		log = function() end,
		game_text = function() end,
	}
	local json = obsidian.module("src/json")
	local f = assert(io.open("locales/en.json", "rb"))
	texts = assert(json.decode(f:read("*a")))
	f:close()
	obsidian.text = function(key, ...)
		local t = texts[key]
		if not t then return key end
		local ok, s = pcall(string.format, t, ...)
		return ok and s or t
	end
	table.clone = table.clone or function(t)
		local out = {}
		for k, v in pairs(t) do out[k] = type(v) == "table" and table.clone(v) or v end
		return out
	end
	return obsidian
end

function F.text(key, ...)
	return obsidian.text(key, ...)
end

-- The war state the fixture holds (tools/fixture_state.py), decoded.
function F.state()
	local json = obsidian.module("src/json")
	local f = assert(io.open("tests/fixtures/state.json", "rb"))
	local s = assert(json.decode(f:read("*a")))
	f:close()
	return s
end

-- A kit that keeps what it was asked to draw.
local Kit = {}
Kit.__index = Kit

function F.kit()
	return setmetatable({ ops = {}, z = 700, alpha = 1, area = nil }, Kit)
end

local function col(c)
	if type(c) == "string" then
		local r, g, b, a = c:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
		c = { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), a ~= "" and tonumber(a, 16) or 255 }
	elseif type(c) ~= "table" then
		c = { 255, 255, 255 }
	end
	for i = 1, 3 do assert(type(c[i]) == "number" and c[i] == c[i], "colour channel " .. i) end
	return { c[1], c[2], c[3], c[4] or 255 }
end

local function push(self, op)
	op.z = self.z
	op.clip = self.area and { self.area.x, self.area.y, self.area.w, self.area.h } or nil
	self.ops[#self.ops + 1] = op
end

function Kit:layer(n) if n then self.z = n end return self.z end
function Kit:opacity(a) if a then self.alpha = a end return self.alpha end
function Kit:point(x, y) return x, y end
function Kit:rect(x, y, w, h, c) push(self, { op = "rect", x = x, y = y, w = w, h = h, c = col(c) }) end
function Kit:poly(points, c)
	assert(#points >= 6 and #points % 2 == 0, "poly points")
	for _, v in ipairs(points) do assert(v == v and v ~= math.huge and v ~= -math.huge, "poly point not finite") end
	push(self, { op = "poly", pts = points, c = col(c) })
end
function Kit:outline(points, c, width) push(self, { op = "outline", pts = points, c = col(c), width = width or 1 }) end
function Kit:panel(p) push(self, { op = "rect", x = p[1] or p.x, y = p[2] or p.y, w = p[3] or p.w, h = p[4] or p.h, c = col(p.fill) }) end
function Kit:text(s, x, y, opts)
	assert(type(s) == "string", "text")
	assert(x == x and y == y, "text position")
	opts = opts or {}
	push(self, { op = "text", s = s, x = x, y = y, size = opts.size or 18, align = opts.align or "left", c = col(opts.color), font = opts.font or "body", tracking = opts.tracking })
end
function Kit:measure(s, opts)
	opts = opts or {}
	local size = opts.size or 18
	local n = #tostring(s):gsub("[\128-\191]", "")
	return n * size * 0.56 + n * (opts.tracking or 0), size
end
function Kit:bar(x, y, w, h, value, c, back)
	if back then self:rect(x, y, w, h, back) end
	self:rect(x, y, w * math.max(0, math.min(1, value or 0)), h, c)
end
function Kit:icon(name, x, y, w, h, c, uv) push(self, { op = "icon", name = name, x = x, y = y, w = w, h = h, c = col(c) }) return true end
function Kit:art() return false end
function Kit:glyph(name, x, y, size, c) push(self, { op = "glyph", name = name, x = x, y = y, size = size, c = col(c) }) return true end
function Kit:clip(x, y, w, h, fn)
	local outer = self.area
	self.area = { x = x, y = y, w = w, h = h }
	local ok, err = pcall(fn, self)
	self.area = outer
	if not ok then error(err, 0) end
end

return F
