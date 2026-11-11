-- Where the map looks and what the player points at: four levels, each a zoom into the one before.
--
--   galaxy     the whole galaxy, sectors tinted by who holds them
--   sector     one sector; its planets show as small globes
--   planet     one globe, turning; its operations sit on the surface
--   operation  closer still, the globe turned to the operation; its missions show around it
--
-- Coordinates: the galaxy in map units (Super Earth at 0, 0, y up), the screen in a 1920x1080 frame
-- with y up (the kit's). The camera is a point of the map, a scale in pixels per map unit, and the
-- point of the screen it sits on. Everything moves by easing toward the target, so a click zooms.
-- No game calls here: input comes in as a table, and what the game must do goes out as actions.
local sphere = obsidian.module("src/sphere")

local M = {}
M.__index = M

local exp, log, min, max, abs, sqrt, floor = math.exp, math.log, math.min, math.max, math.abs, math.sqrt, math.floor

M.W, M.H = 1920, 1080
M.PLANET_R = 0.012             -- a globe radius, in map units
M.OPERATION_ZOOM = 1.55        -- the operation level, over the planet level
M.SIDE = 460                   -- the width of a side column of panels (src/draw)
M.MARGIN = 50                  -- from the edge of the window to the panels
M.LEVELS = { "galaxy", "sector", "planet", "operation" }
M.DEPTH = { galaxy = 1, sector = 2, planet = 3, operation = 4 }
M.PITCH = 16                   -- the globe tilt on the planet level, in degrees
M.SPIN = 5                     -- idle turn, degrees a second
M.FTL_SECONDS = 1.1

local function ease(dt, rate)
	return 1 - exp(-dt * rate)
end

function M.new(galaxy)
	local v = setmetatable({
		g = galaxy,
		level = "galaxy", sector = nil, planet = nil, op = nil, mission = 1,
		cam = { x = 0, y = 0, s = 1, cx = 0, cy = 0 },
		target = { x = 0, y = 0, s = 1, cx = 0, cy = 0 },
		yaw = 0, pitch = M.PITCH, yaw_to = nil, pitch_to = nil,
		hover = nil, focus = nil, buttons = {}, t = 0, cursor = nil,
		drag = nil, ftl = nil, notice = nil,
	}, M)
	v:set_screen(nil)
	v:snap()
	return v
end

-- The part of the frame the window shows, { l, b, r, t } in frame units: the frame scales with the
-- player's ui_scale, so at 0.8 the window shows more than 1920x1080 of it. The galaxy takes the same
-- share of the window at any ui_scale; the panels keep the game's scale and sit at the window edges.
function M:set_screen(ext)
	ext = ext or { l = 0, b = 0, r = M.W, t = M.H }
	local e = self.ext
	if e and abs(e.l - ext.l) < 0.5 and abs(e.r - ext.r) < 0.5 and abs(e.b - ext.b) < 0.5 and abs(e.t - ext.t) < 0.5 then return end
	self.ext = { l = ext.l, b = ext.b, r = ext.r, t = ext.t }
	local w, h = ext.r - ext.l, ext.t - ext.b
	local cx = (ext.l + ext.r) / 2
	-- Between the side columns, a little left of the middle: the right column is the wider one.
	local mid = cx - 20
	self.lay = {
		gs = h * 0.41, gx = cx, gy = ext.b + h * 0.465,
		box_w = max(480, w - 2 * (M.SIDE + M.MARGIN + 40)), box_h = h * 0.58, sx = mid, sy = ext.b + h * 0.47,
		pr = h * 0.25, px = mid, py = ext.b + h * 0.46, oy = ext.b + h * 0.44,
	}
	local placed = e ~= nil
	self:aim()
	if not placed then self:snap() end
end

-- ---------------------------------------------------------------- transforms

function M:to_screen(x, y)
	local c = self.cam
	return c.cx + (x - c.x) * c.s, c.cy + (y - c.y) * c.s
end

function M:to_map(sx, sy)
	local c = self.cam
	return c.x + (sx - c.cx) / c.s, c.y + (sy - c.cy) / c.s
end

-- How far the camera has zoomed past the galaxy view, as a factor.
function M:zoom()
	return self.cam.s / self.lay.gs
end

local function smooth(a, b, x)
	local t = max(0, min(1, (x - a) / (b - a)))
	return t * t * (3 - 2 * t)
end
M.smooth = smooth

-- How much of each layer shows at the current zoom, 0 to 1.
function M:layers()
	local z = self:zoom()
	return {
		galaxy = 1 - smooth(9, 26, z),           -- sector shapes, borders, links
		labels = 1 - smooth(2.2, 4.5, z),        -- sector names
		globes = smooth(1.7, 3.4, z),            -- planets drawn as globes with lines
		names = smooth(2.4, 4, z) * (1 - smooth(20, 34, z)),
		surface = smooth(22, 48, z),             -- operations on the focused globe
	}
end

-- A planet's globe radius on screen now.
function M:globe_px()
	return M.PLANET_R * self.cam.s
end

-- ---------------------------------------------------------------- where each level looks

local function sector_frame(g, sid, lay)
	local s = g.sectors[sid + 1]
	local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9
	for _, pid in ipairs(s.planets) do
		local p = g.planets[pid + 1]
		x0, y0, x1, y1 = min(x0, p.x), min(y0, p.y), max(x1, p.x), max(y1, p.y)
	end
	-- Room around the planets for the globes and their names.
	local w, h = (x1 - x0) + 0.11, (y1 - y0) + 0.13
	local scale = min(lay.box_w / w, lay.box_h / h)
	scale = max(lay.gs * 2.6, min(lay.gs * 9, scale))
	return (x0 + x1) / 2, (y0 + y1) / 2 - 0.008, scale
end

function M:aim()
	local t, g, lay = self.target, self.g, self.lay
	if self.level == "galaxy" then
		t.x, t.y, t.s, t.cx, t.cy = 0, 0, lay.gs, lay.gx, lay.gy
	elseif self.level == "sector" then
		t.x, t.y, t.s = sector_frame(g, self.sector, lay)
		t.cx, t.cy = lay.sx, lay.sy
	else
		local p = g.planets[self.planet + 1]
		t.x, t.y = p.x, p.y
		t.s = lay.pr / M.PLANET_R * (self.level == "operation" and M.OPERATION_ZOOM or 1)
		t.cx, t.cy = lay.px, self.level == "operation" and lay.oy or lay.py
	end
end

-- Snaps the camera to the target (a fresh screen, the tests).
function M:snap()
	self:aim()
	for k, val in pairs(self.target) do self.cam[k] = val end
end

-- ---------------------------------------------------------------- moving between levels

function M:go(level, what)
	local before = self.level
	self.level = level
	if level == "galaxy" then
		self.planet, self.op = nil, nil
	elseif level == "sector" then
		self.sector = what or self.sector
		self.planet, self.op = nil, nil
	elseif level == "planet" then
		if what then
			self.planet = what
			self.sector = self.g.planets[what + 1].sector
		end
		self.op = nil
		self.yaw_to, self.pitch_to = nil, M.PITCH
	elseif level == "operation" then
		self.op = what or self.op
		self.mission = 1
	end
	self.focus = nil
	self:aim()
	return before ~= level
end

function M:back()
	local d = M.DEPTH[self.level]
	if d <= 1 then return false end
	local up = M.LEVELS[d - 1]
	self:go(up)
	return true
end

-- ---------------------------------------------------------------- frame update

function M:update(dt)
	self.t = self.t + dt
	local c, t = self.cam, self.target
	local k = ease(dt, 6.5)
	c.x = c.x + (t.x - c.x) * k
	c.y = c.y + (t.y - c.y) * k
	c.cx = c.cx + (t.cx - c.cx) * k
	c.cy = c.cy + (t.cy - c.cy) * k
	c.s = exp(log(c.s) + (log(t.s) - log(c.s)) * k)
	-- The globe: an operation turns to face the viewer; otherwise it turns slowly unless dragged.
	if self.yaw_to then
		local kk = ease(dt, 5)
		self.yaw = self.yaw + sphere.turn(self.yaw, self.yaw_to) * kk
		self.pitch = self.pitch + (self.pitch_to - self.pitch) * kk
	elseif not self.drag then
		self.yaw = (self.yaw + M.SPIN * dt) % 360
		if self.pitch_to then self.pitch = self.pitch + (self.pitch_to - self.pitch) * ease(dt, 3) end
	end
	if self.ftl then self.ftl.t = self.ftl.t + dt end
	if self.notice then
		self.notice.t = self.notice.t - dt
		if self.notice.t <= 0 then self.notice = nil end
	end
end

-- Whether the camera has about reached its target.
function M:settled()
	local c, t = self.cam, self.target
	return abs(log(c.s / t.s)) < 0.02 and abs(c.x - t.x) * c.s < 2 and abs(c.y - t.y) * c.s < 2
end

-- ---------------------------------------------------------------- picking

local function inside(cell, x, y)
	local n = #cell / 2
	local sign = 0
	for i = 1, n do
		local j = i % n + 1
		local ax, ay, bx, by = cell[i * 2 - 1], cell[i * 2], cell[j * 2 - 1], cell[j * 2]
		local cross = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
		if cross ~= 0 then
			local s = cross > 0 and 1 or -1
			if sign == 0 then sign = s elseif s ~= sign then return false end
		end
	end
	return true
end
M.inside = inside

-- The sector whose outline holds the map point (one of the convex pieces of the outline), or nil
-- outside the galaxy.
function M:sector_at(x, y)
	if x * x + y * y > self.g.rim * self.g.rim then return nil end
	for _, s in ipairs(self.g.sectors) do
		for _, piece in ipairs(s.pieces) do
			if inside(piece, x, y) then return s.id end
		end
	end
end

-- The nearest planet drawn as a globe under a screen point.
function M:globe_at(sx, sy)
	local r = max(self:globe_px() + 6, 14)
	local best, bd
	for _, p in ipairs(self.g.planets) do
		local x, y = self:to_screen(p.x, p.y)
		local d = (x - sx) ^ 2 + (y - sy) ^ 2
		if d < r * r and (not bd or d < bd) then best, bd = p.id, d end
	end
	return best
end

-- Where an operation sits on the focused globe: screen x, y and depth (> 0 on the near side).
function M:op_point(op, lat_off, lon_off)
	local p = self.g.planets[self.planet + 1]
	local cx, cy = self:to_screen(p.x, p.y)
	local r = self:globe_px()
	local x, y, z = sphere.point(op.lat + (lat_off or 0), op.lon + (lon_off or 0), self.yaw, self.pitch)
	return cx + x * r, cy + y * r, z
end

-- Where mission i of n sits around its operation, as degrees from it.
function M.mission_offset(i, n, lat)
	local spread = 10
	local a = math.pi / 2 + (i - 1) * 2 * math.pi / n
	local coslat = max(0.3, math.cos(math.rad(lat)))
	return spread * math.sin(a), spread * math.cos(a) / coslat
end

-- ---------------------------------------------------------------- input

-- inp: cursor = { x, y } (frame units) or nil, click (button released), down (held), pressed (went
-- down), back, select, left, right, up, down_key, zoom_in, zoom_out. war: src/war. is_host: whether
-- this player picks missions. Answers a list of actions: { "sound", name }, { "exit" },
-- { "launch", campaign, op, mission }, { "notice", key }.
function M:input(inp, war, is_host)
	local acts = {}
	local function act(...) acts[#acts + 1] = { ... } end
	if self.ftl then return acts end
	local g = self.g
	self.cursor = inp.cursor

	-- Buttons the last frame drew (panels, rows, the breadcrumb) come first.
	local on_button
	if inp.cursor then
		for i = #self.buttons, 1, -1 do
			local b = self.buttons[i]
			if inp.cursor.x >= b.x and inp.cursor.x < b.x + b.w and inp.cursor.y >= b.y and inp.cursor.y < b.y + b.h then
				on_button = b
				break
			end
		end
	end
	local hover
	if on_button then
		hover = on_button.hover
	elseif inp.cursor and not self.drag then
		hover = self:pick(inp.cursor.x, inp.cursor.y, war)
	end
	if hover and (not self.hover or self.hover.kind ~= hover.kind or self.hover.id ~= hover.id) then
		act("sound", "ui_move")
		-- An operation picked out in the list turns the globe to it.
		if on_button and hover.kind == "op" and self.level == "planet" then
			local op = war:operation(hover.id)
			if op then self.yaw_to, self.pitch_to = sphere.facing(op.lat, op.lon) end
		end
	end
	self.hover = hover
	if hover and hover.kind == "mission" then self.mission = hover.id end

	-- Dragging turns the globe.
	if self.level == "planet" or self.level == "operation" then
		if inp.pressed and inp.cursor and not on_button then
			self.drag = { x = inp.cursor.x, y = inp.cursor.y, moved = 0 }
		end
		if self.drag and inp.down and inp.cursor then
			local dx, dy = inp.cursor.x - self.drag.x, inp.cursor.y - self.drag.y
			self.drag.moved = self.drag.moved + abs(dx) + abs(dy)
			self.drag.x, self.drag.y = inp.cursor.x, inp.cursor.y
			if self.drag.moved > 4 then
				self.yaw_to = nil
				self.yaw = (self.yaw + dx * 0.35) % 360
				self.pitch = max(-70, min(70, self.pitch - dy * 0.35))
				self.pitch_to = nil
			end
		end
		if self.drag and not inp.down then
			local moved = self.drag.moved
			self.drag = nil
			if moved > 4 then inp.click = false end
		end
	else
		self.drag = nil
	end

	if inp.back or inp.zoom_out then
		if self:back() then
			act("sound", "menu_campaign_map_move")
		elseif inp.back then
			act("sound", "ui_back")
			act("exit")
		end
		return acts
	end

	-- Keys and pads: move the focus, then select it.
	local step = (inp.right or inp.down_key) and 1 or ((inp.left or inp.up) and -1 or 0)
	if step ~= 0 then
		local items = self:items(war)
		if #items > 0 then
			local at = 0
			for i, it in ipairs(items) do
				if self.focus and it.kind == self.focus.kind and it.id == self.focus.id then at = i end
			end
			at = ((at - 1 + step) % #items) + 1
			if at < 1 then at = #items end
			self.focus = items[at]
			if self.focus.kind == "mission" then self.mission = self.focus.id end
			if self.focus.kind == "op" then
				local op = war:operation(self.focus.id)
				if op then self.yaw_to, self.pitch_to = sphere.facing(op.lat, op.lon) end
			end
			act("sound", "ui_move")
		end
	end

	local chosen
	if inp.click and hover then chosen = hover end
	if inp.click and on_button and on_button.action then chosen = on_button.action end
	if inp.select or inp.zoom_in then chosen = chosen or hover or self.focus end
	if inp.select and not chosen and self.level == "operation" then chosen = { kind = "mission", id = self.mission } end
	if chosen then self:choose(chosen, war, is_host, act) end
	return acts
end

-- What the player can point at on this level, for keys and pads.
function M:items(war)
	local g, out = self.g, {}
	if self.level == "galaxy" then
		-- Sectors with a campaign, round the galaxy.
		local seen = {}
		for _, c in ipairs(war.campaigns or {}) do
			local sid = g.planets[c.planet + 1].sector
			if not seen[sid] then
				seen[sid] = true
				local s = g.sectors[sid + 1]
				out[#out + 1] = { kind = "sector", id = sid, angle = math.atan2(s.y, s.x) }
			end
		end
		table.sort(out, function(a, b) return a.angle > b.angle end)
	elseif self.level == "sector" then
		-- Planets with a campaign first: that's where a pad or the keys most likely go.
		local rest = {}
		for _, pid in ipairs(g.sectors[self.sector + 1].planets) do
			local list = war:campaign(pid) and out or rest
			list[#list + 1] = { kind = "planet", id = pid }
		end
		for _, it in ipairs(rest) do out[#out + 1] = it end
	elseif self.level == "planet" then
		local c = war:campaign(self.planet)
		for _, op in ipairs(c and c.operations or {}) do out[#out + 1] = { kind = "op", id = op.id } end
	elseif self.level == "operation" then
		local op = war:operation(self.op)
		for i = 1, op and #op.missions or 0 do out[#out + 1] = { kind = "mission", id = i } end
	end
	return out
end

-- What is under a screen point on this level.
function M:pick(sx, sy, war)
	if self.level == "galaxy" then
		local mx, my = self:to_map(sx, sy)
		local sid = self:sector_at(mx, my)
		if sid then return { kind = "sector", id = sid } end
	elseif self.level == "sector" then
		local pid = self:globe_at(sx, sy)
		if pid then return { kind = "planet", id = pid } end
		local mx, my = self:to_map(sx, sy)
		local other = self:sector_at(mx, my)
		if other and other ~= self.sector then return { kind = "sector", id = other } end
	elseif self.level == "planet" or self.level == "operation" then
		local c = war:campaign(self.planet)
		if self.level == "operation" then
			local op = war:operation(self.op)
			if op then
				for i = 1, #op.missions do
					local la, lo = M.mission_offset(i, #op.missions, op.lat)
					local x, y, z = self:op_point(op, la, lo)
					if z > 0 and (x - sx) ^ 2 + (y - sy) ^ 2 < 30 * 30 then return { kind = "mission", id = i } end
				end
			end
		end
		local best, bd
		for _, op in ipairs(c and c.operations or {}) do
			if not (self.level == "operation" and op.id == self.op) then
				local x, y, z = self:op_point(op)
				local d = (x - sx) ^ 2 + (y - sy) ^ 2
				if z > 0.05 and d < 28 * 28 and (not bd or d < bd) then best, bd = op.id, d end
			end
		end
		if best then return { kind = "op", id = best } end
	end
end

function M:choose(it, war, is_host, act)
	if it.kind == "sector" then
		self:go("sector", it.id)
		act("sound", "menu_select_territory")
	elseif it.kind == "planet" then
		if self.level == "galaxy" then self.sector = self.g.planets[it.id + 1].sector end
		self:go("planet", it.id)
		act("sound", "menu_click_planet")
	elseif it.kind == "op" then
		local op = war:operation(it.id)
		if not op then return end
		if self.level ~= "planet" and self.level ~= "operation" then
			local _, c = war:operation(it.id)
			self:go("planet", c.planet)
		end
		self:go("operation", it.id)
		self.yaw_to, self.pitch_to = sphere.facing(op.lat, op.lon)
		self.mission = war.next_mission(op) or 1
		act("sound", "menu_campaign_select")
	elseif it.kind == "mission" then
		local op, c = war:operation(self.op)
		if not op then return end
		local m = op.missions[it.id]
		if not m then return end
		self.mission = it.id
		if m.done then
			act("sound", "menu_select_planet_locked")
			act("notice", "notice_done")
		elseif not is_host then
			act("sound", "menu_select_planet_locked")
			act("notice", "notice_host")
		else
			act("sound", "menu_campaign_select")
			act("launch", c, op, it.id)
		end
	elseif it.kind == "level" then
		while M.DEPTH[self.level] > M.DEPTH[it.id] do self:back() end
		act("sound", "menu_campaign_map_move")
	elseif it.kind == "campaign" then
		-- A row of the campaign list: straight to that planet.
		local p = self.g.planets[it.id + 1]
		self.sector = p.sector
		self:go("planet", it.id)
		act("sound", "menu_click_planet")
	end
end

-- Starts the jump to the planet: the map plays the jump, then the game takes over.
function M:start_ftl(campaign, op, mission)
	self.mission = mission
	self.ftl = { t = 0, campaign = campaign, op = op, mission = mission, done = false }
end

function M:say(key, seconds)
	self.notice = { key = key, t = seconds or 3 }
end

return M
