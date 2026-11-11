-- main.lua against stand-ins for the loader and the game: the hooks it installs, the galaxy map
-- screen, the save and the war server.
local json = obsidian.module("src/json")

local function world(F)
	local hooks, frames, screens, mutes, texts = {}, {}, {}, {}, {}
	local saved = {}
	obsidian.hook = function(class, method, fn) hooks[class .. "." .. method] = fn end
	obsidian.on_frame = function(fn) frames[#frames + 1] = fn end
	obsidian.import = function() return { audio = { play = function() end } } end
	obsidian.game_text = function(k, v) texts[k] = v end
	obsidian.ui = {
		frame = function() end,
		on = function(id, h) screens[id] = h end,
		mute = function(id) mutes[id] = true end,
		unmute = function(id) mutes[id] = nil end,
		prompt = function(name) return name == "back" and "Q" or "E" end,
	}
	local state_body = (function()
		local f = io.open("tests/fixtures/state.json", "rb")
		local s = f:read("*a")
		f:close()
		return s
	end)()
	local posts = {}
	_G.Http = {
		create_request = function(method, url, cb)
			local req = { headers = {} }
			function req:add_header(k, v) self.headers[k] = v end
			function req:set_body(b) self.body = b end
			function req:send()
				if url:match("/state$") then cb(self, 200, state_body) else posts[#posts + 1] = self.body cb(self, 200, '{"credited":true}') end
			end
			return req
		end,
	}
	_G.CampaignManager = { url = "http://127.0.0.1:17495/0a1b/1.0/" }
	_G.Steam = { user_id = function() return "110000100000001" end }
	_G.Network = { peer_id = function() return "host1" end }
	local available = {}
	for f = 1, 3 do available[f] = { current_region = 2, planets = { { name = "planet_" .. f, reward = "xp_boost_x2", position = 3 } } } end
	_G.SaveManager = {
		get = function(_, k) if k == "available_planets" then return available end return saved[k] end,
		set = function(_, k, v) saved[k] = v end,
	}
	_G.MenuScreenBase = { get_user_inputs = function(_, raw) return raw or {} end }
	_G.Mouse = nil
	_G.Unit = { set_unit_visibility = function() end }
	-- Modules are shared between the tests; the game loads them once, fresh.
	local net = obsidian.module("src/net")
	net.http, net.base, net.status, net.busy, net.next_poll, net.outbox, net.player = nil, nil, "off", false, 0, {}, nil
	dofile("main.lua")
	return { hooks = hooks, frames = frames, screens = screens, mutes = mutes, texts = texts, posts = posts, available = available }
end

local function tick(w)
	for _, fn in ipairs(w.frames) do fn() end
end

return {
	{ "a whole round: poll, open, pick, jump, report", function(F)
		local w = world(F)
		tick(w)
		truthy(w.mutes.campaign, "the stock map is muted in an Evolved war")
		truthy(next(w.texts), "operation names given to the game")
		-- The screen opens and draws.
		local exited = false
		local screen = { parent = { is_server = true }, hd_gui = {}, warfront_unit = {} }
		function screen:exit() exited = true end
		w.hooks["MenuScreenCampaign.update"](function() end, screen, 0.016)
		eq(screen.hd_gui.is_dirty, true, "rebuilt muted")
		local h = w.screens.campaign
		h.enter({ screen = "campaign" })
		local kit = F.kit()
		h.draw(kit, {}, 0.016)
		truthy(#kit.ops > 100, "the map drew")
		local War = obsidian.module("src/war")
		-- As the game gives them: the scroll wheel as numbers, 0 when idle.
		local input = function(raw)
			raw.scroll_up, raw.scroll_down = raw.scroll_up or 0, raw.scroll_down or 0
			w.hooks["MenuScreenCampaign.handle_input"](function() error("stock input reached") end, screen, raw)
		end
		-- Keys first: the focus walks the sectors with campaigns, select zooms in, back comes out.
		input({ right = true })
		input({ select = true })
		for _ = 1, 30 do h.draw(F.kit(), {}, 1 / 15) end
		input({ back = true })
		for _ = 1, 30 do h.draw(F.kit(), {}, 1 / 15) end
		-- Then the mouse on the first row of the campaign list (the panel at the top right).
		_G.Mouse = {
			axis = function() return { x = 1500, y = 1080 - 190 - 44 - 38 } end,
			axis_index = function() return 1 end,
			button = function() return 0 end,
			button_index = function() return 1 end,
		}
		input({ select_mouse = true })
		for _ = 1, 30 do h.draw(F.kit(), {}, 1 / 15) end
		_G.Mouse = nil
		-- Now on a planet: pick its first operation and its next mission with keys.
		input({ right = true })
		input({ select = true })
		for _ = 1, 30 do h.draw(F.kit(), {}, 1 / 15) end
		input({ select = true })
		-- The jump plays, then the screen gets the planet and leaves.
		for _ = 1, 40 do h.draw(F.kit(), {}, 1 / 30) end
		truthy(exited, "the screen left")
		eq(screen.set_current_planet_on_exit, true)
		local planet = screen.current_planet
		truthy(planet and War.op_of_key(planet.name), "an operation planet")
		eq(w.available[planet.enemy].planets[1].name, planet.name, "parked where the game looks for it")
		-- The mission ends: the host reports it.
		w.hooks["StateMissionEnd.on_enter"](function() end, {}, { planet_name = planet.name, mission_completed = true, initial_host = "host1", mission_seed = 77 })
		tick(w)
		eq(#w.posts, 1, "one report")
		local r = json.decode(w.posts[1])
		eq(r.operation, War.op_of_key(planet.name))
		eq(r.success, true)
		eq(r.lobby, "host1:77")
	end },
	{ "outside a Commander war nothing changes", function(F)
		local w = world(F)
		_G.CampaignManager.url = "https://official.example/1.0/"
		tick(w)
		eq(w.mutes.campaign, nil)
		local called = false
		local screen = { parent = { is_server = true } }
		w.hooks["MenuScreenCampaign.handle_input"](function() called = true end, screen, {})
		truthy(called, "the game keeps its input")
	end },
}
