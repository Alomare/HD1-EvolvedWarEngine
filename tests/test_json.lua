local json = obsidian.module("src/json")

return {
	{ "reads what the war server writes", function()
		local v = assert(json.decode('{"a":[1,2.5,-3e2,null,true],"b":{"c":"x\\ny\\u00e9\\"z"},"d":null,"e":[]}'))
		eq(v.a[1], 1)
		eq(v.a[2], 2.5)
		eq(v.a[3], -300)
		eq(v.a[4], nil)
		eq(v.a.n, 5, "a list with a null keeps its length")
		eq(v.a[5], true)
		eq(v.b.c, 'x\ny\195\169"z')
		eq(v.d, nil)
		eq(v.e.n, 0)
	end },
	{ "refuses broken text", function()
		eq(json.decode("{"), nil)
		eq(json.decode('{"a":1} x'), nil)
		eq(json.decode(nil), nil)
	end },
	{ "writes a report the server reads back", function()
		local s = json.encode({ campaign = 3, operation = 12, mission = 0, success = true, lobby = "a:1", kills = 2.5 })
		eq(s, '{"campaign":3,"kills":2.5,"lobby":"a:1","mission":0,"operation":12,"success":true}')
		local back = json.decode(s)
		eq(back.operation, 12)
		eq(json.encode({ 1, 2, { x = "q\"" } }), '[1,2,{"x":"q\\""}]')
	end },
	{ "reads the fixture state", function(F)
		local s = F.state()
		eq(#s.owners >= 273 or s.owners.n == 273, true)
		truthy(s.campaigns.n > 0)
	end },
}
