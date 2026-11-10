-- Talking to the war. In a Commander war the game's war requests go to the Obsidian relay on this PC
-- (CampaignManager.url is http://127.0.0.1:<port>/<token>/1.0/). The relay carries
-- <token>/evolved/... to the war server too, so the mod asks the same place: GET evolved/state for the
-- war, POST evolved/report after a mission. Anything else (the official war, no Obsidian relay) and the
-- mod stays out of the way.
local json = obsidian.module("src/json")

local M = {
	base = nil,          -- http://127.0.0.1:<port>/<token>/evolved/
	status = "off",      -- off: no relay; classic: a Vanilla war; ok; error: no answer
	busy = false,
	next_poll = 0,
	outbox = {},
	on_state = nil,      -- fn(state) for each state that arrives
	log = function() end,
	http = nil,          -- the engine Http table, or a fake in the tests
	player = nil,
}

M.POLL_OPEN = 8          -- seconds between polls while the galaxy map is up
M.POLL_SHIP = 40
M.RETRY = 15

-- The evolved base for a war URL, or nil when it isn't the Obsidian relay.
function M.base_of(url)
	if type(url) ~= "string" then return nil end
	local root = url:match("^(http://127%.0%.0%.1:%d+/[0-9a-f]+/)1%.0/?$")
	return root and (root .. "evolved/") or nil
end

local function request(method, url, body, done)
	local http = M.http
	if not http then return false end
	local ok, req = pcall(http.create_request, method, url, function(_, code, answer)
		done(code, answer)
	end)
	if not ok or not req then return false end
	if body then
		req:add_header("Content-Type", "application/json")
		req:set_body(body)
	end
	if M.player then req:add_header("X-Commander-Player", M.player) end
	req:send()
	return true
end

function M.poll(now)
	if not M.base or M.busy then return end
	M.busy = true
	local base = M.base
	local sent = request("GET", base .. "state", nil, function(code, body)
		M.busy = false
		if base ~= M.base then return end
		if code == 200 then
			local state, err = json.decode(body)
			if type(state) == "table" and state.owners then
				if M.status ~= "ok" then M.log("evolved war found at " .. base) end
				M.status = "ok"
				if M.on_state then M.on_state(state) end
			else
				M.log("state not readable: " .. tostring(err))
				M.status = "error"
			end
		elseif code == 404 then
			-- A Vanilla war: nothing for this mod to do.
			if M.status ~= "classic" then M.log("the war isn't an Evolved war") end
			M.status = "classic"
		else
			if M.status == "ok" then M.log("war server unreachable (" .. tostring(code) .. ")") end
			M.status = M.status == "classic" and "classic" or "error"
		end
	end)
	if not sent then M.busy = false end
end

-- Sends a report now and keeps it until the server has it.
function M.report(r)
	M.outbox[#M.outbox + 1] = { body = json.encode(r), tries = 0, next = 0 }
end

local function flush(now)
	if not M.base then return end
	for _, item in ipairs(M.outbox) do
		if not item.inflight and now >= item.next then
			item.inflight = true
			item.tries = item.tries + 1
			request("POST", M.base .. "report", item.body, function(code, answer)
				item.inflight = false
				if code == 200 or code == 400 then
					item.sent = true
					M.log("report " .. item.body .. " -> " .. tostring(code) .. " " .. tostring(answer))
					local a = json.decode(answer or "")
					if code == 200 and M.on_answer then M.on_answer(a) end
				else
					item.next = now + M.RETRY
				end
			end)
		end
	end
	local kept = {}
	for _, item in ipairs(M.outbox) do
		if not item.sent and item.tries < 40 then kept[#kept + 1] = item end
	end
	M.outbox = kept
end

-- Once a frame (cheap): follows the game's war URL and polls on schedule. open: the map is up.
function M.update(url, now, open)
	local base = M.base_of(url)
	if base ~= M.base then
		M.base, M.status, M.busy, M.next_poll = base, base and "error" or "off", false, 0
		if base then M.log("war relay " .. base) end
	end
	if not base then return end
	if now >= M.next_poll then
		M.next_poll = now + (M.status == "classic" and 120 or (open and M.POLL_OPEN or M.POLL_SHIP))
		M.poll(now)
	end
	flush(now)
end

-- Asks for the state at the next frame (the map just opened, a mission just ended).
function M.soon()
	M.next_poll = 0
end

return M
