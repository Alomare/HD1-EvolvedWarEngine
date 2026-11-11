-- Draws the war screen on an obsidian.ui kit: the galaxy of an Evolved war in the HELLDIVERS 2 layout,
-- dressed as the HELLDIVERS galactic campaign (the header and tabs, war stats, callouts, tables and
-- key prompts). One call a frame: draw.frame. Only kit calls here, so tools/preview.lua can run it
-- against a recording kit and render a picture.
--
-- The frame is 1920x1080 with y up. ctx.ext is the part of it the window shows (more than the frame
-- at a ui_scale under 1): the galaxy takes the same share of the window at any ui_scale, the panels
-- keep the game's scale and sit at the edges of the window.
--
-- ctx: v (src/view), war (src/war), now (seconds), T (the mod's text), G (the game's text or nil),
-- online (the war server answered last time), ext { l, b, r, t }, keys { { key, label }, ... }.
local sphere = obsidian.module("src/sphere")
local P = obsidian.module("src/palette")

local M = {}

local sin, cos, min, max, floor, abs, pi, sqrt, atan2 = math.sin, math.cos, math.min, math.max, math.floor, math.abs, math.pi, math.sqrt, math.atan2
local alpha, mix = P.alpha, P.mix

local Z_BACK, Z_MAP, Z_GLOBE, Z_MARK, Z_PANEL, Z_TOP = 540, 560, 580, 600, 640, 700
local W, H = 1920, 1080
local SIDE, MARGIN = 460, 50

-- Type sizes, in frame units, after the galactic campaign screen (the 720p sizes times 1.5).
local SZ = { title = 52, tab = 22, head = 24, body = 23, small = 20, value = 26, label = 23, sub = 20, faction = 40 }

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

-- Text over the map: a dark copy under it, so it reads on any territory.
local function shadow(kit, s, x, y, size, c, opts)
	local o = {}
	for k, val in pairs(opts or {}) do o[k] = val end
	text(kit, s, x + 2, y - 2, size, { 0, 0, 0, (c[4] or 255) * 0.8 }, o)
	text(kit, s, x, y, size, c, opts)
end

local function measure(kit, s, size, font, tracking)
	return kit:measure(s, { font = font or P.FONT, size = size, tracking = tracking })
end

-- Breaks s into lines no wider than w.
local function wrap(kit, s, w, size)
	local lines, cur = {}, ""
	for word in tostring(s):gmatch("%S+") do
		local try = cur == "" and word or (cur .. " " .. word)
		if measure(kit, try, size) > w and cur ~= "" then
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

-- Shortens s with ".." until it fits w.
local function fit(kit, s, size, w, font)
	if measure(kit, s, size, font) <= w then return s end
	while #s > 3 and measure(kit, s .. "..", size, font) > w do s = s:sub(1, -2) end
	return s .. ".."
end

