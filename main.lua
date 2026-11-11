-- Evolved War Engine: the galaxy map and missions of an Evolved war from Obsidian Commander.
--
-- In a Commander war of the Evolved model, the galaxy map of the ship shows the HELLDIVERS 2 galaxy
-- instead of the three fronts: sectors, planets, supply lines, campaigns, operations and the Major
-- Order, from the war server. Picking a mission builds the planet the way the game's own map does,
-- so the ship jumps there, the hellpods open and the squad follows. At the end of the mission the host
-- reports it to the war. Anywhere else (the official war, a Vanilla war) the mod does nothing.
local galaxy = obsidian.module("src/galaxy")
local War = obsidian.module("src/war")
local View = obsidian.module("src/view")
local draw = obsidian.module("src/draw")
local net = obsidian.module("src/net")
local launch = obsidian.module("src/launch")

local api = obsidian.import("obsidian.api")
local ui = obsidian.ui

local function g(name) return rawget(_G, name) end
local function log(s) obsidian.log("evolvedwar: " .. s) end

local war = War.new(galaxy)
local view = View.new(galaxy)
view:snap()

local screen = nil        -- the galaxy map screen while it's up
local muted = false
local broken = false      -- a drawing error gave the screen back to the game
local named = {}          -- operation keys given to obsidian.game_text
local launched = nil      -- the mission the host started: { key, campaign, op, mission, record, front }
local dirtied = setmetatable({}, { __mode = "k" })

net.log = log

-- ---------------------------------------------------------------- state

local function now() return os.time() end

net.on_state = function(state)
	if war.state and state.galaxy_version and state.galaxy_version ~= galaxy.version then
		log("the war server map is version " .. tostring(state.galaxy_version) .. ", this mod draws " .. tostring(galaxy.version))
	end
	war:set(state, now())
	-- The ship and the loading screen name the planet by the operation key.
	for _, c in ipairs(war.campaigns) do
		local p = galaxy.planets[c.planet + 1]
		for _, op in ipairs(c.operations) do
			local key = War.op_key(op)
			if not named[key] then
				named[key] = true
				obsidian.game_text(key, p.name)
			end
		end
	end
	-- An operation left open on the planet level that has ended: back to the planet.
	if view.level == "operation" and not war:operation(view.op) then
		view:go("planet")
		view:say("notice_gone")
	end
end

net.on_answer = function(a)
	if type(a) == "table" and (a.planet_liberated or a.planet_defended or a.operation_complete) then net.soon() end
end

local function active()
	return net.status == "ok" and war:ready() and not broken
end

local function set_mute(on)
	if on == muted then return end
	muted = on
	if on then ui.mute("campaign") else ui.unmute("campaign") end
end

-- ---------------------------------------------------------------- texts and sounds

local function T(key, ...)
	return obsidian.text(key, ...)
end

local function G(key)
	local lm = g("LocalizationManager")
	if type(lm) ~= "table" then return nil end
	local ok, s = pcall(lm.string, lm, key)
	if ok and type(s) == "string" and s ~= "" and not s:match("^LOC:") then return s end
	return nil
end

-- Menu sounds go through the sound world of the galaxy map, as the screens there play them.
local function sound(name)
	local tw = g("TimpaniWorld")
	if screen and tw then
		local ok = pcall(function()
			local world = screen.campaign_world_proxy:get_timpani_world()
			tw.trigger_event(world, name)
		end)
		if ok then return end
	end
	if api and api.audio then pcall(api.audio.play, name) end
end

-- The keys the prompts name, as the galactic campaign screen shows them ("Q BACK E SELECT"). The game's
-- own prompt text carries key glyphs only its button overlay draws, so the words are plain here: the
-- keyboard keys, or a pad's face buttons when the main player holds a pad.
local KEYS = {
	keyboard = { select = "E", back = "Q", zoom = "WHEEL", turn = "LMB" },
	pad = { select = "A", back = "B", zoom = "LB / RB", turn = "R" },
}
local function prompt(name)
	local settings, kb = g("GameSettings"), g("KEYBOARD_MOUSE_PAD_NUMBER")
	local ok, pad = pcall(function() return settings.get_main_pad_number() end)
	local set = (not ok or pad == nil or pad == kb) and KEYS.keyboard or KEYS.pad
	return set[name]
end

-- ---------------------------------------------------------------- launching

-- The save planet a launched operation takes the place of: the first planet of that enemy front,
-- whose position, region and reward stay valid for the game's lists and network messages.
local function park(record, front)
	local sm = g("SaveManager")
	local available = sm:get("available_planets")
	local list = type(available) == "table" and available[front]
	if type(list) ~= "table" or type(list.planets) ~= "table" or not list.planets[1] then return false end
	list.planets[1] = table.clone(record)
	sm:set("available_planets", available)
	return true
end

local function slot_of(front)
	local sm = g("SaveManager")
	local available = sm:get("available_planets")
	local list = type(available) == "table" and available[front]
	local first = type(list) == "table" and type(list.planets) == "table" and list.planets[1]
	if type(first) ~= "table" then return nil end
	return { reward = first.reward, position = first.position, region = list.current_region }
