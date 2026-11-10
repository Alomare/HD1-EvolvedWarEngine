local galaxy = obsidian.module("src/galaxy")
local War = obsidian.module("src/war")
local View = obsidian.module("src/view")
local draw = obsidian.module("src/draw")

local function setup(F)
	local w = War.new(galaxy)
	w:set(F.state(), 1000)
	local v = View.new(galaxy)
	v:snap()
	return w, v
end

local function settle(v)
	for _ = 1, 400 do v:update(1 / 30) end
end

-- Draws a frame so the buttons of this level are known, as in the game.
local function frame(F, w, v)
	draw.frame(F.kit(), { v = v, war = w, now = 1000, T = F.text, G = function() return nil end, online = true })
end

local function has(acts, kind)
	for _, a in ipairs(acts) do
		if a[1] == kind then return a end
	end
end

local function liberation(w)
	for _, c in ipairs(w.campaigns) do
		if c.kind == "liberation" then return c end
	end
end

return {
	{ "a click on a sector zooms into it", function(F)
		local w, v = setup(F)
		local c = liberation(w)
		local p = galaxy.planets[c.planet + 1]
		local sx, sy = v:to_screen(p.x, p.y)
		local acts = v:input({ cursor = { x = sx, y = sy }, click = true }, w, true)
		eq(v.level, "sector")
		eq(v.sector, p.sector)
		truthy(has(acts, "sound"))
		settle(v)
		truthy(v:zoom() > 2.5, "zoomed")
	end },
	{ "sector, planet, operation, mission: the launch", function(F)
		local w, v = setup(F)
		local c = liberation(w)
		local p = galaxy.planets[c.planet + 1]
		v:go("sector", p.sector)
		settle(v)
		local sx, sy = v:to_screen(p.x, p.y)
		v:input({ cursor = { x = sx, y = sy }, click = true }, w, true)
		eq(v.level, "planet")
		eq(v.planet, c.planet)
		settle(v)
		-- Turn the globe to the first operation and click it where it shows.
		local op = c.operations[1]
		v.yaw_to, v.pitch_to = -op.lon, op.lat
		settle(v)
		local ox, oy, oz = v:op_point(op)
		truthy(oz > 0.9, "facing")
		v:input({ cursor = { x = ox, y = oy }, click = true }, w, true)
		eq(v.level, "operation")
		eq(v.op, op.id)
		settle(v)
		local m = War.next_mission(op)
		local la, lo = View.mission_offset(m, #op.missions, op.lat)
		local mx, my, mz = v:op_point(op, la, lo)
		truthy(mz > 0)
		local acts = v:input({ cursor = { x = mx, y = my }, click = true }, w, true)
		local launch = has(acts, "launch")
		truthy(launch, "a launch")
		eq(launch[2], c)
		eq(launch[3], op)
		eq(launch[4], m)
	end },
	{ "only the host launches; a done mission stays shut", function(F)
		local w, v = setup(F)
		local c = liberation(w)
		local op = c.operations[1]
		v:go("planet", c.planet)
		v:go("operation", op.id)
		local acts = {}
		v:choose({ kind = "mission", id = War.next_mission(op) }, w, false, function(...) acts[#acts + 1] = { ... } end)
		eq(has(acts, "launch"), nil)
		eq(has(acts, "notice")[2], "notice_host")
		for _, mm in ipairs(op.missions) do
			if mm.done then
				local i
				for k, x in ipairs(op.missions) do if x == mm then i = k end end
				acts = {}
				v:choose({ kind = "mission", id = i }, w, true, function(...) acts[#acts + 1] = { ... } end)
				eq(has(acts, "launch"), nil)
				eq(has(acts, "notice")[2], "notice_done")
			end
		end
	end },
	{ "back climbs a level, then leaves the map", function(F)
		local w, v = setup(F)
		local c = liberation(w)
		v:go("planet", c.planet)
		v:go("operation", c.operations[1].id)
		v:input({ back = true }, w, true)
		eq(v.level, "planet")
		v:input({ back = true }, w, true)
		eq(v.level, "sector")
		v:input({ back = true }, w, true)
		eq(v.level, "galaxy")
		local acts = v:input({ back = true }, w, true)
		truthy(has(acts, "exit"))
	end },
	{ "keys and pads walk the campaigns", function(F)
		local w, v = setup(F)
		v:input({ right = true }, w, true)
		eq(v.focus.kind, "sector")
		v:input({ select = true }, w, true)
		eq(v.level, "sector")
		v:input({ right = true }, w, true)
		eq(v.focus.kind, "planet")
	end },
	{ "a campaign row opens that planet", function(F)
		local w, v = setup(F)
		frame(F, w, v)
		local row
		for _, b in ipairs(v.buttons) do
			if b.action and b.action.kind == "campaign" then row = b break end
		end
		truthy(row, "a campaign row")
		v:input({ cursor = { x = row.x + 10, y = row.y + 10 }, click = true }, w, true)
		eq(v.level, "planet")
		eq(v.planet, row.action.id)
	end },
	{ "a drag turns the globe and doesn't click", function(F)
		local w, v = setup(F)
		local c = liberation(w)
		v:go("planet", c.planet)
		settle(v)
		local yaw = v.yaw
		v:input({ cursor = { x = 700, y = 500 }, pressed = true, down = true }, w, true)
		v:input({ cursor = { x = 760, y = 500 }, down = true }, w, true)
		local acts = v:input({ cursor = { x = 800, y = 500 }, down = false, click = true }, w, true)
		truthy(math.abs(v.yaw - yaw) > 5, "turned")
		eq(v.level, "planet", "still on the planet")
		eq(has(acts, "launch"), nil)
	end },
	{ "picking the galaxy finds the planet territory", function()
		local v = View.new(galaxy)
		for _, p in ipairs(galaxy.planets) do
			-- A point near the planet is in its own territory or a neighbour's: never outside.
			local id = v:planet_at(p.x + 0.001, p.y + 0.001)
			truthy(id ~= nil, p.name)
		end
		eq(v:planet_at(2, 2), nil)
	end },
}
