--!strict
-- Shared constants (server + client). Economy values mirror design/economy.md.

local GameConfig = {}

GameConfig.GameName = "Gridiron Dynasty"

-- Card data published by pipeline/build.py to GitHub Pages.
GameConfig.CardDataUrl = "https://aadiii09.github.io/GridironDynasty/cards.json"
GameConfig.CardDataRefreshSeconds = 30 * 60

GameConfig.StartingCoins = 1000

-- One random Common Base card per slot, given once to every new player (fills a 7v7 depth chart).
GameConfig.StarterSquad = {
	QB = 1, RB = 1, WR = 3, TE = 1, OL = 2,
	DL = 2, LB = 2, CB = 2, S = 1,
}

GameConfig.TierOrder = { "Common", "Rare", "Epic", "Elite", "Icon" }

GameConfig.QuickSell = {
	Common = 25, Rare = 75, Epic = 250, Elite = 1000, Icon = 3000,
}

GameConfig.TierColors = {
	Common = Color3.fromRGB(150, 156, 166),
	Rare = Color3.fromRGB(64, 160, 255),
	Epic = Color3.fromRGB(176, 92, 255),
	Elite = Color3.fromRGB(255, 196, 46),
	Icon = Color3.fromRGB(46, 255, 140),
}

return GameConfig