local function button(v, x, y, w, h, action, hover)
	v.buttons[#v.buttons + 1] = { x = x, y = y, w = w, h = h, action = action, hover = hover or action }
end

local function hovered(v, kind, id)
	local h = v.hover or v.focus
	return h and h.kind == kind and h.id == id
end

local function faction_name(ctx, f)
	-- The mod's own words: the game's campaign_faction_* keys read "Cyborg Homeworld" and the like.
	local s = ctx.T(P.FACTION_TEXT[f])
	if type(s) ~= "string" or s == "" or s == P.FACTION_TEXT[f] then return P.FACTION_WORDS[f] end
	return s
end
M.faction_name = faction_name

local function difficulty_name(ctx, d)
	return ctx.G("campaign_planet_difficulty_" .. tostring(d)) or ctx.T("difficulty_n", d)
end

local function visible(ext, x0, y0, x1, y1)
	return x1 >= ext.l - 60 and x0 <= ext.r + 60 and y1 >= ext.b - 60 and y0 <= ext.t + 60
end

-- An HD1 menu box: dark, with a faint frame.
local function plate(kit, x, y, w, h, a)
	a = a or 1
	kit:rect(x, y, w, h, alpha(P.BOX, a))
	kit:outline({ x, y, x + w, y, x + w, y + h, x, y + h }, alpha(P.PANEL_LINE, a), 1)
end

-- The header row of an HD1 table ("HEROES OF THE FEDERATION"): a grey bar, white capitals, and a
-- value at the right. Answers the y under it.
local function table_head(kit, x, top, w, title, right, right_c, accent)
	local h = 44
	kit:rect(x, top - h, w, h, P.HEAD_BAR)
	if accent then kit:rect(x, top - 3, w, 3, accent) end
	text(kit, upper(title), x + 16, top - 30, SZ.head, P.WHITE, { tracking = 2 })
	if right then text(kit, right, x + w - 16, top - 30, SZ.small + 2, right_c or P.VALUE, { align = "right" }) end
	return top - h
end

local function bar(kit, x, y, w, h, value, c, back)
	kit:rect(x, y, w, h, back or P.BAR_BACK)
	if value > 0 then kit:rect(x, y, w * min(1, value), h, c) end
end

-- A key prompt as the game draws one: a light key with the letter, then the words.
local function keycap(kit, x, y, key, label)
	local kw = max(32, measure(kit, key, 18, P.FONT_LARGE) + 18)
	kit:rect(x, y, kw, 32, { 232, 232, 232, 235 })
	text(kit, key, x + kw / 2, y + 9, 18, { 12, 12, 12, 255 }, { align = "center", font = P.FONT_LARGE })
	text(kit, upper(label), x + kw + 10, y + 8, SZ.body, P.WHITE, { tracking = 1 })
	return kw + 10 + measure(kit, upper(label), SZ.body, nil, 1) + 34
end

-- Who holds a sector: the enemy with the most planets there, or Super Earth when no enemy holds one;
-- and how much of the sector that enemy holds.
local function holder(war, s)
	local sum = war:sector(s.id)
	if not sum then return s.owner, s.owner == 0 and 0 or 1 end
	local f = sum.enemy
	if f == 0 or (sum.held[f] or 0) == 0 then return 0, 0 end
	return f, sum.held[f] / max(1, sum.total)
end

-- The diagonal stripes of an enemy sector, as HELLDIVERS 2 draws enemy territory: segments in map
-- units, worked out once from the outline.
local SQ = sqrt(0.5)
local HATCH = 0.026
local hatch_cache = {}
local function hatch_of(s)
	local h = hatch_cache[s.id]
	if h then return h end
	h = {}
	local pts = s.shape
	local n = #pts / 2
	local us, ws, w0, w1 = {}, {}, 1e9, -1e9
	for i = 1, n do
		local x, y = pts[i * 2 - 1], pts[i * 2]
		us[i], ws[i] = (x + y) * SQ, (y - x) * SQ
		w0, w1 = min(w0, ws[i]), max(w1, ws[i])
	end
	local k = math.ceil(w0 / HATCH)
	while k * HATCH < w1 do
		local w = k * HATCH
		local cross = {}
		for i = 1, n do
			local j = i % n + 1
			local wa, wb = ws[i], ws[j]
			if (wa <= w and w < wb) or (wb <= w and w < wa) then
				cross[#cross + 1] = us[i] + (w - wa) * (us[j] - us[i]) / (wb - wa)
			end
		end
		table.sort(cross)
		for c = 1, #cross - 1, 2 do
			local u1, u2 = cross[c], cross[c + 1]
			h[#h + 1], h[#h + 2] = (u1 - w) * SQ, (u1 + w) * SQ
			h[#h + 1], h[#h + 2] = (u2 - w) * SQ, (u2 + w) * SQ
		end
		k = k + 1
	end
	hatch_cache[s.id] = h
	return h
end

-- ---------------------------------------------------------------- the galaxy

local function draw_galaxy(kit, ctx, L)
	local v, war, g, ext = ctx.v, ctx.war, ctx.v.g, ctx.ext
	local a = L.galaxy
	if a <= 0.01 then return end
	kit:layer(Z_MAP)
	local pulse = 0.5 + 0.5 * sin(v.t * 3)
	local hover_sector
	if v.level == "galaxy" then
		local h = v.hover or v.focus
		hover_sector = h and h.kind == "sector" and h.id
	end
	local selected = v.level ~= "galaxy" and v.sector
	-- The disc, darker than the space around it, so the territories read over the stock nebula.
	local gx, gy = v:to_screen(0, 0)
	local R = v.cam.s * (g.rim or 1)
	if R < 3000 then
		disc(kit, gx, gy, R * 1.025, alpha({ 2, 4, 9 }, 0.66 * a), 120)
	else
		-- Zoomed in, the disc is past the window: the whole window is inside it.
		kit:rect(ext.l - 50, ext.b - 50, ext.r - ext.l + 100, ext.t - ext.b + 100, alpha({ 2, 4, 9 }, 0.66 * a))
	end
	-- Sectors: Super Earth gold, an enemy in the enemy colour with stripes, stronger the more it holds.
	local holders = {}
	for _, s in ipairs(g.sectors) do
		local f, share = holder(war, s)
		holders[s.id] = f
		local fill = f == 0 and 0.13 or 0.24 + 0.16 * share
		if s.id == hover_sector then fill = fill + 0.14 end
		local dim = selected and s.id ~= selected
		if dim then fill = fill * 0.4 end
		local sum = war:sector(s.id)
		if sum and #sum.campaigns > 0 and not dim then fill = fill + 0.03 + 0.04 * pulse end
		local c = alpha(P.FACTION[f], fill * a)
		for _, piece in ipairs(s.pieces) do
			local pts, x0, y0, x1, y1 = {}, 1e9, 1e9, -1e9, -1e9
			for i = 1, #piece, 2 do
				local x, y = v:to_screen(piece[i], piece[i + 1])
				pts[i], pts[i + 1] = x, y
				x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
			end
			if visible(ext, x0, y0, x1, y1) then kit:poly(pts, c) end
		end
		if f ~= 0 then
			local hc = alpha(P.FACTION_HOT[f], (dim and 0.07 or 0.2) * a)
			local hs = hatch_of(s)
			for i = 1, #hs, 4 do
				local x1, y1 = v:to_screen(hs[i], hs[i + 1])
				local x2, y2 = v:to_screen(hs[i + 2], hs[i + 3])
				if visible(ext, min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)) then line(kit, x1, y1, x2, y2, 2, hc) end
			end
		end
	end
	-- Borders: dark gaps between sectors of one side, a light line where the sides meet, the rim in
	-- the colour of whoever holds the edge; the sector in hand outlined in white.
	local b = g.borders
	for i = 1, #b, 6 do
		local x1, y1 = v:to_screen(b[i], b[i + 1])
		local x2, y2 = v:to_screen(b[i + 2], b[i + 3])
		if visible(ext, min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)) then
			local s1, s2 = b[i + 4], b[i + 5]
			local h1, h2 = holders[s1], s2 >= 0 and holders[s2] or nil
			local width, c
			if s1 == hover_sector or s2 == hover_sector or s1 == selected or s2 == selected then
				width, c = 3, alpha(P.WHITE, 0.95)
			elseif s2 < 0 then
				width, c = 2.5, alpha(P.FACTION[h1], 0.7)
			elseif h1 ~= h2 then
				width, c = 2.5, { 255, 236, 200, 175 }
			else
				width, c = 3, { 0, 0, 0, 150 }
			end
			line(kit, x1, y1, x2, y2, width, alpha(c, a))
		end
	end
end

-- The enemy names, large, inside their territory near the rim, as HELLDIVERS 2 writes them.
local function draw_faction_names(kit, ctx, L)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local a = L.galaxy * L.labels
	if a <= 0.02 then return end
	kit:layer(Z_MAP + 6)
	local sx, sy, n = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }
	for _, p in ipairs(g.planets) do
		local o = war:owner(p.id)
		local r = sqrt(p.x * p.x + p.y * p.y)
		if o > 0 and r > 0.55 then
			sx[o], sy[o], n[o] = sx[o] + p.x / r, sy[o] + p.y / r, n[o] + 1
		end
	end
	for f = 1, 3 do
		if n[f] > 0 then
			local ang = atan2(sy[f], sx[f])
			local x, y = v:to_screen(cos(ang) * 0.87, sin(ang) * 0.87)
			shadow(kit, upper(faction_name(ctx, f)), x, y - SZ.faction * 0.35, SZ.faction, alpha(P.FACTION_HOT[f], 0.92 * a),
				{ align = "center", tracking = 4, font = P.FONT_LARGE })
		end
	end
end

-- A planet as a hologram: a lit disc in the colours of the surface, a grid that turns with it,
-- scanlines, and a rim in the colour of whoever holds it.
local function globe(kit, ctx, p, x, y, r, a, yaw, pitch, detail, simple)
	local war = ctx.war
	local owner = war:owner(p.id)
	local base = p.id == 0 and P.EARTH or (P.ENV[p.env] or P.ENV[0])
	local edge = P.FACTION[owner]
	local sides = (simple or r < 10) and 12 or (r < 40 and 24 or 56)
	-- A big globe is a hologram: a dark body in the tint of the surface, the light on one side, and the
	-- grid and the marks carry the picture. Small ones stay planets.
	local holo = r > 100
	disc(kit, x, y, r * 1.2, alpha(edge, (holo and 0.05 or 0.07) * a), sides)
	if holo then
		disc(kit, x, y, r * 1.06, alpha(edge, 0.08 * a), sides)
		disc(kit, x, y, r, alpha(mix(base, { 4, 7, 12 }, 0.84), 0.95 * a), sides)
		disc(kit, x - r * 0.14, y + r * 0.14, r * 0.8, alpha(mix(base, { 4, 7, 12 }, 0.66), 0.4 * a), sides)
		disc(kit, x - r * 0.32, y + r * 0.32, r * 0.4, alpha(mix(base, P.WHITE, 0.2), 0.06 * a), sides)
	else
		disc(kit, x, y, r, alpha(mix(base, { 6, 9, 14 }, 0.5), 0.94 * a), sides)
		disc(kit, x - r * 0.12, y + r * 0.12, r * 0.84, alpha(mix(base, { 6, 9, 14 }, 0.2), 0.55 * a), sides)
		disc(kit, x - r * 0.3, y + r * 0.3, r * 0.42, alpha(mix(base, P.WHITE, 0.25), 0.22 * a), sides)
	end
	if simple then
		ring(kit, x, y, r, 1.5, alpha(edge, 0.8 * a), sides)
		return
	end
	if r >= 9 then
		local step = detail and 20 or (r < 30 and 45 or 30)
		local seg = detail and 6 or (r < 30 and 30 or 15)
		local grid = sphere.grid(x, y, r, yaw, pitch, step, step, seg)
		local width = holo and 1.8 or 1
		local gc = holo and mix(mix(base, P.WHITE, 0.45), edge, 0.25) or mix(base, P.WHITE, 0.5)
		for i = 1, #grid, 5 do
			local depth = grid[i + 4]
			line(kit, grid[i], grid[i + 1], grid[i + 2], grid[i + 3], width, alpha(gc, ((holo and 0.12 or 0.1) + (holo and 0.55 or 0.3) * depth) * a))
		end
	end
	if r >= 18 then
		local gap = r > 120 and 5 or 4
		local off = (ctx.v.t * 14) % gap
		local dy = -r + off
		while dy < r do
			local w = sphere.chord(r, dy)
			if w > 1 then kit:rect(x - w, y + dy, w * 2, 1, alpha(P.WHITE, (holo and 0.06 or 0.05) * a)) end
			dy = dy + gap
		end
	end
	ring(kit, x, y, r, r > 100 and 3 or 2, alpha(edge, 0.95 * a), sides)
end

-- Super Earth at the middle of the galaxy level.
local function draw_super_earth(kit, ctx, L)
	local v, g = ctx.v, ctx.v.g
	local a = L.galaxy * (1 - L.globes)
	if a <= 0.02 then return end
	kit:layer(Z_MARK)
	local x, y = v:to_screen(0, 0)
	local r = 26
	local pulse = 0.5 + 0.5 * sin(v.t * 2)
	disc(kit, x, y, r + 16, alpha(P.FACTION[0], 0.12 * a), 40)
	ring(kit, x, y, r + 9 + pulse * 2, 2, alpha(P.FACTION_HOT[0], 0.75 * a), 48)
	globe(kit, ctx, g.planets[1], x, y, r, a, (v.t * 12) % 360, 18, false, false)
	shadow(kit, upper(ctx.T("super_earth")), x, y - r - 40, SZ.label, alpha(P.WHITE, a), { align = "center", tracking = 4 })
end

-- A campaign on the galaxy level: a mark on the planet and an HD1 callout with the progress.
local function marker(kit, ctx, c, x, y, a, pulse)
	local col = P.FACTION_HOT[c.faction]
	ring(kit, x, y, 15 + pulse * 6, 2, alpha(col, (0.6 - 0.45 * pulse) * a), 32)
	disc(kit, x, y, 13, alpha({ 6, 8, 12 }, 0.92 * a), 24)
	ring(kit, x, y, 13, 2.5, alpha(col, a), 24)
	if c.kind == "defense" then
		kit:glyph("shield", x - 8, y - 8, 16, alpha(P.FACTION_HOT[0], a))
	else
		chevron(kit, x, y + 1, 7, alpha(col, a))
	end
end

local function callout(kit, ctx, c, p, x, y, a)
	local v, war = ctx.v, ctx.war
	local gx, gy = v:to_screen(0, 0)
	local right, up = x >= gx, y >= gy
	local w, h = 270, 80
	local ext = ctx.ext
	local ex, ey = x + (right and 46 or -46), y + (up and 40 or -40)
	-- Under the title and tabs, above the key prompts.
	if up and ey + h > ext.t - 150 then up, ey = false, y - 40 end
	if not up and ey - h < ext.b + 80 then up, ey = true, y + 40 end
	local bx, by = right and ex or ex - w, up and ey or ey - h
	-- The leader: from the mark to the near corner of the box.
	line(kit, x + (right and 14 or -14), y + (up and 12 or -12), ex, ey, 2, alpha(P.WHITE, 0.7 * a))
	plate(kit, bx, by, w, h, 0.92 * a)
	kit:rect(right and bx or bx + w - 4, by, 4, h, alpha(P.FACTION_HOT[c.faction], a))
	local tx = bx + (right and 16 or 12)
	text(kit, fit(kit, upper(p.name), SZ.label, w - 30), tx, by + h - 30, SZ.label, alpha(P.WHITE, a), { tracking = 1 })
	local value, frac, col
	if c.kind == "defense" then
		value, frac, col = war.clock(war:left(c.ends_in, ctx.now)), (c.defense or 0) / 100, P.FACTION_HOT[0]
	else
		value, frac, col = string.format("%.1f%%", c.liberation or 0), (c.liberation or 0) / 100, P.FACTION_HOT[0]
	end
	bar(kit, tx, by + 16, w - 118, 10, frac, alpha(col, a), alpha(mix(P.FACTION[c.faction], { 0, 0, 0 }, 0.45), 0.9 * a))
	text(kit, value, bx + w - 14, by + 14, SZ.sub + 2, alpha(P.VALUE, a), { align = "right" })
end

local function draw_campaigns(kit, ctx, L)
	local v, war, g, ext = ctx.v, ctx.war, ctx.v.g, ctx.ext
	local a = L.galaxy * (1 - L.globes)
	if a <= 0.02 then return end
	kit:layer(Z_MARK)
	local pulse = 0.5 + 0.5 * sin(v.t * 4)
	-- Major Order targets: a white diamond round the planet.
	local o = war:order()
	if o and o.kind ~= "missions" then
		for _, pid in ipairs(o.planets or {}) do
			local p = g.planets[pid + 1]
			if p then
				local x, y = v:to_screen(p.x, p.y)
				local r = 22
				kit:outline({ x, y - r, x + r, y, x, y + r, x - r, y }, alpha(P.WHITE, 0.9 * a), 2)
			end
		end
	end
	-- Home worlds: a small mark in the colour of their enemy.
	for f, pid in pairs(g.homes or {}) do
		local p = g.planets[pid + 1]
		if p and f > 0 and not war:campaign(pid) then
			local x, y = v:to_screen(p.x, p.y)
			diamond(kit, x, y, 9, alpha({ 6, 8, 12 }, 0.9 * a))
			diamond(kit, x, y, 6, alpha(P.FACTION_HOT[war:owner(pid)], a))
		end
	end
	for _, c in ipairs(war.campaigns) do
		local p = g.planets[c.planet + 1]
		local x, y = v:to_screen(p.x, p.y)
		if visible(ext, x, y, x, y) then
			marker(kit, ctx, c, x, y, a, pulse)
			kit:layer(Z_MARK + 4)
			callout(kit, ctx, c, p, x, y, a)
			kit:layer(Z_MARK)
		end
	end
end

local function draw_globes(kit, ctx, L)
	local v, war, g, ext = ctx.v, ctx.war, ctx.v.g, ctx.ext
	local a = L.globes
	if a <= 0.02 then return end
	kit:layer(Z_GLOBE)
	local r = v:globe_px()
	local focus_planet = (v.level == "planet" or v.level == "operation") and v.planet
	-- Supply lines of the sector in view.
	local l = g.links
	for i = 1, #l, 2 do
		local pa, pb = g.planets[l[i] + 1], g.planets[l[i + 1] + 1]
		if (pa.sector == v.sector or pb.sector == v.sector) and not focus_planet then
			local x1, y1 = v:to_screen(pa.x, pa.y)
			local x2, y2 = v:to_screen(pb.x, pb.y)
			if visible(ext, min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)) then
				local oa, ob = war:owner(pa.id), war:owner(pb.id)
				-- Lines inside the sector show plain; those leaving it fade, so the sector stays the subject.
				local inside = pa.sector == pb.sector
				local c = oa == ob and alpha(P.WHITE, inside and 0.3 or 0.12) or alpha(P.FACTION_HOT[oa == 0 and ob or oa], inside and 0.7 or 0.3)
				line(kit, x1, y1, x2, y2, (oa == ob and 1.5 or 2.5), alpha(c, a * (1 - L.surface)))
			end
		end
	end
	for _, p in ipairs(g.planets) do
		local x, y = v:to_screen(p.x, p.y)
		if x + r > ext.l - 40 and x - r < ext.r + 40 and y + r > ext.b - 40 and y - r < ext.t + 40 then
			local own = p.sector == v.sector or p.id == focus_planet
			if focus_planet and p.id ~= focus_planet then own = false end
			if own then
				local yaw, pitch = (v.t * 9 + p.id * 37) % 360, 14
				if p.id == focus_planet then yaw, pitch = v.yaw, v.pitch end
				globe(kit, ctx, p, x, y, r, a, yaw, pitch, p.id == focus_planet and r > 80, false)
				if hovered(v, "planet", p.id) then ring(kit, x, y, r + 7, 2.5, alpha(P.WHITE, 0.95 * a)) end
			elseif not focus_planet then
				-- Planets of the other sectors: points, so the sector in hand stands out.
				disc(kit, x, y, 4, alpha(P.FACTION[war:owner(p.id)], 0.55 * a), 8)
			end
		end
	end
	-- Names under the globes, on plates.
	local na = L.names
	if na <= 0.02 then return end
	kit:layer(Z_GLOBE + 8)
	for _, p in ipairs(g.planets) do
		if p.sector == v.sector and not focus_planet then
			local x, y = v:to_screen(p.x, p.y)
			if visible(ext, x, y, x, y) then
				local owner = war:owner(p.id)
				local hot = hovered(v, "planet", p.id)
				local c = war:campaign(p.id)
				local sub, subc
				if c and c.kind == "liberation" then
					sub, subc = ctx.T("liberated_pct", string.format("%.1f", c.liberation or 0)), P.VALUE
				elseif c then
					sub, subc = ctx.T("defend_left", war.clock(war:left(c.ends_in, ctx.now))), P.FACTION_HOT[0]
				else
					sub, subc = faction_name(ctx, owner), P.FACTION_HOT[owner]
				end
				local name = upper(p.name)
				sub = upper(sub)
				local w = max(measure(kit, name, SZ.label, nil, 1), measure(kit, sub, SZ.sub)) + 24
				local top = y - r - 12
				plate(kit, x - w / 2, top - 58, w, 58, 0.85 * na)
				if c then kit:rect(x - w / 2, top - 3, w, 3, alpha(P.FACTION_HOT[c.faction], na)) end
				text(kit, name, x, top - 27, SZ.label, alpha(hot and P.HOVER or P.WHITE, na), { align = "center", tracking = 1 })
				text(kit, sub, x, top - 50, SZ.sub, alpha(subc, na), { align = "center" })
				if c then
					local cx, cy = x + r * 0.72, y + r * 0.72
					disc(kit, cx, cy, 13, alpha({ 6, 8, 12 }, 0.92 * na), 20)
					ring(kit, cx, cy, 13, 2, alpha(P.FACTION_HOT[c.faction], na), 20)
					if c.kind == "defense" then kit:glyph("shield", cx - 8, cy - 8, 16, alpha(P.FACTION_HOT[0], na))
					else chevron(kit, cx, cy + 1, 7, alpha(P.FACTION_HOT[c.faction], na)) end
				end
			end
		end
	end
