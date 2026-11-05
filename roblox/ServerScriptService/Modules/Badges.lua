-- Badges (server): award a Roblox badge once. Roblox shows its own "badge earned" popup.
-- Calls are cached per session so the same badge isn't requested twice.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeConfig = require(ReplicatedStorage.Shared.BadgeConfig)

local Badges = {}

local done = {} -- [Player] = { [key] = true }

function Badges.Award(player, key)
	local badge = BadgeConfig.ByKey[key]
	if not badge or badge.id == 0 or typeof(player) ~= "Instance" or not player.Parent then
		return
	end
	done[player] = done[player] or {}
	if done[player][key] then
		return
	end
	done[player][key] = true
	task.spawn(function()
		local ok, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badge.id)
		if not ok then
			warn("[Badges] couldn't award", key, err)
			done[player][key] = nil -- try again next time
		end
	end)
end

-- Everything a player has already earned (players from before badges existed, or a missed award)
function Badges.CatchUp(player, data)
	local stats = data.stats or {}
	local wins = stats.wins or 0
	if wins + (stats.losses or 0) + (stats.ties or 0) > 0 then
		Badges.Award(player, "rookie_camp")
	end
	if wins >= 1 then
		Badges.Award(player, "first_win")
	end
	if wins >= 10 then
		Badges.Award(player, "wins_10")
	end
	if wins >= 50 then
		Badges.Award(player, "wins_50")
	end
	if wins >= 250 then
		Badges.Award(player, "rainbow")
	end
	local rating = data.h2h and data.h2h.rating or 0
	if rating >= 1150 then
		Badges.Award(player, "gold_div")
	end
	if rating >= 1600 then
		Badges.Award(player, "dynasty_div")
	end
end

-- After a game: wins milestones, picks, ranked divisions
function Badges.AfterGame(player, totalWins, tally, newRating)
	Badges.Award(player, "rookie_camp")
	if totalWins >= 1 then
		Badges.Award(player, "first_win")
	end
	if totalWins >= 10 then
		Badges.Award(player, "wins_10")
	end
	if totalWins >= 50 then
		Badges.Award(player, "wins_50")
	end
	if totalWins >= 250 then
		Badges.Award(player, "rainbow")
	end
	if tally and (tally.ints or 0) > 0 then
		Badges.Award(player, "ballhawk")
	end
	if newRating and newRating >= 1150 then
		Badges.Award(player, "gold_div")
	end
	if newRating and newRating >= 1600 then
		Badges.Award(player, "dynasty_div")
	end
end

-- After a pack: Elite / Icon pulls
function Badges.AfterPack(player, tiers)
	for _, tier in tiers do
		if tier == "Elite" or tier == "Icon" then
			Badges.Award(player, "elite_pull")
		end
		if tier == "Icon" then
			Badges.Award(player, "icon_pull")
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	done[player] = nil
end)

return Badges
