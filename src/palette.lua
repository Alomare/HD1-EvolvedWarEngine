-- The look: HELLDIVERS menus and type, with the colours of every Commander war (Super Earth blue,
-- bugs orange yellow, cyborgs red, Illuminate purple, as the war screens draw them). The panel colours
-- follow the game's menus (white text, orange values, dark boxes).
local M = {}

-- By faction: 0 Super Earth, 1 bugs, 2 cyborgs, 3 illuminates.
M.FACTION = {
	[0] = { 70, 160, 255 },
	[1] = { 255, 165, 30 },
	[2] = { 235, 72, 60 },
	[3] = { 165, 100, 255 },
}
-- Brighter, for what is under attack or selected.
M.FACTION_HOT = {
	[0] = { 130, 195, 255 },
	[1] = { 255, 205, 90 },
	[2] = { 255, 120, 100 },
	[3] = { 200, 150, 255 },
}
-- The text keys of the game for the factions' names, and what to show when a key is missing.
M.FACTION_KEY = { [0] = "campaign_faction_superearth", [1] = "campaign_faction_bugs", [2] = "campaign_faction_cyborgs", [3] = "campaign_faction_illuminates" }
M.FACTION_WORDS = { [0] = "Super Earth", [1] = "Bugs", [2] = "Cyborgs", [3] = "Illuminates" }

-- Planet surfaces by HELLDIVERS environment: desert, forest, snow, lava, city.
M.ENV = {
	[0] = { 222, 178, 110 },
	[1] = { 92, 170, 96 },
	[2] = { 214, 232, 246 },
	[3] = { 236, 98, 44 },
	[4] = { 190, 196, 210 },
}
M.ENV_KEY = { [0] = "desert", [1] = "forest", [2] = "snow", [3] = "lava", [4] = "city" }

M.WHITE = { 255, 255, 255 }
M.TEXT = { 235, 235, 235 }
M.DIM = { 150, 150, 150 }
M.VALUE = { 250, 185, 90 }       -- CampaignSettings stat_value_color
M.HOVER = { 240, 175, 80 }       -- the game's hovered text button
M.YELLOW = { 255, 200, 0 }
M.PANEL = { 8, 11, 14, 215 }
M.PANEL_LINE = { 255, 255, 255, 40 }
M.SHADE = { 0, 0, 0, 150 }
M.BAR_BACK = { 255, 255, 255, 28 }
M.LINK = { 255, 255, 255, 34 }
M.BORDER = { 255, 255, 255, 70 }
M.RIM = { 150, 190, 240, 110 }

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