end

-- Operations on the focused globe, and on the operation level the missions around it.
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
		if z > -0.15 and not (open and open.id == op.id) then
			local near = max(0, min(1, (z + 0.15) / 0.4))
			local hot = hovered(v, "op", op.id)
			local col = P.FACTION_HOT[c.faction]
			local s = (hot and 15 or 12) * (0.6 + 0.4 * near)
			ring(kit, x, y, s + 7 + pulse * 4, 2, alpha(col, 0.5 * near * a))
			diamond(kit, x, y, s, alpha({ 8, 10, 14 }, 0.9 * near * a))
			diamond(kit, x, y, s - 4, alpha(hot and P.WHITE or col, near * a))
			if near > 0.5 and not open then
				local done = 0
				for _, m in ipairs(op.missions) do if m.done then done = done + 1 end end
				local name = upper(op.name)
				local sub = upper(ctx.T("op_line", difficulty_name(ctx, op.difficulty), done, #op.missions))
				local w = max(measure(kit, name, SZ.label, nil, 1), measure(kit, sub, SZ.sub)) + 24
				plate(kit, x + 24, y - 30, w, 58, 0.85 * near * a)
				text(kit, name, x + 36, y + 2, SZ.label, alpha(hot and P.HOVER or P.WHITE, near * a), { tracking = 1 })
				text(kit, sub, x + 36, y - 21, SZ.sub, alpha(P.VALUE, near * a))
			end
		end
	end
	if not open then return end
	-- The open operation: the missions on the surface around it, linked in order.
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
		if p1[3] > 0 and p2[3] > 0 then line(kit, p1[1], p1[2], p2[1], p2[2], 2.5, alpha(P.WHITE, 0.4 * a)) end
	end
	if oz > 0 then
		local spread = 0
		for i = 1, n do spread = max(spread, sqrt((pts[i][1] - ox) ^ 2 + (pts[i][2] - oy) ^ 2)) end
		ring(kit, ox, oy, spread + 40 + pulse * 4, 2, alpha(P.FACTION_HOT[c.faction], 0.45 * a), 64)
	end
	local next_i = war.next_mission(open)
	for i = 1, n do
		local m, p = open.missions[i], pts[i]
		if p[3] > 0 then
			local hot = v.mission == i
			local col = m.done and P.DIM or (i == next_i and P.YELLOW or P.WHITE)
			local s = hot and 30 or 24
			if hot then ring(kit, p[1], p[2], s + 9 + pulse * 3, 2.5, alpha(P.YELLOW, a)) end
			disc(kit, p[1], p[2], s, alpha({ 8, 10, 14 }, 0.92 * a), 24)
			ring(kit, p[1], p[2], s, 2.5, alpha(col, a), 24)
			if m.kind == 2 then
				for k = 0, 5 do
					local ang = k * pi / 3 + v.t
					diamond(kit, p[1] + cos(ang) * s * 0.5, p[2] + sin(ang) * s * 0.5, 3.5, alpha(col, a))
				end
			end
			text(kit, tostring(i), p[1], p[2] - 8, 24, alpha(col, a), { align = "center", font = P.FONT_LARGE })
			if m.done then line(kit, p[1] - s * 0.7, p[2] - s * 0.7, p[1] + s * 0.7, p[2] + s * 0.7, 2.5, alpha(P.DIM, a)) end
		end
	end
end

-- ---------------------------------------------------------------- the header: title and tabs

local function header(kit, ctx)
	local v, g, ext = ctx.v, ctx.v.g, ctx.ext
	local cx = (ext.l + ext.r) / 2
	local ty = ext.t - 74
	local title = upper(ctx.T("galactic_war"))
	local tw = measure(kit, title, SZ.title, P.FONT_LARGE, 6)
	shadow(kit, title, cx, ty, SZ.title, P.WHITE, { align = "center", font = P.FONT_LARGE, tracking = 6 })
	-- The wings of the galactic campaign header: three bars each side, the top one longest.
	for side = -1, 1, 2 do
		for i = 0, 2 do
			local len = 190 - i * 34
			local y0 = ty + 30 - i * 13
			local x0 = cx + side * (tw / 2 + 26 + i * 10)
			local x1 = x0 + side * len
			local slant = 9
			local pts = side < 0
				and { x1 - slant, y0, x0, y0, x0, y0 + 7, x1, y0 + 7 }
				or { x0, y0, x1 + slant, y0, x1, y0 + 7, x0, y0 + 7 }
			kit:poly(pts, alpha({ 225, 228, 232 }, 0.88 - i * 0.18))
		end
	end
	-- Tabs: one per level so far, the open one on the gold bar; the others go back to it.
	local tabs = { { "galaxy", upper(ctx.T("galaxy")) } }
	if v.sector and v.level ~= "galaxy" then tabs[#tabs + 1] = { "sector", upper(ctx.T("sector_name", g.sectors[v.sector + 1].name)) } end
	if v.planet and (v.level == "planet" or v.level == "operation") then tabs[#tabs + 1] = { "planet", upper(g.planets[v.planet + 1].name) } end
	if v.op and v.level == "operation" then
		local op = ctx.war:operation(v.op)
		if op then tabs[#tabs + 1] = { "operation", upper(op.name) } end
	end
	local widths, total = {}, 0
	for i, t in ipairs(tabs) do
		widths[i] = max(220, measure(kit, t[2], SZ.tab, nil, 2) + 56)
		total = total + widths[i]
	end
	local x, y = cx - total / 2, ty - 58
	for i, t in ipairs(tabs) do
		local w = widths[i]
		local cur = t[1] == v.level
		local hot = not cur and hovered(v, "level", t[1])
		if cur then
			kit:rect(x + 3, y, w - 6, 34, alpha(P.GOLD, 0.95))
		else
			kit:rect(x + 3, y, w - 6, 34, alpha(P.BOX, 0.55))
			button(v, x + 3, y, w - 6, 34, { kind = "level", id = t[1] })
		end
		text(kit, t[2], x + w / 2, y + 10, SZ.tab, cur and P.WHITE or (hot and P.HOVER or P.TEXT), { align = "center", tracking = 2 })
		x = x + w
	end
end

-- ---------------------------------------------------------------- the left column: stats and the order

local function war_stats(kit, ctx, x, top)
	local war, g = ctx.war, ctx.v.g
	local st = war.state and war.state.stats or {}
	local held = 0
	for _, p in ipairs(g.planets) do if war:owner(p.id) == 0 then held = held + 1 end end
	text(kit, upper(ctx.T("war_stats")), x, top - 26, SZ.head + 2, P.WHITE, { tracking = 2 })
	local y = top - 64
	local rows = {
		{ ctx.T("stat_held"), ctx.T("held_of", held, #g.planets) },
		{ ctx.T("stat_liberated"), tostring(st.liberated or 0) },
		{ ctx.T("stat_missions"), tostring(st.missions_won or 0) },
		{ ctx.T("stat_kills"), tostring(st.kills or 0) },
		{ ctx.T("stat_lost"), tostring(st.deaths or 0) },
	}
	for _, r in ipairs(rows) do
		text(kit, upper(r[1]) .. ":", x + 16, y, SZ.body, P.WHITE, { tracking = 1 })
		text(kit, r[2], x + 16, y - 30, SZ.value, P.VALUE)
		y = y - 70
	end
	return y + 20
end

local function order_box(kit, ctx, x, top, w, compact)
	local war, g = ctx.war, ctx.v.g
	local o = war:order()
	if not o then
		local y = table_head(kit, x, top, w, ctx.T("major_order"))
		plate(kit, x, y - 50, w, 50)
		text(kit, ctx.T("no_order"), x + 16, y - 33, SZ.body, P.DIM)
		return y - 62
	end
	local left = war:left(o.ends_in, ctx.now)
	local y = table_head(kit, x, top, w, ctx.T("major_order"), upper(ctx.T("ends_in", war.clock(left))), P.VALUE, P.YELLOW)
	local lines = wrap(kit, o.brief or "", w - 32, SZ.body)
	if compact then lines = { lines[1] } end
	-- The objectives: a box for each planet to take, or the count of missions.
	local objectives = {}
	if o.kind == "liberate" then
		for _, pid in ipairs(o.planets or {}) do
			local p = g.planets[pid + 1]
			if p then objectives[#objectives + 1] = { ctx.T("order_liberate", p.name), war:owner(pid) == 0 } end
		end
	elseif o.kind == "defend" then
		objectives[1] = { ctx.T("order_defend"), false }
	end
	if compact then objectives = {} end
	local target = (o.target and o.target > 0) and o.target or 1
	local h = 22 + #lines * 28 + #objectives * 34 + 50
	plate(kit, x, y - h, w, h)
	local ty = y - 34
	for _, ln in ipairs(lines) do
		text(kit, ln, x + 16, ty, SZ.body, P.WHITE)
		ty = ty - 28
	end
	for _, ob in ipairs(objectives) do
		ty = ty - 6
		local bx = x + w - 38
		kit:outline({ bx, ty - 4, bx + 20, ty - 4, bx + 20, ty + 16, bx, ty + 16 }, P.WHITE, 2)
		if ob[2] then kit:rect(bx + 4, ty, 12, 12, P.YELLOW) end
		text(kit, fit(kit, ob[1], SZ.small + 2, w - 80), x + 16, ty, SZ.small + 2, ob[2] and P.VALUE or P.TEXT)
		ty = ty - 28
	end
	bar(kit, x + 16, y - h + 18, w - 120, 12, (o.progress or 0) / target, P.YELLOW)
	text(kit, ctx.T("objective_progress", floor(o.progress or 0), floor(target)), x + w - 16, y - h + 16, SZ.small + 2, P.VALUE, { align = "right" })
	return y - h - 14
end

-- ---------------------------------------------------------------- the right column, per level

local function campaign_table(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local rows = war.campaigns
	local y = table_head(kit, x, top, w, ctx.T("campaigns"), upper(ctx.T("campaign_count", #rows)), P.VALUE)
	if #rows == 0 then
		plate(kit, x, y - 50, w, 50)
		text(kit, ctx.T("no_campaigns"), x + 16, y - 33, SZ.body, P.DIM)
		return y - 62
	end
	local row_h = 76
	local shown = min(#rows, 8)
	plate(kit, x, y - shown * row_h, w, shown * row_h)
	for i = 1, shown do
		local c = rows[i]
		local p = g.planets[c.planet + 1]
		local ry = y - i * row_h
		local hot = hovered(v, "campaign", c.planet)
		if hot then kit:rect(x + 1, ry + 1, w - 2, row_h - 2, alpha(P.WHITE, 0.08)) end
		if i > 1 then kit:rect(x + 12, ry + row_h - 1, w - 24, 1, alpha(P.WHITE, 0.08)) end
		kit:rect(x + 1, ry + 8, 5, row_h - 16, P.FACTION_HOT[c.faction])
		text(kit, fit(kit, upper(p.name), SZ.body, w - 190), x + 20, ry + row_h - 32, SZ.body, hot and P.HOVER or P.WHITE, { tracking = 1 })
		local s = g.sectors[p.sector + 1]
		text(kit, upper(s.name), x + w - 16, ry + row_h - 32, SZ.small - 2, P.DIM, { align = "right" })
		local frac, value, col
		if c.kind == "defense" then
			frac, value, col = (c.defense or 0) / 100, ctx.T("defend_left", war.clock(war:left(c.ends_in, ctx.now))), P.FACTION_HOT[0]
		else
			frac, value, col = (c.liberation or 0) / 100, ctx.T("liberated_pct", string.format("%.1f", c.liberation or 0)), P.FACTION_HOT[0]
		end
		bar(kit, x + 20, ry + 16, 150, 9, frac, col, alpha(mix(P.FACTION[c.faction], { 0, 0, 0 }, 0.45), 0.9))
		text(kit, upper(value), x + 184, ry + 13, SZ.small, P.VALUE)
		button(v, x, ry, w, row_h, { kind = "campaign", id = c.planet })
	end
	return y - shown * row_h - 14
end

local function sector_table(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local s = g.sectors[v.sector + 1]
	local info = war:sector(s.id)
	local n = #s.planets
	local f = holder(war, s)
	local y = table_head(kit, x, top, w, ctx.T("sector_name", s.name), upper(ctx.T("planets_n", n)), P.VALUE, P.FACTION_HOT[f])
	local row_h = 46
	local h = 70 + n * row_h
	plate(kit, x, y - h, w, h)
	-- Who holds the sector: one band per side, in proportion.
	local bx, bw = x + 16, w - 32
	for o = 0, 3 do
		local share = info and info.total > 0 and (info.held[o] or 0) / info.total or 0
		if share > 0 then
			kit:rect(bx, y - 24, bw * share, 10, P.FACTION[o])
			bx = bx + bw * share
		end
	end
	text(kit, ctx.T("planets_held", info and info.held[0] or 0, n), x + 16, y - 54, SZ.small, P.TEXT)
	for i, pid in ipairs(s.planets) do
		local p = g.planets[pid + 1]
		local ry = y - 66 - i * row_h
		local hot = hovered(v, "planet", pid)
		if hot then kit:rect(x + 1, ry + 1, w - 2, row_h - 2, alpha(P.WHITE, 0.08)) end
		local owner = war:owner(pid)
		kit:rect(x + 16, ry + row_h / 2 - 6, 12, 12, P.FACTION[owner])
		text(kit, fit(kit, upper(p.name), SZ.body, w - 150), x + 40, ry + 15, SZ.body, hot and P.HOVER or P.WHITE)
		local c = war:campaign(pid)
		if c then
			local s2 = c.kind == "defense" and upper(ctx.T("defend_short")) or string.format("%.1f%%", c.liberation or 0)
			text(kit, s2, x + w - 16, ry + 15, SZ.small + 2, P.VALUE, { align = "right" })
		end
		button(v, x, ry, w, row_h, { kind = "planet", id = pid })
	end
	return y - h - 14
end

local function planet_card(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local p = g.planets[v.planet + 1]
	local owner = war:owner(p.id)
	local c = war:campaign(p.id)
	local ops = c and c.operations or {}
	local y = table_head(kit, x, top, w, p.name, upper(ctx.T("sector_name", g.sectors[p.sector + 1].name)), P.DIM, P.FACTION_HOT[owner])
	local note = not c and wrap(kit, ctx.T(owner == 0 and "no_ops_held" or "no_ops_far"), w - 32, SZ.small) or {}
	local h = 36 + 68 + (#p.hazards > 0 and 34 or 0) + (c and 82 or #note * 24) + (#ops > 0 and (20 + #ops * 62) or 0) + 4
	plate(kit, x, y - h, w, h)
	local ty = y - 36
	local function row(label, value, col)
		text(kit, upper(label), x + 16, ty, SZ.small, P.DIM)
		text(kit, fit(kit, value, SZ.body, w - 170), x + w - 16, ty, SZ.body, col or P.VALUE, { align = "right" })
		ty = ty - 34
	end
	row(ctx.T("control"), upper(faction_name(ctx, owner)), P.FACTION_HOT[owner])
	row(ctx.T("biome"), upper(p.biome), P.TEXT)
	if #p.hazards > 0 then row(ctx.T("hazards"), upper(table.concat(p.hazards, ", ")), P.TEXT) end
	if c and c.kind == "liberation" then
		row(ctx.T("liberation"), string.format("%.2f%%", c.liberation or 0), P.VALUE)
		bar(kit, x + 16, ty + 8, w - 32, 12, (c.liberation or 0) / 100, P.FACTION_HOT[0], alpha(mix(P.FACTION[c.faction], { 0, 0, 0 }, 0.45), 0.9))
		ty = ty - 18
		text(kit, ctx.T("math_line", string.format("%.1f", c.per_mission or 0), string.format("%.1f", c.regen_per_hour or 0)), x + 16, ty, SZ.small - 2, P.TEXT)
		ty = ty - 30
	elseif c then
		row(ctx.T("defense"), string.format("%.2f%%", c.defense or 0), P.VALUE)
		bar(kit, x + 16, ty + 8, w - 32, 12, (c.defense or 0) / 100, P.FACTION_HOT[0])
		ty = ty - 18
		text(kit, ctx.T("defend_left", war.clock(war:left(c.ends_in, ctx.now))), x + 16, ty, SZ.small, P.FACTION_HOT[c.faction])
		ty = ty - 30
	else
		for _, ln in ipairs(note) do
			text(kit, ln, x + 16, ty, SZ.small, P.TEXT)
			ty = ty - 24
		end
	end
	if #ops > 0 then
		ty = ty - 6
		kit:rect(x, ty - 6, w, 36, P.HEAD_BAR)
		text(kit, upper(ctx.T("operations")), x + 16, ty + 4, SZ.small + 2, P.WHITE, { tracking = 2 })
		ty = ty - 14
		for _, op in ipairs(ops) do
			local ry = ty - 60
			local hot = hovered(v, "op", op.id)
			if hot then kit:rect(x + 1, ry + 1, w - 2, 58, alpha(P.WHITE, 0.08)) end
			diamond(kit, x + 26, ry + 30, 8, P.FACTION_HOT[c.faction])
			text(kit, fit(kit, upper(op.name), SZ.body, w - 70), x + 46, ry + 32, SZ.body, hot and P.HOVER or P.WHITE)
			local done = 0
			for _, m in ipairs(op.missions) do if m.done then done = done + 1 end end
			text(kit, upper(ctx.T("op_line", difficulty_name(ctx, op.difficulty), done, #op.missions)), x + 46, ry + 8, SZ.small, P.VALUE)
			button(v, x, ry, w, 60, { kind = "op", id = op.id })
			ty = ty - 62
		end
	end
	return y - h - 14
end

local TOD = { [0] = "tod_dawn", [1] = "tod_day", [2] = "tod_dusk", [3] = "tod_night" }

local function operation_card(kit, ctx, x, top, w)
	local v, war, g = ctx.v, ctx.war, ctx.v.g
	local op, c = war:operation(v.op)
	if not op then return top end
	local p = g.planets[c.planet + 1]
	local n = #op.missions
	local y = table_head(kit, x, top, w, op.name, nil, nil, P.FACTION_HOT[c.faction])
	local h = 120 + n * 62 + 80
	plate(kit, x, y - h, w, h)
	text(kit, upper(ctx.T("op_where", p.name, faction_name(ctx, c.faction))), x + 16, y - 32, SZ.small, P.TEXT)
	text(kit, upper(ctx.G("campaign_planet_difficulty") or ctx.T("difficulty")), x + 16, y - 66, SZ.small, P.DIM)
	text(kit, upper(difficulty_name(ctx, op.difficulty)), x + w - 16, y - 66, SZ.body, P.VALUE, { align = "right" })
	for i = 1, 15 do
		kit:rect(x + 16 + (i - 1) * ((w - 32) / 15), y - 92, (w - 32) / 15 - 4, 10, i <= op.difficulty and P.VALUE or P.BAR_BACK)
	end
	local ty = y - 110
	local next_i = war.next_mission(op)
	for i, m in ipairs(op.missions) do
		local ry = ty - 60
		local hot = v.mission == i
		if hot then kit:rect(x + 1, ry + 1, w - 2, 58, alpha(P.WHITE, 0.09)) end
		if hot then kit:rect(x + 1, ry + 1, 5, 58, P.YELLOW) end
		local col = m.done and P.DIM or (i == next_i and P.YELLOW or P.WHITE)
		text(kit, upper(ctx.T("mission_n", i, n)), x + 20, ry + 32, SZ.body, col)
		text(kit, upper(ctx.T(m.kind == 2 and "kind_extermination" or "kind_mission")), x + 20, ry + 9, SZ.small, P.TEXT)
		text(kit, upper(ctx.T(m.done and "status_done" or TOD[m.tod or 1])), x + w - 16, ry + 32, SZ.small + 2, m.done and P.DIM or P.VALUE, { align = "right" })
		button(v, x, ry, w, 60, { kind = "mission", id = i }, { kind = "mission", id = i })
		ty = ty - 62
	end
	-- Deploy: the game's gold button.
	local m = op.missions[v.mission]
	local can = m and not m.done
	local by = y - h + 16
	kit:rect(x + 16, by, w - 32, 52, can and alpha(P.GOLD, 0.95) or alpha(P.BAR_BACK, 1))
	text(kit, upper(ctx.T(can and "deploy" or "status_done")), x + w / 2, by + 16, SZ.head, can and P.WHITE or P.DIM, { align = "center", tracking = 4, font = P.FONT_LARGE })
	if can then button(v, x + 16, by, w - 32, 52, { kind = "mission", id = v.mission }, { kind = "mission", id = v.mission }) end
	return y - h - 14
end

-- ---------------------------------------------------------------- the bottom: keys and the dispatch

local function bottom(kit, ctx)
	local v, war, ext = ctx.v, ctx.war, ctx.ext
	local y = ext.b + 34
	local x = ext.l + MARGIN
	for _, k in ipairs(ctx.keys or {}) do
		x = x + keycap(kit, x, y, k[1], k[2])
	end
	local item = war.news and war.news[1]
	if not item then return end
	local left = max(x + 30, ext.l + MARGIN + 520)
	local right = ext.r - MARGIN
	local label = upper(ctx.T("dispatch"))
	text(kit, label, left, y + 8, SZ.body, P.YELLOW, { tracking = 2 })
	local start = left + measure(kit, label, SZ.body, nil, 2) + 20
	local span = right - start
	if span < 120 then return end
	kit:clip(start, y - 4, span, 40, function(k)
		local words = item.text or ""
		local tw = measure(k, words, SZ.body)
		local off = 0
		if tw > span then off = (v.t * 60) % (tw + 120) end
		text(k, words, start - off, y + 8, SZ.body, P.TEXT)
		if off > 0 then text(k, words, start - off + tw + 120, y + 8, SZ.body, P.TEXT) end
	end)
end

-- ---------------------------------------------------------------- tooltip, notice, FTL

-- What is under the pointer on the galaxy level: the sector, as HELLDIVERS 2 names it on hover.
local function tooltip(kit, ctx)
	local v, war, g, ext = ctx.v, ctx.war, ctx.v.g, ctx.ext
	if v.level ~= "galaxy" or not v.cursor or not v.hover or v.hover.kind ~= "sector" then return end
	local s = g.sectors[v.hover.id + 1]
	local f, share = holder(war, s)
	kit:layer(Z_TOP)
	local name = upper(s.name)
	local line2 = upper(ctx.T("planets_n", #s.planets)) .. "   " .. upper(f == 0 and ctx.T("held_by", faction_name(ctx, 0)) or ctx.T("held_by", faction_name(ctx, f)))
	local w = max(measure(kit, name, SZ.value + 4, P.FONT_LARGE, 2), measure(kit, line2, SZ.small), 260) + 40
	local h = 132
	local x, y = v.cursor.x + 26, v.cursor.y - h - 18
	if x + w > ext.r - 20 then x = v.cursor.x - w - 26 end
	if y < ext.b + 20 then y = v.cursor.y + 18 end
	plate(kit, x, y, w, h, 0.95)
	kit:rect(x, y + h - 3, w, 3, P.FACTION_HOT[f])
	text(kit, upper(ctx.T("sector")), x + 20, y + h - 30, SZ.small, P.DIM, { tracking = 2 })
	text(kit, name, x + 20, y + h - 64, SZ.value + 4, P.YELLOW, { font = P.FONT_LARGE, tracking = 2 })
	text(kit, line2, x + 20, y + h - 92, SZ.small, P.TEXT)
	keycap(kit, x + 20, y + 10, (ctx.keys and ctx.keys[1] and ctx.keys[1][1]) or "E", ctx.T("select_sector"))
end

local function ftl(kit, ctx)
	local v, ext = ctx.v, ctx.ext
	local f = v.ftl
	if not f then return end
	kit:layer(Z_TOP + 10)
	local t = f.t
	local k = min(1, t / 0.9)
	local cx, cy = (ext.l + ext.r) / 2, (ext.b + ext.t) / 2
	kit:rect(ext.l - 50, ext.b - 50, ext.r - ext.l + 100, ext.t - ext.b + 100, { 0, 0, 0, 160 * k })
	for i = 0, 63 do
		local ang = i * 2.39996 -- golden angle, so the streaks don't line up
		local r0 = 40 + (i * 37 % 300) * (1 - k * 0.6)
		local len = 60 + 1100 * k * k
		local x1, y1 = cx + cos(ang) * r0, cy + sin(ang) * r0
		local x2, y2 = cx + cos(ang) * (r0 + len), cy + sin(ang) * (r0 + len)
		line(kit, x1, y1, x2, y2, 1.5 + k * 2, { 200, 230, 255, 200 * k })
	end
	local flash = max(0, (t - 0.7) / 0.35)
	if flash > 0 then kit:rect(ext.l - 50, ext.b - 50, ext.r - ext.l + 100, ext.t - ext.b + 100, { 255, 255, 255, 255 * min(1, flash) }) end
	local p = f.campaign and v.g.planets[f.campaign.planet + 1]
	if p then
		text(kit, upper(ctx.T("ftl", p.name)), cx, cy - 10, 34, { 255, 255, 255, 255 * min(1, t * 3) }, { align = "center", tracking = 4, font = P.FONT_LARGE })
	end
end

local function notice(kit, ctx)
	local n, ext = ctx.v.notice, ctx.ext
	if not n then return end
	local s = ctx.T(n.key)
	local w = measure(kit, s, SZ.body) + 60
	local a = min(1, n.t * 2)
	local cx = (ext.l + ext.r) / 2
	local y = ext.b + 110
	kit:rect(cx - w / 2, y, w, 52, alpha(P.BOX, 0.95 * a))
	kit:rect(cx - w / 2, y, 4, 52, alpha(P.YELLOW, a))
	text(kit, s, cx, y + 17, SZ.body, alpha(P.WHITE, a), { align = "center" })
end

local function scanlines(kit, ctx)
	-- The galactic campaign's own: a 512 tall strip, sliding 20 a second.
	local ext = ctx.ext
	local off = (ctx.v.t * -20) % 512
	local x0, w = ext.l - 100, ext.r - ext.l + 200
	local k = floor((ext.b - 512) / 512)
	local y = k * 512 + off
	while y < ext.t + 512 do
		kit:icon("galcamp_scanlines", x0, y - 512, w, 512, { 255, 255, 255, 46 }, { 0, 0, 0.75, 1 })
		y = y + 512
	end
end

-- ---------------------------------------------------------------- the frame

function M.frame(kit, ctx)
	local v = ctx.v
	ctx.ext = ctx.ext or v.ext or { l = 0, b = 0, r = W, t = H }
	local ext = ctx.ext
	v.buttons = {}
	local L = v:layers()
	-- Dim the stock scene behind the map; the nebula stays, as on the game's own screen.
	kit:layer(Z_BACK)
	kit:rect(ext.l - 50, ext.b - 50, ext.r - ext.l + 100, ext.t - ext.b + 100, { 2, 5, 9, 120 })
	draw_galaxy(kit, ctx, L)
	draw_faction_names(kit, ctx, L)
	draw_globes(kit, ctx, L)
	draw_super_earth(kit, ctx, L)
	draw_campaigns(kit, ctx, L)
	draw_surface(kit, ctx, L)
	kit:layer(Z_PANEL - 2)
	scanlines(kit, ctx)
	kit:layer(Z_PANEL)
	header(kit, ctx)
	local left_x, right_x = ext.l + MARGIN, ext.r - MARGIN - SIDE
	local top = ext.t - 190
	-- The war, over the left column.
	local state = ctx.war.state and ctx.war.state.war
	if state then
		text(kit, upper(state.name or ""), left_x, ext.t - 60, SZ.head, P.WHITE, { tracking = 2 })
		local line2 = state.season and upper(ctx.T("season_n", state.season)) or ""
		if not ctx.online then line2 = upper(ctx.T("offline")) end
		text(kit, line2, left_x, ext.t - 90, SZ.small, ctx.online and P.DIM or P.FACTION_HOT[2], { tracking = 1 })
	end
	if v.level == "galaxy" then
		local y = war_stats(kit, ctx, left_x, top)
		order_box(kit, ctx, left_x, y - 10, SIDE - 40, false)
		campaign_table(kit, ctx, right_x, top, SIDE)
	else
		order_box(kit, ctx, left_x, top, SIDE - 40, true)
		if v.level == "sector" then
			sector_table(kit, ctx, right_x, top, SIDE)
		elseif v.level == "planet" then
			planet_card(kit, ctx, right_x, top, SIDE)
		elseif v.level == "operation" then
			operation_card(kit, ctx, right_x, top, SIDE)
		end
	end
	bottom(kit, ctx)
	tooltip(kit, ctx)
	notice(kit, ctx)
	ftl(kit, ctx)
end

return M
