-- Draws the map offline for each level and writes the draw calls to internal/preview/<name>.json, for
-- tools/render_preview.py to turn into pictures. Run from the mod folder:
--   luajit tools/preview.lua
-- The war state is tests/fixtures/state.json (tools/fixture_state.py).
local F = dofile("tests/fake.lua")
F.install()
local json = obsidian.module("src/json")
local galaxy = obsidian.module("src/galaxy")
local War = obsidian.module("src/war")
local View = obsidian.module("src/view")
local draw = obsidian.module("src/draw")

local G = {
	campaign_faction_bugs = "BUGS", campaign_faction_cyborgs = "CYBORGS", campaign_faction_illuminates = "ILLUMINATES",
	campaign_faction_superearth = "SUPER EARTH", campaign_planet_difficulty = "DIFFICULTY",
}
-- The game names the 15 difficulties itself (campaign_planet_difficulty_<n>); the preview shows numbers.

local war = War.new(galaxy)
war:set(F.state(), 1000)

local function shot(name, setup)
	local v = View.new(galaxy)
	setup(v)
	local kit = F.kit()
	draw.frame(kit, {
		v = v, war = war, now = 1000, T = F.text, G = function(k) return G[k] end, online = true,
		keys = { { "E", F.text("key_select") }, { "WHEEL", F.text("key_zoom") }, { "Q", F.text("key_back") } },
	})
	os.execute("mkdir internal\\preview 2>nul")
	local f = assert(io.open("internal/preview/" .. name .. ".json", "wb"))
	f:write(json.encode({ name = name, ops = kit.ops }))
	f:close()
	print(name .. ": " .. #kit.ops .. " draw calls")
end

local lib = war.campaigns[#war.campaigns]
for _, c in ipairs(war.campaigns) do
	if c.kind == "liberation" then lib = c break end
end
local planet = galaxy.planets[lib.planet + 1]

shot("1-galaxy", function(v)
	v:snap()
	v.t = 2.1
	v.hover = { kind = "sector", id = planet.sector }
end)
shot("2-sector", function(v)
	v:go("sector", planet.sector)
	v:snap()
	v.t = 2.1
	v.hover = { kind = "planet", id = planet.id }
end)
shot("3-planet", function(v)
	v:go("planet", planet.id)
	v:snap()
	v.t = 2.1
	v.yaw, v.pitch = 200, 16
	v.hover = { kind = "op", id = lib.operations[2].id }
end)
shot("4-operation", function(v)
	local op = lib.operations[1]
	v:go("planet", planet.id)
	v:go("operation", op.id)
	v:snap()
	v.t = 2.1
	v.yaw, v.pitch = -op.lon, op.lat
	v.mission = 2
end)
shot("5-ftl", function(v)
	local op = lib.operations[1]
	v:go("planet", planet.id)
	v:go("operation", op.id)
	v:snap()
	v.yaw, v.pitch = -op.lon, op.lat
	v:start_ftl(lib, op, 2)
	v.ftl.t = 0.62
end)
local def
for _, c in ipairs(war.campaigns) do
	if c.kind == "defense" then def = c end
end
if def then
	shot("6-defense", function(v)
		v:go("planet", def.planet)
		v:snap()
		v.t = 1.3
		v.yaw, v.pitch = 40, 16
	end)
end
