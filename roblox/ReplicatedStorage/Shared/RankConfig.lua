-- Head-to-head: ranked rating (Elo), divisions, rewards and the play clock.

local RankConfig = {}

RankConfig.StartRating = 1000
RankConfig.K = 32 -- how much one game moves your rating

-- Divisions by rating (lowest first)
RankConfig.Divisions = {
	{ name = "BRONZE", min = 0, color = Color3.fromRGB(205, 127, 70) },
	{ name = "SILVER", min = 1000, color = Color3.fromRGB(200, 205, 215) },
	{ name = "GOLD", min = 1150, color = Color3.fromRGB(255, 196, 46) },
	{ name = "PLATINUM", min = 1300, color = Color3.fromRGB(80, 220, 210) },
	{ name = "DIAMOND", min = 1450, color = Color3.fromRGB(64, 160, 255) },
	{ name = "DYNASTY", min = 1600, color = Color3.fromRGB(46, 255, 140) },
}

function RankConfig.Division(rating)
	local div = RankConfig.Divisions[1]
	for _, d in RankConfig.Divisions do
		if (rating or RankConfig.StartRating) >= d.min then
			div = d
		end
	end
	return div
end

-- New ratings for A and B after a game. scoreA: 1 win, 0.5 tie, 0 loss.
function RankConfig.Update(ratingA, ratingB, scoreA)
	local expectedA = 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
	local delta = math.floor(RankConfig.K * (scoreA - expectedA) + 0.5)
	return ratingA + delta, ratingB - delta, delta
end

-- Coins for a head-to-head game (VIP doubles)
RankConfig.Rewards = { Win = 600, Tie = 300, Loss = 200 }

-- Play clock (head-to-head only): seconds to call a play / snap before it's done for you
RankConfig.CallSeconds = 15
RankConfig.SnapSeconds = 12

-- Friendly challenges expire if not answered
RankConfig.ChallengeSeconds = 30

return RankConfig
