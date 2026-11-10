-- Draws the map on an obsidian.ui kit, in a 1920x1080 frame with y up. One call a frame: draw.frame.
-- Only kit calls here, so tools/preview.lua can run it against a recording kit and render a picture.
--
-- ctx: v (src/view), war (src/war), now (seconds, for countdowns), T (the mod's text: key -> words),
-- G (the game's text: key -> words or nil), online (the war server answered last time).
local sphere = obsidian.module("src/sphere")
local P = obsidian.module("src/palette")

local M = {}

local sin, cos, min, max, floor, abs, pi, sqrt = math.sin, math.cos, math.min, math.max, math.floor, math.abs, math.pi, math.sqrt
local alpha, mix = P.alpha, P.mix

local Z_MAP, Z_GLOBE, Z_PANEL, Z_TOP = 560, 580, 620, 680
local W, H = 1920, 1080

-- ---------------------------------------------------------------- helpers

local function line(kit, x1, y1, x2, y2, width, c)
	local dx, dy = x2 - x1, y2 - y1
	local len = sqrt(dx * dx + dy * dy)
	if len < 0.01 then return end
	local nx, ny = -dy / len * width * 0.5, dx / len * width * 0.5
	kit:poly({ x1 + nx, y1 + ny, x1 - nx, y1 - ny, x2 - nx, y2 - ny, x2 + nx, y2 + ny }, c)
end
M.line = line

local function disc(kit, x, y, r, c, sides)
	kit:poly(sphere.circle(x, y, r, sides or (r < 6 and 8 or (r < 30 and 16 or 40))), c)
end

local function ring(kit, x, y, r, width, c, sides)
	kit:outline(sphere.circle(x, y, r, sides or (r < 30 and 20 or 48)), c, width)
end

local function diamond(kit, x, y, r, c)
	kit:poly({ x, y - r, x + r, y, x, y + r, x - r, y }, c)
end

local function chevron(kit, x, y, r, c)
	-- Points up: the mark of an attack.
	kit:poly({ x - r, y - r * 0.5, x, y + r * 0.7, x, y + r * 0.15, x - r * 0.62, y - r * 0.85 }, c)
	kit:poly({ x + r, y - r * 0.5, x + r * 0.62, y - r * 0.85, x, y + r * 0.15, x, y + r * 0.7 }, c)
end

local function upper(s)
	return string.upper(tostring(s or ""))
end

local function text(kit, s, x, y, size, c, opts)
	opts = opts or {}
	opts.size = size
	opts.color = c
	opts.font = opts.font or P.FONT
	kit:text(s, x, y, opts)
end

-- Breaks s into lines no wider than w.
local function wrap(kit, s, w, opts)
	local lines, cur = {}, ""
	for word in tostring(s):gmatch("%S+") do
		local try = cur == "" and word or (cur .. " " .. word)
		if kit:measure(try, opts) > w and cur ~= "" then
			lines[#lines + 1] = cur
			cur = word
		else
			cur = try
		end
	end
	if cur ~= "" then lines[#lines + 1] = cur end
	return lines
end
M.wrap = wrap

local function button(v, x, y, w, h, action, hover)
	v.buttons[#v.buttons + 1] = { x = x, y = y, w = w, h = h, action = action, hover = hover or action }
end

local function hovered(v, kind, id)
	local h = v.hover or v.focus
	return h and h.kind == kind and h.id == id
end

-- An HD1 menu box: dark, a thin frame, a faction or yellow bar across the top.
local function box(kit, x, y, w, h, accent, a)
	a = a or 1
	kit:rect(x, y, w, h, alpha(P.PANEL, a))
	kit:outline({ x, y, x + w, y, x + w, y + h, x, y + h }, alpha(P.PANEL_LINE, a), 1)
	if accent then kit:rect(x, y + h - 3, w, 3, alpha(accent, a)) end
end

local function header(kit, s, x, y, c)
	text(kit, upper(s), x, y, 17, c or P.YELLOW, { tracking = 2 })
end

local function faction_name(ctx, f)
	return ctx.G(P.FACTION_KEY[f]) or P.FACTION_WORDS[f]
end
M.faction_name = faction_name

local function difficulty_name(ctx, d)
	return ctx.G("campaign_planet_difficulty_" .. tostring(d)) or ctx.T("difficulty_n", d)
end

-- ---------------------------------------------------------------- the galaxy

local function visible(x0, y0, x1, y1)
	return x1 >= -60 and x0 <= W + 60 and y1 >= -60 and y0 <= H + 60
end

local function draw_galaxy(kit, ctx, L)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local a = L.galaxy
	if a <= 0.01 then return end
	kit:layer(Z_MAP)
	local pulse = 0.5 + 0.5 * sin(v.t * 3)
	local hover_sector = v.level == "galaxy" and v.hover and v.hover.kind == "sector" and v.hover.id
	if v.level == "galaxy" and not hover_sector and v.focus and v.focus.kind == "sector" then hover_sector = v.focus.id end
	local selected = v.level ~= "galaxy" and v.sector
	-- Territory.
	for _, p in ipairs(g.planets) do
		local cell = p.cell
		local pts, x0, y0, x1, y1 = {}, 1e9, 1e9, -1e9, -1e9
		for i = 1, #cell, 2 do
			local x, y = v:to_screen(cell[i], cell[i + 1])
			pts[i], pts[i + 1] = x, y
			x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
		end
		if visible(x0, y0, x1, y1) then
			local owner = war:owner(p.id)
			local share = owner == 0 and 0.13 or 0.24
			if p.sector == hover_sector then share = share + 0.12 end
			if selected and p.sector ~= selected then share = share * 0.45 end
			local c = war:campaign(p.id)
			if c then share = share + 0.08 + 0.1 * pulse end
			kit:poly(pts, alpha(P.FACTION[owner], share * a))
		end
	end
	-- Sector borders, the rim.
	local b = g.borders
	for i = 1, #b, 6 do
		local x1, y1 = v:to_screen(b[i], b[i + 1])
		local x2, y2 = v:to_screen(b[i + 2], b[i + 3])
		if visible(min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)) then
			local hot = hover_sector and (b[i + 4] == hover_sector or b[i + 5] == hover_sector)
			local sel = selected and (b[i + 4] == selected or b[i + 5] == selected)
			local c = (hot or sel) and alpha(P.WHITE, 150 / 255) or P.BORDER
			line(kit, x1, y1, x2, y2, (hot or sel) and 2 or 1.2, alpha(c, a))
		end
	end
	local rim = {}
	for i = 0, 119 do
		local x, y = v:to_screen(g.rim * cos(i * pi / 60), g.rim * sin(i * pi / 60))
		rim[#rim + 1], rim[#rim + 2] = x, y
	end
	for i = 1, #rim, 2 do
		local j = (i + 1) % #rim + 1
		line(kit, rim[i], rim[i + 1], rim[j], rim[j + 1], 2, alpha(P.RIM, a))
	end
	-- Supply lines.
	local l = g.links
	for i = 1, #l, 2 do
		local pa, pb = g.planets[l[i] + 1], g.planets[l[i + 1] + 1]
		local x1, y1 = v:to_screen(pa.x, pa.y)
		local x2, y2 = v:to_screen(pb.x, pb.y)
		if visible(min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)) then
			local oa, ob = war:owner(pa.id), war:owner(pb.id)
			local c = P.LINK
			if oa ~= ob then c = alpha(P.FACTION_HOT[oa == 0 and ob or oa], 0.45) end
			line(kit, x1, y1, x2, y2, oa ~= ob and 1.6 or 1, alpha(c, a))
		end
	end
	-- Planets as points, until they're big enough to draw as globes.
	local dots = a * (1 - L.globes)
	if dots > 0.02 then
		for _, p in ipairs(g.planets) do
			local x, y = v:to_screen(p.x, p.y)
			if visible(x, y, x, y) then
				local owner = war:owner(p.id)
				disc(kit, x, y, 3.2, alpha(P.FACTION[owner], dots), 8)
			end
		end
	end
	-- Super Earth.
	local sx, sy = v:to_screen(0, 0)
	if visible(sx, sy, sx, sy) and dots > 0.02 then
		ring(kit, sx, sy, 11 + pulse * 2, 2, alpha(P.FACTION[0], dots))
		disc(kit, sx, sy, 6, alpha(P.FACTION_HOT[0], dots))
	end
end

local function draw_labels(kit, ctx, L)
	local v, g = ctx.v, ctx.v.g
	local a = L.labels * L.galaxy
	if a <= 0.02 then return end
	kit:layer(Z_MAP + 4)
	for _, s in ipairs(g.sectors) do
		if s.id ~= 0 then
			local x, y = v:to_screen(s.x, s.y)
			local hot = hovered(v, "sector", s.id)
			text(kit, upper(s.name), x, y - 4, 13, alpha(hot and P.WHITE or P.DIM, (hot and 1 or 0.75) * a), { align = "center", tracking = 1 })
		end
	end
	local sx, sy = v:to_screen(0, 0)
	text(kit, upper(ctx.T("super_earth")), sx, sy - 30, 14, alpha(P.FACTION_HOT[0], a), { align = "center", tracking = 2 })
	-- The enemies, past the rim on their side: cyborgs left, bugs right, Illuminate below.
	-- The Illuminate side is below the disc, which reaches the bottom of the screen: their name goes
	-- past the rim at the lower left, where the disc leaves room.
	local spots = { [1] = { 1.13, 0.27 }, [2] = { -1.13, 0.27 }, [3] = { -0.86, -0.92 } }
	for f = 1, 3 do
		local x, y = v:to_screen(spots[f][1] * g.rim, spots[f][2] * g.rim)
		text(kit, upper(faction_name(ctx, f)), x, y, 22, alpha(P.FACTION_HOT[f], 0.85 * a), { align = "center", tracking = 3, font = P.FONT_LARGE })
	end
end

-- Campaign marks: an attack chevron on a planet being liberated, a shield on one being defended.
local function draw_marks(kit, ctx, L)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local a = (1 - L.surface)
	if a <= 0.02 then return end
	kit:layer(Z_GLOBE + 6)
	local pulse = 0.5 + 0.5 * sin(v.t * 4)
	for _, c in ipairs(war.campaigns) do
		local p = g.planets[c.planet + 1]
		local x, y = v:to_screen(p.x, p.y)
		if visible(x, y, x, y) then
			local r = max(v:globe_px(), 3) + 7 + pulse * 3
			local col = P.FACTION_HOT[c.faction]
			ring(kit, x, y, r, 2, alpha(col, (0.5 + 0.5 * pulse) * a))
			local mx, my = x + r * 0.75, y + r * 0.75
			if c.kind == "defense" then
				kit:glyph("shield", mx - 7, my - 7, 14, alpha(P.FACTION_HOT[0], a))
			else
				chevron(kit, mx, my, 7, alpha(col, a))
			end
		end
	end
end

-- ---------------------------------------------------------------- globes

-- A planet as a hologram: a lit disc in the colours of its surface, a grid that turns with it,
-- scanlines, and a rim in the colour of whoever holds it.
local function globe(kit, ctx, p, x, y, r, a, yaw, pitch, detail, simple)
	local war = ctx.war
	local owner = war:owner(p.id)
	local base = P.ENV[p.env] or P.ENV[0]
	local edge = P.FACTION[owner]
	local sides = (simple or r < 10) and 12 or (r < 40 and 24 or 56)
	-- Glow.
	disc(kit, x, y, r * 1.18, alpha(edge, 0.06 * a), sides)
	disc(kit, x, y, r * 1.07, alpha(edge, 0.08 * a), sides)
	-- Body, lit from the upper left.
	disc(kit, x, y, r, alpha(mix(base, { 10, 14, 20 }, 0.55), 0.85 * a), sides)
	disc(kit, x - r * 0.12, y + r * 0.12, r * 0.84, alpha(mix(base, { 10, 14, 20 }, 0.25), 0.55 * a), sides)
	disc(kit, x - r * 0.3, y + r * 0.3, r * 0.42, alpha(mix(base, P.WHITE, 0.25), 0.22 * a), sides)
	if simple then
		ring(kit, x, y, r, 1.5, alpha(edge, 0.8 * a), sides)
		return
	end
	if r >= 9 then
		local step = detail and 20 or (r < 30 and 45 or 30)
		local seg = detail and 6 or (r < 30 and 30 or 15)
		local grid = sphere.grid(x, y, r, yaw, pitch, step, step, seg)
		local width = r > 120 and 1.4 or 1
		for i = 1, #grid, 5 do
			local depth = grid[i + 4]
			line(kit, grid[i], grid[i + 1], grid[i + 2], grid[i + 3], width, alpha(mix(base, P.WHITE, 0.5), (0.1 + 0.32 * depth) * a))
		end
	end
	if r >= 18 then
		-- Scanlines across the disc, drifting down.
		local gap = r > 120 and 5 or 4
		local off = (ctx.v.t * 14) % gap
		local dy = -r + off
		while dy < r do
			local w = sphere.chord(r, dy)
			if w > 1 then kit:rect(x - w, y + dy, w * 2, 1, alpha(P.WHITE, 0.05 * a)) end
			dy = dy + gap
		end
	end
	ring(kit, x, y, r, r > 100 and 2.5 or 1.5, alpha(edge, 0.9 * a), sides)
end

local function draw_globes(kit, ctx, L)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local a = L.globes
	if a <= 0.02 then return end
	kit:layer(Z_GLOBE)
	local r = v:globe_px()
	local focus_planet = (v.level == "planet" or v.level == "operation") and v.planet
	for _, p in ipairs(g.planets) do
		local x, y = v:to_screen(p.x, p.y)
		if x + r > -40 and x - r < W + 40 and y + r > -40 and y - r < H + 40 then
			local own = p.sector == v.sector or p.id == focus_planet
			local share = a * (own and 1 or 0.55)
			if focus_planet and p.id ~= focus_planet then share = share * (1 - L.surface) end
			if share > 0.02 then
				local yaw = (v.t * 9 + p.id * 37) % 360
				local pitch = 14
				if p.id == focus_planet then yaw, pitch = v.yaw, v.pitch end
				-- Full detail for the sector in view; the neighbours stay plain, to keep the frame cheap.
				local simple = not own and not (v.level == "galaxy")
				globe(kit, ctx, p, x, y, r, share, yaw, pitch, p.id == focus_planet and r > 80, simple)
				if hovered(v, "planet", p.id) then ring(kit, x, y, r + 6, 2, alpha(P.WHITE, 0.9 * share)) end
			end
		end
	end
	-- Names under the globes.
	local na = L.names
	if na > 0.02 then
		kit:layer(Z_GLOBE + 8)
		for _, p in ipairs(g.planets) do
			if p.sector == v.sector or p.id == focus_planet then
				local x, y = v:to_screen(p.x, p.y)
				if visible(x, y, x, y) then
					local owner = war:owner(p.id)
					local hot = hovered(v, "planet", p.id)
					text(kit, upper(p.name), x, y - r - 22, 16, alpha(hot and P.HOVER or P.WHITE, na), { align = "center", tracking = 1 })
					local c = war:campaign(p.id)
					local sub
					if c and c.kind == "liberation" then
						sub = ctx.T("liberated_pct", string.format("%.1f", c.liberation or 0))
					elseif c then
						sub = ctx.T("defend_left", war.clock(war:left(c.ends_in, ctx.now)))
					else
						sub = upper(faction_name(ctx, owner))
					end
					text(kit, sub, x, y - r - 40, 13, alpha(c and P.FACTION_HOT[c.faction] or P.FACTION[owner], na), { align = "center" })
				end
			end
		end
	end
end

-- Operations on the focused globe, and on the operation level its missions around it.
local function draw_surface(kit, ctx, L)
	local v, war = ctx.v, ctx.war
	local a = L.surface
	if a <= 0.02 or not v.planet then return end
	local c = war:campaign(v.planet)
	if not c then return end
	kit:layer(Z_GLOBE + 10)
	local pulse = 0.5 + 0.5 * sin(v.t * 4)
	local open = v.level == "operation" and war:operation(v.op)
	for _, op in ipairs(c.operations) do
		local x, y, z = v:op_point(op)
		if z > -0.15 then
			local near = max(0, min(1, (z + 0.15) / 0.4))
			local hot = hovered(v, "op", op.id) or (open and open.id == op.id)
			local col = P.FACTION_HOT[c.faction]
			local s = (hot and 13 or 10) * (0.6 + 0.4 * near)
			if not (open and open.id == op.id) then
				ring(kit, x, y, s + 6 + pulse * 3, 1.5, alpha(col, 0.5 * near * a))
				diamond(kit, x, y, s, alpha({ 10, 12, 16 }, 0.85 * near * a))
				diamond(kit, x, y, s - 3, alpha(hot and P.WHITE or col, near * a))
			end
			if near > 0.5 and not open then
				local done = 0
				for _, m in ipairs(op.missions) do if m.done then done = done + 1 end end
				text(kit, upper(op.name), x + 20, y + 2, 15, alpha(hot and P.HOVER or P.WHITE, near * a), { tracking = 1 })
				text(kit, ctx.T("op_line", difficulty_name(ctx, op.difficulty), done, #op.missions), x + 20, y - 16, 13, alpha(P.DIM, near * a))
			end
		end
	end
	-- The open operation: its missions on the surface around it, linked in order.
	if open then
		local n = #open.missions
		local ox, oy, oz = v:op_point(open)
		local pts = {}
		for i = 1, n do
			local la, lo = v.mission_offset(i, n, open.lat)
			local x, y, z = v:op_point(open, la, lo)
			pts[i] = { x, y, z }
		end
		for i = 1, n - 1 do
			local p1, p2 = pts[i], pts[i + 1]
			if p1[3] > 0 and p2[3] > 0 then line(kit, p1[1], p1[2], p2[1], p2[2], 2, alpha(P.WHITE, 0.35 * a)) end
		end
		if oz > 0 then
			local spread = 0
			for i = 1, n do spread = max(spread, sqrt((pts[i][1] - ox) ^ 2 + (pts[i][2] - oy) ^ 2)) end
			ring(kit, ox, oy, spread + 34 + pulse * 4, 1.5, alpha(P.FACTION_HOT[c.faction], 0.35 * a), 64)
			text(kit, upper(open.name), ox, oy + spread + 58, 20, alpha(P.WHITE, a), { align = "center", tracking = 2, font = P.FONT_LARGE })
		end
		local next_i = war.next_mission(open)
		for i = 1, n do
			local m, p = open.missions[i], pts[i]
			if p[3] > 0 then
				local hot = v.mission == i
				local col = m.done and P.DIM or (i == next_i and P.YELLOW or P.WHITE)
				local s = hot and 27 or 21
				if hot then ring(kit, p[1], p[2], s + 8 + pulse * 3, 2, alpha(P.YELLOW, a)) end
				disc(kit, p[1], p[2], s, alpha({ 8, 10, 14 }, 0.9 * a), 24)
				ring(kit, p[1], p[2], s, 2, alpha(col, a), 24)
				if m.kind == 2 then
					-- Extermination: a skull would be the game's; a burst of points stands in.
					for k = 0, 5 do
						local ang = k * pi / 3 + v.t
						diamond(kit, p[1] + cos(ang) * s * 0.45, p[2] + sin(ang) * s * 0.45, 3, alpha(col, a))
					end
				end
				text(kit, tostring(i), p[1], p[2] - 6, 18, alpha(col, a), { align = "center", font = P.FONT_LARGE })
				if m.done then line(kit, p[1] - s * 0.7, p[2] - s * 0.7, p[1] + s * 0.7, p[2] + s * 0.7, 2, alpha(P.DIM, a)) end
			end
		end
	end
end

-- ---------------------------------------------------------------- panels

local function bar(kit, x, y, w, h, value, c, a)
	kit:rect(x, y, w, h, alpha(P.BAR_BACK, a))
	if value > 0 then kit:rect(x, y, w * min(1, value), h, alpha(c, a)) end
end

local function order_panel(kit, ctx, x, top, w, compact)
	local war = ctx.war
	local o = war:order()
	if not o then return top end
	local lines = wrap(kit, o.brief or "", w - 32, { font = P.FONT, size = 16 })
	local h = compact and 86 or (92 + #lines * 20)
	local y = top - h
	box(kit, x, y, w, h, P.YELLOW)
	header(kit, ctx.T("major_order"), x + 16, top - 28)
	local left = war:left(o.ends_in, ctx.now)
	text(kit, war.clock(left), x + w - 16, top - 28, 15, P.VALUE, { align = "right" })
	local ty = top - 54
	if not compact then
		for _, ln in ipairs(lines) do
			text(kit, ln, x + 16, ty, 16, P.TEXT)
			ty = ty - 20
		end
	else
		text(kit, lines[1] or "", x + 16, ty, 15, P.TEXT)
		ty = ty - 20
	end
	local target = (o.target and o.target > 0) and o.target or 1
	local value = (o.progress or 0) / target
	bar(kit, x + 16, y + 16, w - 110, 8, value, P.YELLOW, 1)
	text(kit, string.format("%d / %d", floor(o.progress or 0), floor(target)), x + w - 16, y + 12, 14, P.VALUE, { align = "right" })
	return y - 12
end

local function campaign_rows(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local rows = war.campaigns
	if #rows == 0 then return top end
	local row_h = 54
	local shown = min(#rows, 8)
	local h = 44 + shown * row_h
	local y = top - h
	box(kit, x, y, w, h, P.WHITE)
	header(kit, ctx.T("campaigns"), x + 16, top - 28, P.WHITE)
	for i = 1, shown do
		local c = rows[i]
		local p = g.planets[c.planet + 1]
		local ry = top - 44 - i * row_h
		local hot = hovered(v, "campaign", c.planet)
		if hot then kit:rect(x + 2, ry + 2, w - 4, row_h - 4, alpha(P.WHITE, 0.08)) end
		kit:rect(x + 8, ry + 8, 4, row_h - 16, P.FACTION_HOT[c.faction])
		text(kit, upper(p.name), x + 22, ry + row_h - 22, 16, hot and P.HOVER or P.WHITE, { tracking = 1 })
		local s = g.sectors[p.sector + 1]
		text(kit, upper(s.name), x + w - 14, ry + row_h - 22, 12, P.DIM, { align = "right" })
		if c.kind == "defense" then
			local left = war:left(c.ends_in, ctx.now)
			text(kit, ctx.T("defend_left", war.clock(left)), x + 22, ry + 13, 13, P.FACTION_HOT[0])
			bar(kit, x + 190, ry + 15, w - 204, 6, (c.defense or 0) / 100, P.FACTION_HOT[0], 1)
		else
			text(kit, ctx.T("liberated_pct", string.format("%.1f", c.liberation or 0)), x + 22, ry + 13, 13, P.FACTION_HOT[c.faction])
			bar(kit, x + 190, ry + 15, w - 204, 6, (c.liberation or 0) / 100, P.FACTION_HOT[0], 1)
		end
		button(v, x, ry, w, row_h, { kind = "campaign", id = c.planet })
	end
	return y - 12
end

local function sector_panel(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local s = g.sectors[v.sector + 1]
	local info = war:sector(s.id)
	local n = #s.planets
	local row_h = 34
	local h = 108 + n * row_h
	local y = top - h
	box(kit, x, y, w, h, P.FACTION[info and info.owner or 0])
	header(kit, ctx.T("sector_name", upper(s.name)), x + 16, top - 28, P.WHITE)
	-- Control: one band per faction, in proportion.
	local bx, by, bw = x + 16, top - 60, w - 32
	for f = 0, 3 do
		local share = info and info.total > 0 and (info.held[f] or 0) / info.total or 0
		if share > 0 then
			kit:rect(bx, by, bw * share, 8, P.FACTION[f])
			bx = bx + bw * share
		end
	end
	text(kit, ctx.T("planets_held", info and info.held[0] or 0, n), x + 16, top - 84, 13, P.DIM)
	for i, pid in ipairs(s.planets) do
		local p = g.planets[pid + 1]
		local ry = top - 96 - i * row_h
		local hot = hovered(v, "planet", pid)
		if hot then kit:rect(x + 2, ry + 1, w - 4, row_h - 2, alpha(P.WHITE, 0.08)) end
		local owner = war:owner(pid)
		disc(kit, x + 22, ry + row_h / 2, 5, P.FACTION[owner], 10)
		text(kit, upper(p.name), x + 36, ry + 11, 15, hot and P.HOVER or P.WHITE)
		local c = war:campaign(pid)
		if c then
			local s2 = c.kind == "defense" and ctx.T("defend_short") or string.format("%.0f%%", c.liberation or 0)
			text(kit, s2, x + w - 14, ry + 11, 13, P.FACTION_HOT[c.faction], { align = "right" })
		end
		button(v, x, ry, w, row_h, { kind = "planet", id = pid })
	end
	return y - 12
end

local function planet_panel(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local p = g.planets[v.planet + 1]
	local owner = war:owner(p.id)
	local c = war:campaign(p.id)
	local ops = c and c.operations or {}
	local h = 214 + (#ops > 0 and (34 + #ops * 46) or 40)
	local y = top - h
	box(kit, x, y, w, h, P.FACTION[owner])
	text(kit, upper(p.name), x + 16, top - 34, 24, P.WHITE, { font = P.FONT_LARGE, tracking = 2 })
	text(kit, upper(ctx.T("sector_name", g.sectors[p.sector + 1].name)), x + 16, top - 58, 13, P.DIM)
	local ty = top - 88
	local function row(label, value, col)
		text(kit, upper(label), x + 16, ty, 13, P.DIM)
		text(kit, value, x + w - 16, ty, 14, col or P.VALUE, { align = "right" })
		ty = ty - 22
	end
	row(ctx.T("control"), upper(faction_name(ctx, owner)), P.FACTION_HOT[owner])
	row(ctx.T("biome"), upper(p.biome), P.TEXT)
	if #p.hazards > 0 then row(ctx.T("hazards"), upper(table.concat(p.hazards, ", ")), P.TEXT) end
	if c and c.kind == "liberation" then
		row(ctx.T("liberation"), string.format("%.2f%%", c.liberation or 0), P.FACTION_HOT[0])
		bar(kit, x + 16, ty + 4, w - 32, 8, (c.liberation or 0) / 100, P.FACTION_HOT[0], 1)
		ty = ty - 20
		text(kit, ctx.T("math_line", string.format("%.1f", c.per_mission or 0), string.format("%.1f", c.regen_per_hour or 0)), x + 16, ty, 12, P.DIM)
		ty = ty - 22
	elseif c then
		row(ctx.T("defense"), string.format("%.2f%%", c.defense or 0), P.FACTION_HOT[0])
		bar(kit, x + 16, ty + 4, w - 32, 8, (c.defense or 0) / 100, P.FACTION_HOT[0], 1)
		ty = ty - 20
		text(kit, ctx.T("defend_left", war.clock(war:left(c.ends_in, ctx.now))), x + 16, ty, 13, P.FACTION_HOT[c.faction])
		ty = ty - 22
	else
		ty = ty - 6
		text(kit, ctx.T(owner == 0 and "no_ops_held" or "no_ops_far"), x + 16, ty, 13, P.DIM)
		ty = ty - 22
	end
	if #ops > 0 then
		header(kit, ctx.T("operations"), x + 16, ty - 4, P.WHITE)
		ty = ty - 22
		for _, op in ipairs(ops) do
			local ry = ty - 42
			local hot = hovered(v, "op", op.id)
			if hot then kit:rect(x + 2, ry + 1, w - 4, 44, alpha(P.WHITE, 0.08)) end
			diamond(kit, x + 24, ry + 22, 7, P.FACTION_HOT[c.faction])
			text(kit, upper(op.name), x + 40, ry + 25, 15, hot and P.HOVER or P.WHITE)
			local done = 0
			for _, m in ipairs(op.missions) do if m.done then done = done + 1 end end
			text(kit, ctx.T("op_line", difficulty_name(ctx, op.difficulty), done, #op.missions), x + 40, ry + 7, 13, P.DIM)
			button(v, x, ry, w, 44, { kind = "op", id = op.id })
			ty = ty - 46
		end
	end
	return y - 12
end

local TOD = { [0] = "tod_dawn", [1] = "tod_day", [2] = "tod_dusk", [3] = "tod_night" }

local function operation_panel(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local op, c = war:operation(v.op)
	if not op then return top end
	local p = g.planets[c.planet + 1]
	local n = #op.missions
	local h = 168 + n * 50 + 70
	local y = top - h
	box(kit, x, y, w, h, P.FACTION_HOT[c.faction])
	text(kit, upper(op.name), x + 16, top - 34, 22, P.WHITE, { font = P.FONT_LARGE, tracking = 1 })
	text(kit, upper(ctx.T("op_where", p.name, faction_name(ctx, c.faction))), x + 16, top - 58, 13, P.DIM)
	text(kit, upper(ctx.G("campaign_planet_difficulty") or ctx.T("difficulty")), x + 16, top - 88, 13, P.DIM)
	text(kit, upper(difficulty_name(ctx, op.difficulty)), x + w - 16, top - 88, 15, P.VALUE, { align = "right" })
	-- Difficulty pips, 1 to 15.
	for i = 1, 15 do
		kit:rect(x + 16 + (i - 1) * ((w - 32) / 15), top - 106, (w - 32) / 15 - 3, 6, i <= op.difficulty and P.VALUE or P.BAR_BACK)
	end
	local ty = top - 130
	local next_i = war.next_mission(op)
	for i, m in ipairs(op.missions) do
		local ry = ty - 46
		local hot = v.mission == i
		if hot then kit:rect(x + 2, ry + 1, w - 4, 46, alpha(P.WHITE, 0.08)) end
		local col = m.done and P.DIM or (i == next_i and P.YELLOW or P.WHITE)
		text(kit, ctx.T("mission_n", i, n), x + 16, ry + 26, 15, col)
		text(kit, upper(ctx.T(m.kind == 2 and "kind_extermination" or "kind_mission")), x + 16, ry + 8, 13, P.DIM)
		text(kit, upper(ctx.T(m.done and "status_done" or TOD[m.tod or 1])), x + w - 16, ry + 26, 13, m.done and P.DIM or P.VALUE, { align = "right" })
		button(v, x, ry, w, 46, { kind = "mission", id = i }, { kind = "mission", id = i })
		ty = ty - 50
	end
	-- Deploy.
	local m = op.missions[v.mission]
	local can = m and not m.done
	local by = y + 16
	kit:rect(x + 16, by, w - 32, 44, can and alpha(P.YELLOW, 0.92) or alpha(P.BAR_BACK, 1))
	text(kit, upper(ctx.T(can and "deploy" or "status_done")), x + w / 2, by + 15, 18, can and { 10, 10, 10 } or P.DIM, { align = "center", tracking = 3, font = P.FONT_LARGE })
	if can then button(v, x + 16, by, w - 32, 44, { kind = "mission", id = v.mission }, { kind = "mission", id = v.mission }) end
	return y - 12
end

local function breadcrumb(kit, ctx)
	local v, g = ctx.v, ctx.v.g
	local parts = { { "galaxy", upper(ctx.T("galactic_war")) } }
	if v.sector and v.level ~= "galaxy" then parts[#parts + 1] = { "sector", upper(ctx.T("sector_name", g.sectors[v.sector + 1].name)) } end
	if v.planet and (v.level == "planet" or v.level == "operation") then parts[#parts + 1] = { "planet", upper(g.planets[v.planet + 1].name) } end
	if v.op and v.level == "operation" then
		local op = ctx.war:operation(v.op)
		if op then parts[#parts + 1] = { "operation", upper(op.name) } end
	end
	local x, y = 60, H - 58
	for i, part in ipairs(parts) do
		local last = i == #parts
		local wd = kit:measure(part[2], { font = P.FONT, size = 16, tracking = 2 })
		local hot = not last and hovered(v, "level", part[1])
		text(kit, part[2], x, y, 16, last and P.WHITE or (hot and P.HOVER or P.DIM), { tracking = 2 })
		if not last then
			button(v, x - 4, y - 8, wd + 8, 28, { kind = "level", id = part[1] })
			text(kit, "/", x + wd + 12, y, 16, P.DIM)
		end
		x = x + wd + 34
	end
	-- The war and its link.
	local state = ctx.war.state and ctx.war.state.war
	local name = state and state.name or ""
	text(kit, upper(name), W - 60, y, 16, P.WHITE, { align = "right", tracking = 2 })
	if not ctx.online then
		text(kit, upper(ctx.T("offline")), W - 60, y - 22, 13, P.FACTION_HOT[2], { align = "right" })
	end
	kit:rect(60, y - 14, W - 120, 1, alpha(P.WHITE, 0.15))
end

local function news(kit, ctx)
	local war, v = ctx.war, ctx.v
	local y = 26
	kit:rect(0, 0, W, 54, alpha(P.PANEL, 0.9))
	kit:rect(0, 54, W, 1, alpha(P.WHITE, 0.15))
	local item = war.news and war.news[1]
	if item then
		local label = upper(ctx.T("dispatch"))
		text(kit, label, 60, y - 6, 14, P.YELLOW, { tracking = 2 })
		local start = 60 + kit:measure(label, { font = P.FONT, size = 14, tracking = 2 }) + 24
		kit:clip(start, 0, 1240 - start, 54, function(k)
			local words = item.text or ""
			local tw = k:measure(words, { font = P.FONT, size = 16 })
			local span = max(1240 - start, tw)
			local off = 0
			if tw > 1240 - start then off = (v.t * 60) % (tw + 120) end
			text(k, words, start - off, y - 7, 16, P.TEXT)
			if off > 0 then text(k, words, start - off + tw + 120, y - 7, 16, P.TEXT) end
		end)
	end
	-- Keys.
	local keys = ctx.keys or {}
	local x = W - 60
	for i = #keys, 1, -1 do
		local k = keys[i]
		local s = "[" .. k[1] .. "] " .. upper(k[2])
		text(kit, s, x, y - 6, 14, P.DIM, { align = "right" })
		x = x - kit:measure(s, { font = P.FONT, size = 14 }) - 26
	end
end

local function scanlines(kit, ctx)
	-- The galactic campaign's own: a 512 tall strip, 40% white, sliding 20 a second.
	local off = (ctx.v.t * -20) % 512
	for k = -1, 2 do
		kit:icon("galcamp_scanlines", -200, off + (k - 1) * 512, W + 400, 512, { 255, 255, 255, 60 }, { 0, 0, 0.75, 1 })
	end
end

local function ftl(kit, ctx)
	local v = ctx.v
	local f = v.ftl
	if not f then return end
	kit:layer(Z_TOP + 10)
	local t = f.t
	local k = min(1, t / 0.9)
	local cx, cy = W / 2, H / 2
	kit:rect(-200, -200, W + 400, H + 400, { 0, 0, 0, 160 * k })
	for i = 0, 63 do
		local ang = i * 2.39996 -- golden angle, so the streaks don't line up
		local r0 = 40 + (i * 37 % 300) * (1 - k * 0.6)
		local len = 60 + 900 * k * k
		local x1, y1 = cx + cos(ang) * r0, cy + sin(ang) * r0
		local x2, y2 = cx + cos(ang) * (r0 + len), cy + sin(ang) * (r0 + len)
		line(kit, x1, y1, x2, y2, 1.5 + k * 2, { 200, 230, 255, 200 * k })
	end
	local flash = max(0, (t - 0.7) / 0.35)
	if flash > 0 then kit:rect(-200, -200, W + 400, H + 400, { 255, 255, 255, 255 * min(1, flash) }) end
	local p = f.campaign and v.g.planets[f.campaign.planet + 1]
	if p then
		text(kit, upper(ctx.T("ftl", p.name)), cx, cy - 8, 26, { 255, 255, 255, 255 * min(1, t * 3) }, { align = "center", tracking = 4, font = P.FONT_LARGE })
	end
end

local function notice(kit, ctx)
	local n = ctx.v.notice
	if not n then return end
	local s = ctx.T(n.key)
	local w = kit:measure(s, { font = P.FONT, size = 17 }) + 48
	local a = min(1, n.t * 2)
	kit:rect(W / 2 - w / 2, 92, w, 40, alpha(P.PANEL, a))
	kit:rect(W / 2 - w / 2, 92, 3, 40, alpha(P.YELLOW, a))
	text(kit, s, W / 2, 106, 17, alpha(P.WHITE, a), { align = "center" })
end

-- ---------------------------------------------------------------- the frame

function M.frame(kit, ctx)
	local v = ctx.v
	v.buttons = {}
	local L = v:layers()
	-- Darken the stock scene behind the map; past the frame for wide screens.
	kit:layer(Z_MAP - 10)
	kit:rect(-400, -200, W + 800, H + 400, { 2, 5, 9, 150 })
	draw_galaxy(kit, ctx, L)
	draw_labels(kit, ctx, L)
	draw_globes(kit, ctx, L)
	draw_marks(kit, ctx, L)
	draw_surface(kit, ctx, L)
	kit:layer(Z_PANEL - 2)
	scanlines(kit, ctx)
	kit:layer(Z_PANEL)
	local left_x, right_x, pw = 60, W - 60 - 440, 440
	local top = H - 96
	if v.level == "galaxy" then
		order_panel(kit, ctx, left_x, top, 400, false)
		campaign_rows(kit, ctx, right_x, top, pw)
	elseif v.level == "sector" then
		order_panel(kit, ctx, left_x, top, 400, true)
		sector_panel(kit, ctx, right_x, top, pw)
	elseif v.level == "planet" then
		order_panel(kit, ctx, left_x, top, 400, true)
		planet_panel(kit, ctx, right_x, top, pw)
	elseif v.level == "operation" then
		order_panel(kit, ctx, left_x, top, 400, true)
		operation_panel(kit, ctx, right_x, top, pw)
	end
	breadcrumb(kit, ctx)
	news(kit, ctx)
	notice(kit, ctx)
	ftl(kit, ctx)
end

return M
