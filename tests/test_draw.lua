local galaxy = obsidian.module("src/galaxy")
local War = obsidian.module("src/war")
local View = obsidian.module("src/view")
local draw = obsidian.module("src/draw")

local function ctx(F, w, v)
	return { v = v, war = w, now = 1000, T = F.text, G = function() return nil end, online = false,
		keys = { { "E", "Select" }, { "Q", "Back" } } }
end

local function count(kit, op)
	local n = 0
	for _, o in ipairs(kit.ops) do if o.op == op then n = n + 1 end end
	return n
end

return {
	{ "every level draws, with its panel and buttons", function(F)
		local w = War.new(galaxy)
		w:set(F.state(), 1000)
		local c = w.campaigns[#w.campaigns]
		local op = c.operations[1]
		for _, level in ipairs({ "galaxy", "sector", "planet", "operation" }) do
			local v = View.new(galaxy)
			if level ~= "galaxy" then v:go("planet", c.planet) end
			if level == "sector" then v:go("sector") end
			if level == "operation" then v:go("operation", op.id) end
			v:snap()
			for _, t in ipairs({ 0, 0.5, 3.7 }) do
				v.t = t
				local kit = F.kit()
				draw.frame(kit, ctx(F, w, v))
				truthy(count(kit, "poly") > 20, level .. " shapes")
				truthy(count(kit, "text") > 5, level .. " text")
				truthy(#v.buttons > 0, level .. " buttons")
				for _, o in ipairs(kit.ops) do
					truthy(o.z >= 0 and o.z < 876, "layer below the loader menu")
				end
			end
		end
	end },
	{ "the jump draws over everything", function(F)
		local w = War.new(galaxy)
		w:set(F.state(), 1000)
		local c = w.campaigns[1]
		local v = View.new(galaxy)
		v:go("planet", c.planet)
		v:go("operation", c.operations[1].id)
		v:snap()
		v:start_ftl(c, c.operations[1], 1)
		v.ftl.t = 0.9
		local kit = F.kit()
		draw.frame(kit, ctx(F, w, v))
		local top = 0
		for _, o in ipairs(kit.ops) do top = math.max(top, o.z) end
		local last = kit.ops[#kit.ops]
		eq(last.z, top)
	end },
	{ "a war with no campaigns still draws", function(F)
		local s = F.state()
		s.campaigns = { n = 0 }
		s.orders = { n = 0 }
		s.news = { n = 0 }
		local w = War.new(galaxy)
		w:set(s, 0)
		local v = View.new(galaxy)
		v:snap()
		draw.frame(F.kit(), ctx(F, w, v))
		v:go("planet", 5)
		v:snap()
		draw.frame(F.kit(), ctx(F, w, v))
	end },
	{ "text wraps to the width", function(F)
		local kit = F.kit()
		local lines = draw.wrap(kit, "Win thirty missions against the Cyborg forces before the deadline", 200, { size = 16 })
		truthy(#lines > 1)
		for _, l in ipairs(lines) do truthy(kit:measure(l, { size = 16 }) <= 200 or not l:find(" ")) end
	end },
}
