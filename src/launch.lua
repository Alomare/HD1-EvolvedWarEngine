-- From an operation on the map to a HELLDIVERS planet record, and from the end of a mission back to a
-- report for the war server.
--
-- The game plays a planet as a list of missions, each a seed that holds the time of day, shading,
-- environment, variant, enemy, mission type and difficulty (DifficultySettings.modulate_seed). An
-- operation is exactly that: the record built here goes where the galaxy map puts the planet the
-- player picked, and the game does the rest (the jump, the hellpods, the briefing, the drop).
local war_mod = obsidian.module("src/war")

local M = {}

local floor = math.floor

-- DifficultySettings.modulate_seed, in the order modulate_seed_for_planet takes its values.
-- shading 0-2, env 0-4, variant 0-2, enemy 0-2 (bugs, cyborgs, illuminates), kind 0 mission or
-- 2 extermination, difficulty 1-15, random up to 2147483646, tod 0-3.
function M.seed(shading, env, variant, enemy, kind, difficulty, random, tod)
	local s = floor(random / 10000000) * 10000000
	s = s + 1000000 * (tod % 4)
	s = s + 100000 * (shading % 6)
	s = s + 10000 * (env % 6)
	s = s + 1000 * (variant % 6)
	s = s + 100 * (enemy % 3)
	s = s + (kind % 5) * 20
	return s + math.max(1, math.min(15, difficulty))
end

-- The planet record for mission `index` of `op` (a campaign operation) on planet `p` (src/galaxy).
-- slot: the planet record it takes the place of in the save (its position, region and reward are
-- kept, so the game's own lists stay valid). samples(difficulty, missions): research samples for the
-- whole planet, or nil.
function M.record(op, campaign, p, index, slot, samples)
	local enemy = campaign.faction                       -- 1 bugs, 2 cyborgs, 3 illuminates
	local env = p.env
	local n = #op.missions
	local total = samples and samples(op.difficulty, n) or 0
	local each = n > 0 and math.ceil(total / n) or 0
	local missions = {}
	for i, m in ipairs(op.missions) do
		missions[i] = {
			seed = M.seed(op.shading, env, op.variant, enemy - 1, m.kind or 0, op.difficulty, m.random or 0, m.tod or 1),
			completed = m.done == true,
			num_research_samples = math.min(total, each),
		}
	end
	slot = slot or {}
	return {
		name = war_mod.op_key(op),
		seed = op.seed,
		difficulty = op.difficulty,
		enemy = enemy,
		environment = env,
		environment_variant = op.variant,
		shading_environment = op.shading,
		missions = missions,
		completed = false,
		is_scanned = true,
		reward = slot.reward,
		position = slot.position,
		region = slot.region,
		total_deaths = 0, total_kills = 0, total_shots = 0,
		selected_mission_index = index,
	}
end

-- What the war server gets when a mission of ours ends. params: what StateMissionEnd.on_enter
-- receives. launched: the operation the host started ({ campaign, op, mission, key }).
function M.report(params, launched)
	if type(params) ~= "table" or type(launched) ~= "table" then return nil end
	if params.planet_name ~= launched.key then return nil end
	return {
		campaign = launched.campaign,
		operation = launched.op,
		mission = launched.mission - 1,                 -- the server counts missions from 0
		success = params.mission_completed == true,
		-- The same for every player of the mission: the host who started it and the mission seed.
		lobby = tostring(params.initial_host or "") .. ":" .. tostring(params.mission_seed or ""),
		kills = tonumber(params.genocide_kills) or 0,
		deaths = tonumber(params.total_deaths) or 0,
	}
end

return M
