local net = obsidian.module("src/net")
local json = obsidian.module("src/json")

-- An engine Http that answers from a table and keeps what was asked.
local function fake_http(answers)
	local sent = {}
	local http = {}
	function http.create_request(method, url, cb)
		local req = { method = method, url = url, headers = {} }
		function req:add_header(k, v) self.headers[k] = v end
		function req:set_body(b) self.body = b end
		function req:send()
			sent[#sent + 1] = self
			local a = answers(self)
			cb(self, a[1], a[2])
		end
		return req
	end
	return http, sent
end

local function reset()
	net.base, net.status, net.busy, net.next_poll, net.outbox = nil, "off", false, 0, {}
	net.on_state, net.on_answer, net.player = nil, nil, nil
end

return {
	{ "only the Obsidian relay counts", function()
		eq(net.base_of("http://127.0.0.1:17495/0a1b2c/1.0/"), "http://127.0.0.1:17495/0a1b2c/evolved/")
		eq(net.base_of("http://127.0.0.1:17495/0a1b2c/1.0"), "http://127.0.0.1:17495/0a1b2c/evolved/")
		eq(net.base_of("https://api.example.com/1.0/"), nil)
		eq(net.base_of("http://10.0.0.2:17495/0a1b2c/1.0/"), nil)
		eq(net.base_of(nil), nil)
	end },
	{ "polls the state and hands it on", function(F)
		reset()
		local body = json.encode({ owners = { 0, 1 }, campaigns = {} })
		local http, sent = fake_http(function() return { 200, body } end)
		net.http = http
		local got
		net.on_state = function(s) got = s end
		net.update("http://127.0.0.1:1/ab/1.0/", 100, true)
		eq(net.status, "ok")
		eq(sent[1].url, "http://127.0.0.1:1/ab/evolved/state")
		eq(got.owners[2], 1)
		-- Not again before the interval.
		net.update("http://127.0.0.1:1/ab/1.0/", 101, true)
		eq(#sent, 1)
		net.update("http://127.0.0.1:1/ab/1.0/", 100 + net.POLL_OPEN, true)
		eq(#sent, 2)
	end },
	{ "a Vanilla war leaves the mod out", function()
		reset()
		net.http = fake_http(function() return { 404, "{}" } end)
		net.update("http://127.0.0.1:1/ab/1.0/", 0, false)
		eq(net.status, "classic")
		net.update("https://official/1.0/", 1, false)
		eq(net.status, "off")
	end },
	{ "reports are kept until the server has them", function()
		reset()
		local up = false
		local http, sent = fake_http(function(req)
			if req.method == "GET" then return { 200, '{"owners":[0]}' } end
			if up then return { 200, '{"credited":true}' } end
			return { 502, "down" }
		end)
		net.http = http
		net.player = "1100001"
		net.update("http://127.0.0.1:1/ab/1.0/", 0, false)
		net.report({ campaign = 1, operation = 2, mission = 0, success = true, lobby = "x" })
		net.update("http://127.0.0.1:1/ab/1.0/", 1, false)
		eq(#net.outbox, 1, "kept after a 502")
		local post = sent[#sent]
		eq(post.method, "POST")
		eq(post.url, "http://127.0.0.1:1/ab/evolved/report")
		eq(post.headers["X-Commander-Player"], "1100001")
		eq(json.decode(post.body).operation, 2)
		up = true
		net.update("http://127.0.0.1:1/ab/1.0/", 2, false)
		eq(#net.outbox, 1, "waits for the retry")
		net.update("http://127.0.0.1:1/ab/1.0/", 2 + net.RETRY, false)
		eq(#net.outbox, 0, "sent")
	end },
}
