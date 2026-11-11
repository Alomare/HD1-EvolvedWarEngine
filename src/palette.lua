-- The look: HELLDIVERS colours and type. The faction colours are the galactic campaign's own
-- (CampaignSettings colours: Super Earth yellow, bugs green, cyborgs red, Illuminate blue), as the
-- Commander war screens draw them; the panel colours follow the game's menus (white text, orange
-- values, dark boxes).
local M = {}

-- By faction: 0 Super Earth, 1 bugs, 2 cyborgs, 3 illuminates.
M.FACTION = {
	[0] = { 255, 170, 20 },
	[1] = { 70, 220, 160 },
	[2] = { 230, 80, 70 },
	[3] = { 40, 150, 250 },
}
-- Brighter, for what is under attack or selected.
M.FACTION_HOT = {
	[0] = { 255, 205, 60 },
	[1] = { 120, 255, 200 },
	[2] = { 255, 120, 100 },
	[3] = { 110, 190, 255 },
}
-- The mod's text keys for the names of the sides, and what to show when a key is missing.
M.FACTION_TEXT = { [0] = "faction_superearth", [1] = "faction_bugs", [2] = "faction_cyborgs", [3] = "faction_illuminates" }
M.FACTION_WORDS = { [0] = "Super Earth", [1] = "Bugs", [2] = "Cyborgs", [3] = "Illuminates" }

-- Planet surfaces by HELLDIVERS environment: desert, forest, snow, lava, city.
M.ENV = {
	[0] = { 222, 178, 110 },
	[1] = { 92, 170, 96 },
	[2] = { 214, 232, 246 },
	[3] = { 236, 98, 44 },
	[4] = { 190, 196, 210 },
}
M.EARTH = { 70, 140, 210 }          -- Super Earth: oceans, not the city biome
M.ENV_KEY ={ [0] = "desert", [1] = "forest", [2] = "snow", [3] = "lava", [4] = "city" }

M.WHITE = { 255, 255, 255 }
M.TEXT = { 235, 235, 235 }
M.DIM = { 150, 150, 150 }
M.VALUE = { 250, 185, 90 }       -- CampaignSettings stat_value_color
M.HOVER = { 240, 175, 80 }       -- the game's hovered text button
M.YELLOW = { 255, 200, 0 }
M.PANEL = { 8, 11, 14, 215 }
M.BOX = { 10, 13, 17, 210 }         -- the dark boxes of the galactic campaign screen
M.HEAD_BAR = { 52, 56, 62, 240 }    -- the header row of the tables there
M.GOLD = { 196, 146, 28 }           -- the selected tab
M.PANEL_LINE = { 255, 255, 255, 40 }
M.SHADE = { 0, 0, 0, 150 }
M.BAR_BACK = { 255, 255, 255, 28 }
M.LINK = { 255, 255, 255, 34 }
M.BORDER = { 255, 255, 255, 70 }
M.RIM = { 255, 200, 0, 90 }

M.FONT = "body"
M.FONT_LARGE = "body_large"

-- c with its alpha (0 to 255) times `share`.
function M.alpha(c, share)
	return { c[1], c[2], c[3], (c[4] or 255) * share }
end

-- Between two colours, t from 0 to 1.
function M.mix(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, (a[4] or 255) + ((b[4] or 255) - (a[4] or 255)) * t }
end

return M
