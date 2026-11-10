-- The war as the map reads it: the last state from the war server (GET evolved/state), with
-- lookups by planet and sector. No game calls, so the tests drive it directly.
local M = {}
M.__index = M

local floor, max = math.floor, math.max

function M.new(galaxy)
	return setmetatable({ g = galaxy, state = nil, fetched = 0, by_planet = {}, sectors = {}, campaigns = {}, ops = {} }, M)
end

local function list(t)
	local out = {}
	if type(t) ~= "table" then return out end
	for i = 1, t.n or #t do
		if t[i] ~= nil then out[#out + 1] = t[i] end
	end
	return out
end

-- Takes a new state. `now` is the time it arrived, in seconds, for the countdowns.
function M:set(state, now)
	if type(state) ~= "table" or type(state.owners) ~= "table" then return false end
	self.state = state
	self.fetched = now or 0
	self.by_planet, self.ops = {}, {}
	self.campaigns = list(state.campaigns)
	for _, c in ipairs(self.campaigns) do
		c.operations = list(c.operations)
		for _, op in ipairs(c.operations) do
			op.missions = list(op.missions)
			self.ops[op.id] = { op = op, campaign = c }
		end
		self.by_planet[c.planet] = c
	end
	-- Defenses first, soonest deadline first; then liberations, furthest along first.
	table.sort(self.campaigns, function(a, b)
		if a.kind ~= b.kind then return a.kind == "defense" end
		if a.kind == "defense" then return (a.ends_in or 0) < (b.ends_in or 0) end
		return (a.liberation or 0) > (b.liberation or 0)
	end)
	self.orders = list(state.orders)
	self.news = list(state.news)
	self:summarize()
	return true
end

function M:ready()
	return self.state ~= nil
end

function M:planet(id)
	return self.g.planets[id + 1]
end

function M:owner(id)
	local o = self.state and self.state.owners[id + 1]
	if o == nil then
		local p = self:planet(id)
		return p and p.owner or 0
	end
	return o
end

function M:campaign(id)
	return self.by_planet[id]
end

-- The operation with this id and its campaign.
function M:operation(id)
	local e = self.ops[id]
	if e then return e.op, e.campaign end
end

-- Per sector: how many planets each faction holds, the main enemy there, and its campaigns.
function M:summarize()
	self.sectors = {}
	for _, s in ipairs(self.g.sectors) do
		local held, campaigns = { [0] = 0, 0, 0, 0 }, {}
		for _, pid in ipairs(s.planets) do
			local o = self:owner(pid)
			held[o] = (held[o] or 0) + 1
			local c = self.by_planet[pid]
			if c then campaigns[#campaigns + 1] = c end
		end
		local enemy, most = 0, 0
		for f = 1, 3 do
			if held[f] > most then enemy, most = f, held[f] end
		end
		local owner = held[0] >= most and 0 or enemy
		self.sectors[s.id] = { held = held, enemy = enemy, owner = owner, total = #s.planets, campaigns = campaigns }
	end
end

function M:sector(id)
	return self.sectors[id]
end

-- The active Major Order, or nil.
function M:order()
	for _, o in ipairs(self.orders or {}) do
		if o.state == "active" then return o end
	end
end

-- Seconds left on a countdown the server sent `seconds` ago, at `now`.
function M:left(seconds, now)
	if type(seconds) ~= "number" then return nil end
	return max(0, seconds - ((now or self.fetched) - self.fetched))
end

-- 1D 04:12:09, or 04:12:09 under a day.
function M.clock(seconds)
	if not seconds then return "" end
	seconds = floor(seconds)
	local d = floor(seconds / 86400)
	local h = floor(seconds / 3600) % 24
	local m = floor(seconds / 60) % 60
	local s = seconds % 60
	if d > 0 then return string.format("%dD %02d:%02d:%02d", d, h, m, s) end
	return string.format("%02d:%02d:%02d", h, m, s)
end

-- The game text key the ship and the loading screen show for an operation.
function M.op_key(op)
	return "evowar_op_" .. tostring(op.id)
end

-- The operation id in such a key, or nil.
function M.op_of_key(key)
	return tonumber(type(key) == "string" and key:match("^evowar_op_(%d+)$") or nil)
end

-- Whether the operation still has a mission to play, and the first one.
function M.next_mission(op)
	for i, m in ipairs(op.missions) do
		if not m.done then return i end
	end
end

return M
