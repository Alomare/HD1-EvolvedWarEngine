local sphere = obsidian.module("src/sphere")

return {
	{ "a point faces the viewer after turning to it", function()
		for _, p in ipairs({ { 0, 0 }, { 30, 120 }, { -45, -170 }, { 60, 10 } }) do
			local yaw, pitch = sphere.facing(p[1], p[2])
			local x, y, z = sphere.point(p[1], p[2], yaw, pitch)
			near(x, 0, "x", 1e-9)
			near(y, 0, "y", 1e-9)
			near(z, 1, "z", 1e-9)
		end
	end },
	{ "the far side is behind", function()
		local _, _, z = sphere.point(0, 180, 0, 0)
		truthy(z < 0)
	end },
	{ "turns take the short way", function()
		eq(sphere.turn(350, 10), 20)
		eq(sphere.turn(10, 350), -20)
	end },
	{ "the grid keeps the near side only", function()
		local g = sphere.grid(0, 0, 100, 30, 15, 30, 30, 10)
		truthy(#g > 0 and #g % 5 == 0)
		for i = 1, #g, 5 do truthy(g[i + 4] > 0 and g[i + 4] <= 1) end
	end },
	{ "chords across a disc", function()
		eq(sphere.chord(10, 0), 10)
		eq(sphere.chord(10, 10), 0)
		near(sphere.chord(10, 6), 8)
	end },
}
