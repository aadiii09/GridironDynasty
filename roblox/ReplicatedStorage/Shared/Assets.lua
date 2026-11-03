-- Uploaded art (made by art/generate.py). Empty strings fall back to plain UI shapes.
-- Filled in after uploading art/out/*.png to Roblox.

local Assets = {
	card_back = "",
	card_base = "",
	card_frame = "",
	card_tint = "",
	pack = "",
	rays = "",
	icon_close = "",
	icon_coin = "",
	icon_collection = "",
	icon_football = "",
	icon_lineup = "",
	icon_packs = "",
	icon_switch = "",
	icon_trophy = "",
	icon_whistle = "",
	play_blitz = "",
	play_deep = "",
	play_man = "",
	play_quick = "",
	play_run = "",
	play_zone = "",
	logos = {}, -- [teamId] = "rbxassetid://..."
}

-- Roblox's own default R15 animations (usable in any experience)
Assets.Animations = {
	run = "rbxassetid://913376220",
	walk = "rbxassetid://913402848",
	idle = "rbxassetid://507766666",
	fall = "rbxassetid://507767968",
}

function Assets.Logo(teamId)
	return Assets.logos[teamId] or ""
end

return Assets
