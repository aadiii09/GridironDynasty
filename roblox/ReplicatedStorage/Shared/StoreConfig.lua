-- Store: Coin bundles (Developer Products), VIP (Game Pass) and daily login rewards.
--
-- Create these in Creator Hub > your experience > Monetization, then paste the IDs here.
-- Anything with id 0 shows as "Coming soon".
--
-- Policy note: Coins can be bought with Robux, so the Coin-priced packs count as paid random
-- items. Players whose PolicyService says ArePaidRandomItemsRestricted can't buy Coins, which
-- keeps every Coin they own earned in-game (so their Coin packs stay allowed).

local StoreConfig = {}

-- How to earn Coins without paying (shown in the Store)
StoreConfig.EarnInfo = {
	{ "Win a game", "+400" },
	{ "Tie a game", "+250" },
	{ "Lose a game", "+150" },
	{ "Daily login (streak bonus)", "+200 to +500" },
	{ "Quick-sell cards", "+25 to +3,000" },
}

StoreConfig.CoinBundles = {
	{ id = "coins_1", coins = 3000, price = 39, productId = 3728100112 },
	{ id = "coins_2", coins = 8000, price = 99, productId = 3728100137, tag = "POPULAR" },
	{ id = "coins_3", coins = 20000, price = 199, productId = 3728100195, tag = "+30% BONUS" },
	{ id = "coins_4", coins = 55000, price = 499, productId = 3728100229, tag = "BEST VALUE" },
}

StoreConfig.VIP = {
	name = "VIP PASS",
	price = 199,
	gamePassId = 2067973914,
	perks = { "2x Coins from every game", "2x daily login reward", "Gold VIP tag in your profile" },
}

-- Daily login: base + streak bonus (streak caps at day 7)
StoreConfig.Daily = { base = 200, perDay = 50, maxStreak = 7 }

function StoreConfig.DailyAmount(streak, vip)
	local d = StoreConfig.Daily
	local amount = d.base + d.perDay * (math.clamp(streak, 1, d.maxStreak) - 1)
	return vip and amount * 2 or amount
end

StoreConfig.BundleById = {}
StoreConfig.BundleByProductId = {}
for _, b in StoreConfig.CoinBundles do
	StoreConfig.BundleById[b.id] = b
	if b.productId ~= 0 then
		StoreConfig.BundleByProductId[b.productId] = b
	end
end

return StoreConfig
