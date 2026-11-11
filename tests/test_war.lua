local galaxy = obsidian.module("src/galaxy")
local War = obsidian.module("src/war")

local function loaded(F)
	local w = War.new(galaxy)
	truthy(w:set(F.state(), 1000))
	return w
end

return {
	{ "the map has the HELLDIVERS 2 galaxy", function()
		eq(#galaxy.planets, 273)
		eq(galaxy.planets[1].name, "Super Earth")
		eq(galaxy.planets[1].x, 0)
		for _, p in ipairs(galaxy.planets) do
			truthy(galaxy.sectors[p.sector + 1], "sector of " .. p.name)
		end
		for _, s in ipairs(galaxy.sectors) do
			truthy(#s.shape >= 6 and #s.shape % 2 == 0, "outline of " .. s.name)
			truthy(#s.pieces >= 1, "pieces of " .. s.name)
			for _, piece in ipairs(s.pieces) do truthy(#piece >= 6 and #piece % 2 == 0, "piece of " .. s.name) end
		end
		eq(#galaxy.borders % 6, 0)
		-- Cyborgs left, bugs right, Illuminate below.
		local sums = { {}, {}, {} }
		for _, p in ipairs(galaxy.planets) do
			if p.owner > 0 then
				local s = sums[p.owner]
				s.x, s.y, s.n = (s.x or 0) + p.x, (s.y or 0) + p.y, (s.n or 0) + 1
			end
		end
		truthy(sums[1].x / sums[1].n > 0.4, "bugs right")
		truthy(sums[2].x / sums[2].n < -0.4, "cyborgs left")
		truthy(sums[3].y / sums[3].n < -0.4, "Illuminate below")
	end },
	{ "campaigns and operations by planet and id", function(F)
		local w = loaded(F)
		truthy(#w.campaigns >= 2)
		eq(w.campaigns[1].kind, "defense", "defenses first")
		for _, c in ipairs(w.campaigns) do
			eq(w:campaign(c.planet), c)
			for _, op in ipairs(c.operations) do
				local o, cc = w:operation(op.id)
				eq(o, op)
				eq(cc, c)
			end
		end
		truthy(w:order(), "an active order")
	end },
	{ "owners come from the war, sectors are summed", function(F)
		local w = loaded(F)
		eq(w:owner(0), 0)
		local total = 0
		for _, s in ipairs(galaxy.sectors) do
			local info = w:sector(s.id)
			total = total + info.total
			eq(info.held[0] + info.held[1] + info.held[2] + info.held[3], info.total)
		end
		eq(total, #galaxy.planets)
	end },
	{ "countdowns run from the moment the state came", function(F)
		local w = loaded(F)
		eq(w:left(100, 1030), 70)
		eq(w:left(10, 1030), 0)
		eq(War.clock(3661), "01:01:01")
		eq(War.clock(90061), "1D 01:01:01")
	end },
	{ "operation keys go both ways", function()
		eq(War.op_key({ id = 42 }), "evowar_op_42")
		eq(War.op_of_key("evowar_op_42"), 42)
		eq(War.op_of_key("planet_12"), nil)
	end },
	{ "a state without owners is refused", function()
		local w = War.new(galaxy)
		eq(w:set({ campaigns = {} }, 0), false)
		eq(w:ready(), false)
	end },
}
