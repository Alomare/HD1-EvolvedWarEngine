local galaxy = obsidian.module("src/galaxy")
local War = obsidian.module("src/war")
local launch = obsidian.module("src/launch")

-- DifficultySettings.get_mission_params, as the game decodes a seed (difficulty_settings.lua:143).
local function decode(seed)
	local p = {}
	p.tod = math.floor(seed / 1000000) % 10 % 4
	p.shading = math.floor(seed / 100000) % 10 % 6
	p.env = math.floor(seed / 10000) % 10 % 6
	p.variant = math.floor(seed / 1000) % 10 % 6
	p.enemy = math.floor(seed / 100) % 10 % 3
	p.kind = math.floor((seed % 100) / 20) % 5
	p.difficulty = math.max(1, math.min(15, (seed % 100) % 20))
	return p
end

return {
	{ "seeds hold what the game reads back", function()
		local s = launch.seed(2, 3, 1, 2, 2, 11, 1888136961, 3)
		local p = decode(s)
		eq(p.tod, 3)
		eq(p.shading, 2)
		eq(p.env, 3)
		eq(p.variant, 1)
		eq(p.enemy, 2)
		eq(p.kind, 2)
		eq(p.difficulty, 11)
		eq(math.floor(s / 10000000), math.floor(1888136961 / 10000000), "the random part")
	end },
	{ "a planet record for the hellpods", function(F)
		local w = War.new(galaxy)
		w:set(F.state(), 0)
		local c = w.campaigns[2]
		local op = c.operations[1]
		local p = galaxy.planets[c.planet + 1]
		local slot = { reward = "xp_boost_x2", position = 4, region = 3 }
		local r = launch.record(op, c, p, 2, slot, function(d, n) return 6 end)
		eq(r.name, "evowar_op_" .. op.id)
		eq(r.enemy, c.faction)
		eq(r.environment, p.env)
		eq(r.difficulty, op.difficulty)
		eq(r.selected_mission_index, 2)
		eq(r.reward, "xp_boost_x2")
		eq(r.position, 4)
		eq(r.region, 3)
		eq(#r.missions, #op.missions)
		for i, m in ipairs(r.missions) do
			local d = decode(m.seed)
			eq(d.enemy, c.faction - 1)
			eq(d.env, p.env)
			eq(d.difficulty, op.difficulty)
			eq(m.completed, op.missions[i].done == true)
			eq(m.num_research_samples, 6 / #op.missions == math.floor(6 / #op.missions) and 6 / #op.missions or math.min(6, math.ceil(6 / #op.missions)))
		end
	end },
	{ "the report names the operation and counts once a squad", function()
		local launched = { key = "evowar_op_7", campaign = 3, op = 7, mission = 2 }
		local r = launch.report({ planet_name = "evowar_op_7", mission_completed = true, initial_host = "abc", mission_seed = 123, total_deaths = 4 }, launched)
		eq(r.campaign, 3)
		eq(r.operation, 7)
		eq(r.mission, 1, "from 0 for the server")
		eq(r.success, true)
		eq(r.lobby, "abc:123")
		eq(r.deaths, 4)
		eq(launch.report({ planet_name = "planet_12" }, launched), nil, "not ours")
		local lost = launch.report({ planet_name = "evowar_op_7", mission_completed = false }, launched)
		eq(lost.success, false)
	end },
}
