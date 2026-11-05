-- Pack definitions shared by server (rolling) and client (shop + odds display).
-- Odds are per card slot and every table sums to 100. A pack's last slot uses `guaranteed`
-- odds when present. The server shows players the exact odds it rolls with (see PackService.GetOdds).
--
-- Robux packs need a Developer Product each (Creator Hub > Monetization > Developer Products).
-- Put each product's ID in productId. A Robux pack with productId 0 is shown as "Coming soon".
-- coinPrice: a Robux pack can also be bought with Coins (priced so Robux stays the better deal,
-- about 400 Coins a win: Pro ~15 wins, Elite ~38, Dynasty ~100).

local PackConfig = {}

PackConfig.FreePackCooldown = 22 * 60 * 60

PackConfig.Packs = {
	{
		id = "daily",
		name = "Daily Free Pack",
		blurb = "One free pack every 22 hours",
		currency = "Free",
		price = 0,
		cards = 3,
		odds = { Common = 80, Rare = 17, Epic = 2.7, Elite = 0.3, Icon = 0 },
		color = Color3.fromRGB(120, 130, 145),
	},
	{
		id = "starter",
		name = "Starter Pack",
		blurb = "5 cards",
		currency = "Coins",
		price = 2500,
		cards = 5,
		odds = { Common = 70, Rare = 24, Epic = 5, Elite = 0.9, Icon = 0.1 },
		color = Color3.fromRGB(64, 160, 255),
	},
	{
		id = "pro",
		name = "Pro Pack",
		blurb = "5 cards, 1 Rare or better",
		currency = "Robux",
		price = 49,
		coinPrice = 6000,
		productId = 3728099990,
		cards = 5,
		odds = { Common = 60, Rare = 30, Epic = 8, Elite = 1.7, Icon = 0.3 },
		guaranteed = { Rare = 85, Epic = 12, Elite = 2.5, Icon = 0.5 },
		color = Color3.fromRGB(176, 92, 255),
	},
	{
		id = "elite",
		name = "Elite Pack",
		blurb = "8 cards, 1 Epic or better",
		currency = "Robux",
		price = 149,
		coinPrice = 15000,
		productId = 3728100025,
		cards = 8,
		odds = { Common = 45, Rare = 37, Epic = 14, Elite = 3.5, Icon = 0.5 },
		guaranteed = { Epic = 80, Elite = 17, Icon = 3 },
		color = Color3.fromRGB(255, 196, 46),
	},
	{
		id = "dynasty",
		name = "Dynasty Pack",
		blurb = "10 cards, 1 Elite or better",
		currency = "Robux",
		price = 399,
		coinPrice = 40000,
		productId = 3728100054,
		cards = 10,
		odds = { Common = 30, Rare = 40, Epic = 22, Elite = 6.5, Icon = 1.5 },
		guaranteed = { Elite = 85, Icon = 15 },
		color = Color3.fromRGB(46, 255, 140),
	},
}

PackConfig.ById = {}
PackConfig.ByProductId = {}
for _, pack in PackConfig.Packs do
	PackConfig.ById[pack.id] = pack
	if pack.productId and pack.productId ~= 0 then
		PackConfig.ByProductId[pack.productId] = pack
	end
end

-- What this pack costs in Coins (nil = can't be bought with Coins)
function PackConfig.CoinPrice(pack)
	if pack.currency == "Coins" then
		return pack.price
	end
	return pack.coinPrice
end

function PackConfig.IsPaidRandom(pack)
	return pack.currency == "Robux"
end

return PackConfig
