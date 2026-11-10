-- The planet globes: points on a sphere turned by yaw and pitch and drawn flat. Degrees in, screen
-- offsets out. x right, y up, z towards the viewer: a point with z > 0 is on the near side.
local M = {}

local rad, sin, cos, sqrt = math.rad, math.sin, math.cos, math.sqrt

-- A point at latitude `lat`, longitude `lon` on a sphere of radius 1, after turning the sphere by
-- `yaw` around its axis and tilting it by `pitch`. Answers x, y, z.
function M.point(lat, lon, yaw, pitch)
	local la, lo = rad(lat), rad(lon + yaw)
	local x, y, z = cos(la) * sin(lo), sin(la), cos(la) * cos(lo)
	local p = rad(pitch)
	local cp, sp = cos(p), sin(p)
	return x, y * cp - z * sp, y * sp + z * cp
end

-- The yaw and pitch that bring (lat, lon) to the middle of the disc, facing the viewer.
function M.facing(lat, lon)
	return -lon, lat
end

-- The shortest turn from angle a to angle b, in degrees.
function M.turn(a, b)
	return ((b - a + 180) % 360) - 180
end

-- Polygon points of a circle, counter-clockwise, as a flat list.
function M.circle(cx, cy, r, sides)
	local out = {}
	sides = sides or 32
	for i = 0, sides - 1 do
		local a = 2 * math.pi * i / sides
		out[#out + 1] = cx + r * cos(a)
		out[#out + 1] = cy + r * sin(a)
	end
	return out
end

-- The lines of a globe as screen segments: rings of latitude and meridians, near side only.
-- Answers a flat list { x1, y1, x2, y2, depth, ... } with depth from 0 (the edge) to 1 (the middle).
function M.grid(cx, cy, r, yaw, pitch, lat_step, lon_step, seg)
	local out = {}
	seg = seg or 10
	local function add(la1, lo1, la2, lo2)
		local x1, y1, z1 = M.point(la1, lo1, yaw, pitch)
		local x2, y2, z2 = M.point(la2, lo2, yaw, pitch)
		if z1 > 0 and z2 > 0 then
			out[#out + 1] = cx + x1 * r
			out[#out + 1] = cy + y1 * r
			out[#out + 1] = cx + x2 * r
			out[#out + 1] = cy + y2 * r
			out[#out + 1] = (z1 + z2) * 0.5
		end
	end
	for lat = -90 + lat_step, 90 - lat_step, lat_step do
		for lon = -180, 180 - seg, seg do add(lat, lon, lat, lon + seg) end
	end
	for lon = -180, 180 - lon_step, lon_step do
		for lat = -90, 90 - seg, seg do add(lat, lon, lat + seg, lon) end
	end
	return out
end

-- Half the width of a disc of radius r at height dy from its middle (for scanlines across it).
function M.chord(r, dy)
	local h = r * r - dy * dy
	return h > 0 and sqrt(h) or 0
end

return M
