-- ReferralService (server): invite friends.
-- The client opens Roblox's invite prompt (SocialService). When a friend joins through that invite,
-- Roblox tells us who invited them (GetJoinData().ReferredByPlayerId). If the friend is brand new
-- to the game, both get Coins:
--   * the new player right away
--   * the inviter right away if they're in this server, otherwise the next time they join
--     (kept in the "Referrals_v1" DataStore until they claim it)
-- Inviters are capped at MAX_REWARDED friends so alt accounts can't farm Coins.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerData = require(script.Parent.PlayerData)

local ReferralService = {}

ReferralService.Reward = 500
ReferralService.MaxRewarded = 10
local NEW_ACCOUNT_SECONDS = 60 * 60 -- "brand new": first save made within the last hour

local pendingStore = DataStoreService:GetDataStore("Referrals_v1")
local checked = {} -- [Player] = true once handled this session
local remote

local function log(...)
	print("[Referral]", ...)
end

local function notify(player, info)
	if remote and player.Parent then
		remote:FireClient(player, info)
	end
end

-- Pay the inviter (in this server). Returns false if they've hit the cap.
local function payInviter(inviter, friendName)
	local profile = PlayerData.Get(inviter)
	if not profile then
		return false
	end
	if (profile.data.referrals or 0) >= ReferralService.MaxRewarded then
		return false
	end
	PlayerData.Update(inviter, function(data)
		data.referrals = (data.referrals or 0) + 1
	end)
	PlayerData.AddCoins(inviter, ReferralService.Reward)
	task.spawn(PlayerData.SaveNow, inviter)
	notify(inviter, { kind = "inviter", coins = ReferralService.Reward, friends = { friendName } })
	return true
end

-- Inviter is offline / in another server: leave the reward for them to claim
local function leavePending(inviterId, friendName)
	local ok, err = pcall(pendingStore.UpdateAsync, pendingStore, "p_" .. inviterId, function(old)
		old = old or { count = 0, names = {} }
		old.count += 1
		if #old.names < 5 then
			table.insert(old.names, friendName)
		end
		return old
	end)
	if not ok then
		warn("[Referral] couldn't save pending reward", err)
	end
end

-- Claim rewards friends earned for you while you were away
local function claimPending(player)
	local taken
	local ok, err = pcall(pendingStore.UpdateAsync, pendingStore, "p_" .. player.UserId, function(old)
		if not old or (old.count or 0) <= 0 then
			taken = nil
			return nil -- nothing to claim, don't write
		end
		taken = old
		return { count = 0, names = {} }
	end)
	if not ok then
		warn("[Referral] couldn't read pending rewards", err)
		return
	end
	if not taken then
		return
	end
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local room = math.max(0, ReferralService.MaxRewarded - (profile.data.referrals or 0))
	local count = math.min(taken.count, room)
	if count <= 0 then
		return
	end
	PlayerData.Update(player, function(data)
		data.referrals = (data.referrals or 0) + count
	end)
	PlayerData.AddCoins(player, count * ReferralService.Reward)
	task.spawn(PlayerData.SaveNow, player)
	log(player.Name, "claimed", count, "invite rewards")
	notify(player, { kind = "inviter", coins = count * ReferralService.Reward, friends = taken.names })
end

-- Joined through an invite? Reward a brand-new player and whoever invited them.
local function checkJoin(player)
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	local data = profile.data
	local ok, joinData = pcall(player.GetJoinData, player)
	local inviterId = ok and joinData and joinData.ReferredByPlayerId or 0
	if type(inviterId) ~= "number" or inviterId <= 0 or inviterId == player.UserId or data.referredBy then
		return
	end
	local stats = data.stats or {}
	local played = (stats.wins or 0) + (stats.losses or 0) + (stats.ties or 0)
	local isNew = played == 0 and os.time() - (data.createdAt or 0) < NEW_ACCOUNT_SECONDS
	-- remember the first referral either way, so rejoining later can't count again
	PlayerData.Update(player, function(d)
		d.referredBy = inviterId
	end)
	if not isNew then
		return
	end
	PlayerData.AddCoins(player, ReferralService.Reward)
	task.spawn(PlayerData.SaveNow, player)
	local inviter = Players:GetPlayerByUserId(inviterId)
	notify(player, { kind = "friend", coins = ReferralService.Reward, inviter = inviter and inviter.DisplayName or nil })
	log(player.Name, "joined through", inviterId, "'s invite")
	if inviter then
		payInviter(inviter, player.DisplayName)
	else
		leavePending(inviterId, player.DisplayName)
	end
end

function ReferralService.Start(remotes)
	remote = remotes:FindFirstChild("ReferralReward")
	PlayerData.Changed.Event:Connect(function(player)
		-- the first time this player's save is ready this session
		if checked[player] or not PlayerData.Get(player) then
			return
		end
		checked[player] = true
		task.spawn(function()
			task.wait(4) -- let the hub load so the toast is seen
			if not player.Parent then
				return
			end
			checkJoin(player)
			claimPending(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		checked[player] = nil
	end)
end

return ReferralService