end

local function samples(difficulty, n)
	local gs = g("GameSettings")
	if type(gs) ~= "table" or type(gs.get_num_research_samples_for_planet) ~= "function" then return 0 end
	local ok, v = pcall(gs.get_num_research_samples_for_planet, difficulty, n)
	return ok and tonumber(v) or 0
end

-- Hands the mission to the galaxy map screen: it saves the planet as it leaves, picks the mission
-- seed, and the ship does the jump and opens the hellpods.
local function finish_launch(s, f)
	local c, op = f.campaign, f.op
	local p = galaxy.planets[c.planet + 1]
	local slot = slot_of(c.faction)
	if not slot then
		view:say("notice_offline")
		log("no planet slot on front " .. tostring(c.faction) .. "; open the galaxy map once with the game's own war first")
		return false
	end
	local record = launch.record(op, c, p, f.mission, slot, samples)
	park(record, c.faction)
	launched = { key = record.name, campaign = c.id, op = op.id, mission = f.mission, record = record, front = c.faction }
	s.selected_trial = nil
	s.current_planet = record
	s.set_current_planet_on_exit = true
	log("launch " .. record.name .. " (" .. p.name .. ") mission " .. f.mission .. " difficulty " .. op.difficulty)
	s:exit()
	return true
end

-- The game rolls new planets when its region changes or a planet is done; the launched one goes
-- back where it was until its operation is over.
obsidian.hook("MenuScreenCampaign", "generate_planets", function(original, self, ...)
	local r = { original(self, ...) }
	if launched and war:operation(launched.op) then pcall(park, launched.record, launched.front) end
	return unpack(r)
end)

-- ---------------------------------------------------------------- the screen

local function read_input(s, raw)
	local base = g("MenuScreenBase")
	local ok, inputs = pcall(base.get_user_inputs, s, raw)
	if not ok or type(inputs) ~= "table" then inputs = {} end
	local mouse = g("Mouse")
	local inp = {}
	if mouse and screen and screen.kit then
		local ok2, pos = pcall(function() return mouse.axis(mouse.axis_index("cursor")) end)
		if ok2 and pos then
			local x, y = screen.kit:point(pos.x, pos.y)
			inp.cursor = { x = x, y = y }
		end
		local ok3, held = pcall(function() return mouse.button(mouse.button_index("left")) end)
		inp.down = ok3 and type(held) == "number" and held > 0
	end
	-- The game gives some inputs as numbers, 0 when idle (the scroll wheel among them, seen in the game
	-- on 2026-11-11), and 0 is true in Lua: a number counts only above 0.
	local function on(...)
		for i = 1, select("#", ...) do
			local val = select(i, ...)
			if val == true or (type(val) == "number" and val > 0) then return true end
		end
		return false
	end
	inp.click = on(inputs.select_mouse)
	inp.pressed = on(inputs.select_mouse_down)
	inp.back = on(inputs.back)
	inp.select = on(inputs.select)
	inp.left = on(inputs.left, inputs.d_left, inputs.left_shoulder)
	inp.right = on(inputs.right, inputs.d_right, inputs.right_shoulder)
	inp.up = on(inputs.up, inputs.d_up)
	inp.down_key = on(inputs.down, inputs.d_down)
	inp.zoom_in = on(inputs.scroll_up)
	inp.zoom_out = on(inputs.scroll_down)
	return inp
end

-- The galaxy map belongs to the ship (StateMenu); a client sees it as a sub-state that follows the host.
local function is_host(s)
	local parent = type(s) == "table" and s.parent
	return not (type(parent) == "table" and parent.is_server == false)
end

