-- Uploaded art (made by art/generate.py, uploaded to Roblox). Empty strings fall back to plain
-- UI shapes, so the game still works if an image is missing.

local Assets = {
	card_back = "rbxassetid://71001764659163",
	card_base = "rbxassetid://75495579535212",
	card_frame = "rbxassetid://81240714723668",
	card_tint = "rbxassetid://86116116326318",
	pack = "rbxassetid://74881757179517",
	rays = "rbxassetid://85347393071192",
	icon_close = "rbxassetid://91790189111712",
	icon_eye = "rbxassetid://120459926023881",
	icon_eyeoff = "rbxassetid://128111375810802",
	icon_chevron = "rbxassetid://91448443943483",
	shadow = "rbxassetid://84930680725435",
	icon_jersey = "rbxassetid://118316417100418",
	icon_coin = "rbxassetid://100143540206648",
	icon_collection = "rbxassetid://104964898949277",
	icon_football = "rbxassetid://138111292683576",
	icon_lineup = "rbxassetid://130332669348761",
	icon_packs = "rbxassetid://117728677575101",
	icon_switch = "rbxassetid://132867874462017",
	icon_trophy = "rbxassetid://73361124810138",
	icon_whistle = "rbxassetid://109071831456711",
	play_blitz = "rbxassetid://84766075849815",
	play_deep = "rbxassetid://94915324922103",
	play_man = "rbxassetid://81928684318608",
	play_quick = "rbxassetid://118226951453511",
	play_run = "rbxassetid://125043645901115",
	play_zone = "rbxassetid://120388596868874",
	logos = {
		ARZ = "rbxassetid://105179147319821", ATL = "rbxassetid://140103884208508", BAL = "rbxassetid://134821178963012",
		BOS = "rbxassetid://103488166314044", BUF = "rbxassetid://113268653402428", CAR = "rbxassetid://123187228596168",
		CHI = "rbxassetid://72293446617045", CIN = "rbxassetid://75379833547388", CLE = "rbxassetid://103686679768370",
		DAL = "rbxassetid://107720092654730", DEN = "rbxassetid://102570804971691", DET = "rbxassetid://82212914504909",
		GBY = "rbxassetid://94268685382452", HOU = "rbxassetid://98202750382848", IND = "rbxassetid://96781465346634",
		JAX = "rbxassetid://104639509886369", JER = "rbxassetid://126292356844768", KCY = "rbxassetid://104703392806889",
		LAS = "rbxassetid://138601016047772", LAW = "rbxassetid://126076599144685", LVG = "rbxassetid://87800499941511",
		MIA = "rbxassetid://102596160759361", MIN = "rbxassetid://127330730468012", NOL = "rbxassetid://128526196412499",
		NSH = "rbxassetid://124488070644441", NYE = "rbxassetid://74835510762093", PHI = "rbxassetid://132009168639117",
		PIT = "rbxassetid://113073955863804", SEA = "rbxassetid://87466751811280", SFG = "rbxassetid://122206945949616",
		TPA = "rbxassetid://130712271149956", WAS = "rbxassetid://97914958211945",
	},
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
