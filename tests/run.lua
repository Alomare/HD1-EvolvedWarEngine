-- Offline tests for everything that doesn't need the game. From the mod folder:
--   luajit tests/run.lua
local F = dofile("tests/fake.lua")
F.install()

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. "\n" .. err) end
end

function eq(got, want, what)
	if got ~= want then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

function near(got, want, what, tol)
	if math.abs(got - want) > (tol or 1e-6) then error((what or "value") .. ": expected " .. want .. ", got " .. got, 2) end
end

function truthy(v, what)
	if not v then error((what or "value") .. ": expected true", 2) end
end

for _, file in ipairs({ "tests/test_json.lua", "tests/test_sphere.lua", "tests/test_war.lua", "tests/test_view.lua",
	"tests/test_launch.lua", "tests/test_net.lua", "tests/test_draw.lua", "tests/test_main.lua" }) do
	local tests = dofile(file)
	for _, t in ipairs(tests) do test(file .. " " .. t[1], function() t[2](F) end) end
end
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