-- The first input the map takes, for the log: whether the screen gives it input at all, and how.
local told_input, told_keys = false, 0
local function tell_input(s, inp)
	if not told_input then
		told_input = true
		log("input: the map takes the screen input, pad " .. tostring(s.user_pad_number) .. (inp.cursor and string.format(", cursor %.0f %.0f", inp.cursor.x, inp.cursor.y) or ", no cursor"))
	end
	if told_keys >= 12 then return end
	local on = {}
	for _, k in ipairs({ "select", "back", "left", "right", "up", "down_key", "click", "zoom_in", "zoom_out" }) do
		if inp[k] then on[#on + 1] = k end
	end
	if #on > 0 then
		told_keys = told_keys + 1
		log("input: " .. table.concat(on, " ") .. (inp.cursor and string.format(" at %.0f %.0f", inp.cursor.x, inp.cursor.y) or ""))
	end
end

local function handle(s, raw)
	if s.exit_timer then return end
	local inp = read_input(s, raw)
	tell_input(s, inp)
	local acts = view:input(inp, war, is_host(s))
	for _, a in ipairs(acts) do
		if a[1] == "sound" then
			sound(a[2])
		elseif a[1] == "exit" then
			s:exit()
		elseif a[1] == "notice" then
			view:say(a[2])
		elseif a[1] == "launch" then
			if net.status ~= "ok" then
				view:say("notice_offline")
			else
				view:start_ftl(a[2], a[3], a[4])
			end
		end
	end
end

-- One screen for host and clients alike: MenuScreenCampaign, whose client view is a sub-state.
local hidden = setmetatable({}, { __mode = "k" })
obsidian.hook("MenuScreenCampaign", "update", function(original, self, ...)
	if active() then
		screen = self
		-- Texts the screen made before the mute would stay up: it makes them again, muted.
		if not dirtied[self] then
			dirtied[self] = true
			if type(self.hd_gui) == "table" then self.hd_gui.is_dirty = true end
			if type(self.hd_gui_dialogue) == "table" then self.hd_gui_dialogue.is_dirty = true end
		end
	end
	local r = { original(self, ...) }
	-- The globe of the three fronts goes; the starfield behind it stays.
	local unit, U = self.warfront_unit, g("Unit")
	if unit and U then
		if active() then
			if not hidden[self] then hidden[self] = pcall(U.set_unit_visibility, unit, false) end
		elseif hidden[self] then
			pcall(U.set_unit_visibility, unit, true)
			hidden[self] = nil
		end
	end
	return unpack(r)
end)
obsidian.hook("MenuScreenCampaign", "handle_input", function(original, self, raw, ...)
	if not active() then return original(self, raw, ...) end
	local ok, err = pcall(handle, self, raw)
	if not ok then
		broken = true
		set_mute(false)
		log("input failed, the game map is back: " .. tostring(err))
		return original(self, raw, ...)
	end
end)

-- What the window shows of the 1920x1080 frame, in frame units: more than the frame when the
-- player's ui_scale is under 1. nil (the plain frame) when the engine can't say.
local function window_extent(kit)
	local app = g("Application")
	local ok, w, h = pcall(function() return app.resolution() end)
	if not ok or type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
	local l, b = kit:point(0, 0)
	local r, t = kit:point(w, h)
	if type(l) ~= "number" or type(t) ~= "number" or r - l < 100 or t - b < 100 then return nil end
	return { l = l, b = b, r = r, t = t }
end

local function screen_handlers()
	return {
		enter = function(cur)
			net.soon()
			view.ftl = nil
			view.notice = nil
			view.hover = nil
		end,
		draw = function(kit, data, dt)
			if not active() then return end
			if screen then screen.kit = kit end
			local ext = window_extent(kit)
			local before = view.ext
			view:set_screen(ext)
			if view.ext ~= before then
				local e = view.ext
				log(string.format("screen l=%.0f b=%.0f r=%.0f t=%.0f", e.l, e.b, e.r, e.t))
			end
			view:update(dt or 0)
			local ok, err = pcall(draw.frame, kit, {
				v = view, war = war, now = now(), T = T, G = G, online = net.status == "ok", ext = view.ext,
				keys = view.level == "planet" and { { prompt("select"), T("key_select") }, { prompt("turn"), T("key_turn") }, { prompt("back"), T("key_back") } }
					or { { prompt("select"), T("key_select") }, { prompt("zoom"), T("key_zoom") }, { prompt("back"), T("key_back") } },
			})
			if not ok then
				broken = true
				set_mute(false)
				log("drawing failed, the game map is back: " .. tostring(err))
				return
			end
			local f = view.ftl
			if f and not f.done and f.t >= View.FTL_SECONDS and screen then
				f.done = true
				if not finish_launch(screen, f) then view.ftl = nil end
			end
		end,
		exit = function()
			screen = nil
			view.ftl = nil
		end,
	}
end

if ui then
	ui.frame(1920, 1080, { centered = true })
	ui.on("campaign", screen_handlers())
end

-- ---------------------------------------------------------------- mission end

obsidian.hook("StateMissionEnd", "on_enter", function(original, self, params, ...)
	local ok, err = pcall(function()
		local network = g("Network")
		local me = network and network.peer_id()
		-- The host who started the mission reports it; the server counts it once either way.
		if launched and type(params) == "table" and params.initial_host == me then
			local r = launch.report(params, launched)
			if r then
				net.report(r)
				if r.success then
					local op = war:operation(launched.op)
					if op and op.missions[launched.mission] then op.missions[launched.mission].done = true end
				end
				log("mission end " .. tostring(params.planet_name) .. " success " .. tostring(r.success))
			end
		end
	end)
	if not ok then log("report failed: " .. tostring(err)) end
	net.soon()
	return original(self, params, ...)
end)

-- ---------------------------------------------------------------- every frame

obsidian.on_frame(function()
	local cm = g("CampaignManager")
	if not net.http then net.http = g("Http") end
	if not net.player then
		local steam = g("Steam")
		local ok, id = pcall(function() return steam and steam.user_id() end)
		if ok and type(id) == "string" and id:match("^%x+$") then net.player = id end
	end
	local ok, err = pcall(net.update, type(cm) == "table" and cm.url or nil, now(), screen ~= nil)
	if not ok then log("net: " .. tostring(err)) end
	if ui then set_mute(active()) end
end)

log("loaded, galaxy " .. galaxy.galaxy .. " v" .. galaxy.version .. " with " .. #galaxy.planets .. " planets")
