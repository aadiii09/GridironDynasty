-- MatchService (server): live 7v7 games. Each team ("user" side A, "cpu" side B) is either
-- played by a human or by the AI:
--   vs CPU:       side A = you, side B = AI team
--   head-to-head: side A and side B are both players (ranked or friendly)
--
-- Human offense: pick a play, snap, throw (keys 1-4) or hand off; after a catch/handoff your
--   avatar takes over the ball carrier.
-- Human defense: pick a coverage (man / deep zone / blitz) and play one defender (Q switches,
--   auto-switch on throws). AI offense: the QB reads coverage and throws to the open man; its
--   ball carriers dodge tacklers.
-- Every client gets the game from its own point of view (sendState).
-- Every player moves and plays by his card's ratings (see Ratings.lua):
--   SPD/ACC top speed and burst, THP ball speed + range, SAC/MAC/DAC accuracy by distance,
--   TUP accuracy under pressure, RUN accuracy on the move, AWR CPU QB reads,
--   SRR/MRR/DRR separation at the route break, RLS vs PRS press at the snap,
--   CTH/CIT/SPC open, contested and off-target catches, MCV/ZCV man and zone coverage,
--   PBK/PBP/PBF vs PMV/FMV pass rush, RBK/RBP/RBF vs BSH run blocking, STR power battles,
--   TRK/SFA/JKM/SPM/ELU/BCV broken tackles and running lanes, TAK/POW/CAR tackles and fumbles,
--   PUR pursuit angles, PRC run reads.
--
-- Field coordinates are always in the frame of the team with the ball (see Field.lua).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local LineupConfig = require(ReplicatedStorage.Shared.LineupConfig)
local CardDatabase = require(ServerScriptService.Modules.CardDatabase)
local PlayerData = require(ServerScriptService.Modules.PlayerData)
local Field = require(ServerScriptService.Modules.Match.Field)
local Npc = require(ServerScriptService.Modules.Match.Npc)
local StoreService = require(ServerScriptService.Modules.StoreService)
local Ratings = require(ReplicatedStorage.Shared.Ratings)
local Jerseys = require(ReplicatedStorage.Shared.Jerseys)
local ChallengeService = require(ServerScriptService.Modules.ChallengeService)
local LeaderboardService = require(ServerScriptService.Modules.LeaderboardService)
local RankConfig = require(ReplicatedStorage.Shared.RankConfig)

local MatchService = {}
MatchService.PlayerExited = Instance.new("BindableEvent") -- (player) left a game, back to the lobby

local Y = MatchConfig.Yard
local L = MatchConfig.FieldLength()
local HALF_W = MatchConfig.HalfWidth()
local TACKLE_RANGE = 3.2
local AVATAR_TACKLE_RANGE = 4.6 -- you get a bigger tackle radius than the AI
local GREEN = Color3.fromRGB(46, 255, 140)
local RED = Color3.fromRGB(255, 90, 90)
local GOLD = Color3.fromRGB(255, 214, 40)

local remotes
local matches = {} -- [Player] = match
local rng = Random.new()
local setBallVisible, releaseBall, holdBall, setPose -- ball + pose helpers (defined further down)
local PRESNAP_POSE = { OL1 = "stance3", OL2 = "stance3", DL1 = "stance3", DL2 = "stance3", QB = "qb" }

local function log(...)
	print("[Match]", ...)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function hdist(a, b)
	return flat(a - b).Magnitude
end

local function chance(p)
	return rng:NextNumber() < p
end

local function lerp(a, b, t)
	return a + (b - a) * math.clamp(t, 0, 1)
end

local function weighted(options)
	local total = 0
	for _, o in options do
		total += o[2]
	end
	local roll = rng:NextNumber(0, total)
	for _, o in options do
		roll -= o[2]
		if roll <= 0 then
			return o[1]
		end
	end
	return options[#options][1]
end

-- Sides ---------------------------------------------------------------------------------------
local function other(side)
	return side == "user" and "cpu" or "user"
end

local function isPlayer(p)
	return typeof(p) == "Instance" and p:IsA("Player")
end

local function offHuman(m) -- the player on offense right now (nil = AI offense)
	return m.humans[m.possession]
end

local function defHuman(m) -- the player on defense right now (nil = AI defense)
	return m.humans[other(m.possession)]
end

local function sideOf(m, player)
	for side, p in m.humans do
		if p == player then
			return side
		end
	end
	return nil
end

local function fire(player, payload)
	if isPlayer(player) and player.Parent then
		remotes.MatchState:FireClient(player, payload)
	end
end

local function fillerCard(pos)
	local attrs = {}
	for _, k in Ratings.All do
		attrs[k] = 40
	end
	return { id = "FILLER", pid = "FILLER", ovr = 40, pos = pos, attrs = attrs }
end

-- Squads ------------------------------------------------------------------------------

-- A starter boosted by team chemistry: +n to OVR and every rating (max 99)
local function boosted(card, n)
	if not n or n <= 0 then
		return card
	end
	local c = table.clone(card)
	c.ovr = math.min(99, card.ovr + n)
	c.attrs = {}
	for k, v in card.attrs do
		c.attrs[k] = math.min(99, v + n)
	end
	c.chem = n
	return c
end

local function userSquad(profile)
	local cards, infos = {}, {}
	for _, slot in LineupConfig.Slots do
		local uid = profile.data.lineup[slot.id]
		local entry = uid and profile.data.cards[uid]
		local card = entry and CardDatabase.Get(entry.id)
		cards[slot.id] = card or fillerCard(slot.pos)
		infos[slot.id] = card and CardDatabase.GetPlayerInfo(card.pid) or { last = "Backup", number = 0 }
	end
	local bySlot = {}
	for slotId in cards do
		bySlot[slotId] = slotId
	end
	local chem = LineupConfig.Chemistry(bySlot, function(slotId)
		return cards[slotId]
	end)
	for slotId, n in chem.boost do
		cards[slotId] = boosted(cards[slotId], n)
	end
	return cards, infos, chem
end

local function cpuSquad(targetOvr)
	local teams = CardDatabase.Teams()
	local team = teams[rng:NextInteger(1, #teams)]
	local all = CardDatabase.All()
	local cards, infos, usedPid = {}, {}, {}
	for _, slot in LineupConfig.Slots do
		local want = targetOvr + rng:NextInteger(-4, 3)
		local best, bestScore
		for _, card in all do
			if card.program == "Base" and card.pos == slot.pos and not usedPid[card.pid] then
				local score = math.abs(card.ovr - want) + (card.team == team.id and 0 or 6) + rng:NextNumber(0, 2)
				if not bestScore or score < bestScore then
					best, bestScore = card, score
				end
			end
		end
		best = best or fillerCard(slot.pos)
		usedPid[best.pid] = true
		cards[slot.id] = best
		infos[slot.id] = CardDatabase.GetPlayerInfo(best.pid) or { last = "CPU", number = 0 }
	end
	return team, cards, infos
end

local function ratingsFor(cards)
	local lineup = {}
	for slotId in cards do
		lineup[slotId] = slotId
	end
	return LineupConfig.TeamRatings(lineup, function(slotId)
		return cards[slotId]
	end, true) -- chemistry is already in the (boosted) cards
end

-- Avatar ----------------------------------------------------------------------------------

local function avatarParts(m, player)
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return char, hum, root
end

-- A human defender as a "unit" so blocking, tackling and coverage treat him like an NPC.
local function makeAvatarUnit(m, npc, player)
	local u = {
		isAvatar = true,
		player = player,
		slot = npc.slot,
		card = npc.card,
		attrs = npc.attrs,
		info = npc.info,
		speed = npc.speed,
		rampTime = npc.rampTime,
		stunUntil = 0,
		engagedUntil = 0,
		engageFactor = 0,
		tackleReadyAt = 0,
	}
	function u:Position()
		local _, _, root = avatarParts(m, player)
		return root and root.Position or Vector3.zero
	end
	function u:Velocity()
		local _, _, root = avatarParts(m, player)
		return root and flat(root.AssemblyLinearVelocity) or Vector3.zero
	end
	return u
end

-- Per-game stats for challenges (counted when the game finishes), per side
local function tally(m, side, key, n)
	local t = m.tally[side]
	t[key] = (t[key] or 0) + (n or 1)
end

-- tone "good" / "bad" = good or bad for the OFFENSE; each viewer sees green when it's good for them
local function colorFor(m, side, tone)
	if typeof(tone) == "Color3" then
		return tone
	elseif tone == "good" or tone == "bad" then
		local goodForViewer = (tone == "good") == (side == m.possession)
		return goodForViewer and GREEN or RED
	end
	return nil
end

-- Floating text over a player (shown on every human's client): the rating behind a play
local function callout(m, unit, text, tone)
	local model
	if unit == "avatar" then
		local p = offHuman(m)
		model = p and p.Character
	elseif type(unit) == "table" and unit.isAvatar then
		model = unit.player and unit.player.Character
	elseif type(unit) == "table" then
		model = unit.model
	end
	if not model then
		return
	end
	for side, p in m.humans do
		local c = colorFor(m, side, tone) or Color3.new(1, 1, 1)
		fire(p, { event = "callout", model = model, text = text, color = c:ToHex() })
	end
end

-- viewer: the player reading it ("YOU" for himself, his name for the other human)
local function nameOf(unit, viewer)
	if unit and unit.isAvatar then
		if unit.player == viewer or viewer == nil then
			return "YOU"
		end
		return string.upper(unit.player.DisplayName or unit.player.Name or "")
	end
	return unit and string.upper(unit.info and unit.info.last or "") or ""
end

local function teamName(m, side)
	local team = m[side] and m[side].team
	return team and string.upper(team.name) or ""
end

-- State to client -----------------------------------------------------------------------

-- message / color: a value, or function(viewer, side) for text that depends on who reads it
local function stateFor(m, viewer, side, message, color)
	local offense = m.possession == side
	local opp = other(side)
	local targets = {}
	if offense then
		for i, slotId in MatchConfig.Targets do
			local route = m.call and m.call.routes[slotId]
			local unit = m.units.Offense[slotId]
			table.insert(targets, {
				key = i, slot = slotId, pos = unit.card.pos, name = nameOf(unit, viewer), available = type(route) == "table",
				ovr = unit.card.ovr, spd = unit.attrs.SPD, cth = unit.attrs.CTH, model = unit.model,
			})
		end
	end
	local controlled = not offense and m.avatarUnit and m.avatarUnit.player == viewer and m.units.Defense[m.controlSlot]
	-- field position from this viewer's point of view
	local yourYards = offense and m.los / Y or MatchConfig.FieldYards - m.los / Y
	local phase = m.phase
	if phase == "calls" then
		if offense then
			phase = m.call and "waiting" or "playcall"
		else
			phase = m.defCall and "waiting" or "defcall"
		end
	end
	local msg = type(message) == "function" and message(viewer, side) or message
	local col = type(color) == "function" and color(viewer, side) or colorFor(m, side, color)
	local oppTeam = m[opp].team
	return {
		phase = phase,
		mode = m.mode,
		possession = offense and "user" or "cpu",
		you = m.score[side],
		cpu = m.score[opp],
		opponent = { id = oppTeam.id, city = oppTeam.city, name = oppTeam.name, primary = oppTeam.primary, secondary = oppTeam.secondary, human = oppTeam.human },
		drive = m.drive,
		drives = MatchConfig.DrivesPerTeam,
		down = m.down,
		toGo = m.firstDown >= L and "GOAL" or tostring(math.max(1, math.ceil((m.firstDown - m.los) / Y - 0.01))),
		spot = MatchConfig.SpotText(yourYards),
		ratings = { you = m[side].ratings, cpu = m[opp].ratings },
		play = (offense or m.phase ~= "calls") and m.call and m.call.id or nil,
		defCall = (not offense or m.phase ~= "calls") and m.defCall or nil,
		playState = m.play and m.play.state,
		air = (m.play and m.play.state == "air" and m.play.air) and {
			from = m.play.air.from,
			to = m.play.air.to,
			T = m.play.air.T,
			h = m.play.air.h,
			startedAt = m.play.air.startedAt,
		} or nil,
		targets = targets,
		control = controlled and { slot = m.controlSlot, pos = controlled.card.pos, name = nameOf(controlled, viewer) } or nil,
		canSnap = m.phase == "presnap" and (offense or not offHuman(m)),
		clockEndsAt = m.clockEndsAt,
		-- for the broadcast camera
		losWorld = m.field:ToWorld(0, m.los, 0),
		downfield = m.field:Downfield(),
		ball = m.ball,
		message = msg,
		messageColor = col and col:ToHex(),
		final = m.final and m.final[side],
		difficulty = m.modeLabel,
	}
end

local function sendState(m, message, color)
	for side, p in m.humans do
		fire(p, stateFor(m, p, side, message, color))
	end
end

-- Possession + formation --------------------------------------------------------------------

local function setPossession(m, who)
	m.possession = who
	m.field.flipped = who == "cpu"
	m.controlSlot = m.control[other(who)] or MatchConfig.DefaultControl
	local off = who == "user" and m.user or m.cpu
	local def = who == "user" and m.cpu or m.user
	m.units = { Offense = off.off, Defense = def.def }
	for _, unit in off.def do
		unit:Hide(true)
	end
	for _, unit in def.off do
		unit:Hide(true)
	end
end

local function placeAvatar(m, player, cf, speed)
	local char, hum, root = avatarParts(m, player)
	if not root then
		return
	end
	root.Anchored = false
	char:PivotTo(cf + Vector3.new(0, 3, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	hum.WalkSpeed = speed
end

local function lineUp(m)
	for _, ring in m.rings or {} do
		ring:Destroy()
	end
	m.rings = {}
	local offHum, defHum = offHuman(m), defHuman(m)
	for slotId, unit in m.units.Offense do
		local spot = MatchConfig.Formation.Offense[slotId]
		local cf = m.field:CFrameAt(spot[1] * Y, m.los + spot[2] * Y, 0, true)
		unit.home = cf.Position
		if offHum and slotId == "QB" then
			unit:Hide(true)
			placeAvatar(m, offHum, cf, unit.speed)
		else
			unit:Hide(false)
			unit:Place(cf)
			unit:SetTag(("%d %s %s"):format(unit.card.ovr, unit.card.pos, nameOf(unit)))
		end
	end
	m.avatarUnit = nil
	for slotId, unit in m.units.Defense do
		local spot = MatchConfig.Formation.Defense[slotId]
		local cf = m.field:CFrameAt(spot[1] * Y, m.los + spot[2] * Y, 0, false)
		unit.home = cf.Position
		if defHum and slotId == m.controlSlot then
			unit:Hide(true)
			placeAvatar(m, defHum, cf, unit.speed)
			m.avatarUnit = makeAvatarUnit(m, unit, defHum)
		else
			unit:Hide(false)
			unit:Place(cf)
			unit:SetTag(("%d %s %s"):format(unit.card.ovr, unit.card.pos, nameOf(unit)))
		end
	end
	m.field:SetMarkers(m.los, m.firstDown)
	m.ball.Parent = m.field.model
	-- everyone settles into a stance; the QB has the ball
	for _, side in m.units do
		for slotId, unit in side do
			local pos = unit.card.pos
			setPose(unit, PRESNAP_POSE[slotId] or ((pos == "OL" or pos == "DL") and "stance3" or "stance2"))
		end
	end
	holdBall(m, offHum and "avatar" or m.units.Offense.QB)
end

local function clearRings(m)
	for _, ring in m.rings or {} do
		ring:Destroy()
	end
	m.rings = {}
end

local function tagTargets(m)
	clearRings(m)
	for i, slotId in MatchConfig.Targets do
		local unit = m.units.Offense[slotId]
		local route = m.call and m.call.routes[slotId]
		if type(route) == "table" and not m.call.run then
			unit:SetTag(("[%d] %d %s %s"):format(i, unit.card.ovr, unit.card.pos, nameOf(unit)), GOLD)
			-- glowing target ring at his feet
			local ring = Instance.new("Part")
			ring.Name = "TargetRing"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.15, 5, 5)
			ring.Material = Enum.Material.Neon
			ring.Color = GOLD
			ring.Transparency = 0.35
			ring.CanCollide = false
			ring.CanQuery = false
			ring.Massless = true
			ring.CastShadow = false
			ring.CFrame = CFrame.new(unit.root.Position - Vector3.new(0, unit.humanoid.HipHeight + unit.root.Size.Y / 2 - 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = unit.root
			weld.Part1 = ring
			weld.Parent = ring
			ring.Parent = unit.model
			table.insert(m.rings, ring)
		end
	end
end

local function burst(m, pos, color, count, kind)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = pos
	local e = Instance.new("ParticleEmitter")
	if kind == "confetti" then
		e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, GOLD) })
		e.Size = NumberSequence.new(0.5)
		e.Speed = NumberRange.new(30, 55)
		e.SpreadAngle = Vector2.new(45, 45)
		e.Acceleration = Vector3.new(0, -30, 0)
		e.Lifetime = NumberRange.new(2.5, 4)
		e.RotSpeed = NumberRange.new(-300, 300)
		e.Rotation = NumberRange.new(0, 360)
		e.EmissionDirection = Enum.NormalId.Top
		e.LightEmission = 0.3
	else -- tackle dust
		e.Color = ColorSequence.new(Color3.fromRGB(180, 200, 160))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		e.Speed = NumberRange.new(6, 12)
		e.SpreadAngle = Vector2.new(180, 30)
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Acceleration = Vector3.new(0, 4, 0)
	end
	e.Rate = 0
	e.Parent = p
	p.Parent = m.field.model
	e:Emit(count)
	task.delay(5, function()
		p:Destroy()
	end)
end

local function makeBall()
	local art = ReplicatedStorage:FindFirstChild("Art")
	local mesh = art and art:FindFirstChild("Football")
	local ball
	if mesh and mesh:IsA("BasePart") then
		-- AI football: its long axis is X; wrap it so the long axis points along -Z (flight direction)
		ball = Instance.new("Part")
		ball.Size = Vector3.new(0.8, 0.8, 1.2)
		ball.Transparency = 1
		local m = mesh:Clone()
		m.Name = "Visual"
		m.Size = m.Size * 1.7
		m.Anchored = false
		m.Massless = true
		m.CanCollide = false
		m.CanTouch = false
		m.CFrame = CFrame.Angles(0, math.rad(90), 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = ball
		w.Part1 = m
		w.Parent = m
		m.Parent = ball
	else
		ball = Instance.new("Part")
		ball.Size = Vector3.new(0.75, 0.75, 1.25)
		ball.Color = Color3.fromRGB(122, 64, 34)
		ball.Material = Enum.Material.Leather
		local sm = Instance.new("SpecialMesh")
		sm.MeshType = Enum.MeshType.Sphere
		sm.Parent = ball
	end
	ball.Name = "Football"
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Massless = true
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.2, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.2, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.LightEmission = 0.6
	trail.Enabled = false
	trail.Parent = ball
	return ball, trail
end

-- Ball handling ------------------------------------------------------------------------------
-- A held ball is welded to the carrier's hand so it moves with him on every client (no lag).
-- A thrown ball is hidden here and drawn by each client from the throw's arc (see MatchFX).

function setBallVisible(m, visible)
	local visual = m.ball:FindFirstChild("Visual")
	if visual then
		visual.Transparency = visible and 0 or 1
	else
		m.ball.Transparency = visible and 0 or 1
	end
end

function releaseBall(m)
	if m.ballWeld then
		m.ballWeld:Destroy()
		m.ballWeld = nil
	end
	m.ball.Anchored = true
end

-- holder: "avatar" or an Npc
function holdBall(m, holder)
	releaseBall(m)
	local offHum = offHuman(m)
	local char = holder == "avatar" and offHum and offHum.Character or (holder ~= "avatar" and holder and holder.model)
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("HumanoidRootPart"))
	setBallVisible(m, true)
	if not hand then
		return
	end
	m.ball.CFrame = hand.CFrame * CFrame.new(0, -0.35, -0.3)
	m.ball.Anchored = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = m.ball
	w.Parent = m.ball
	m.ballWeld = w
end

-- Poses are read by every client (MatchFX) and layered on top of the run/idle animations.
function setPose(unit, pose, duration)
	if not unit or unit.isAvatar or not unit.model then
		return
	end
	unit.model:SetAttribute("Pose", pose)
	if duration then
		task.delay(duration, function()
			if unit.model and unit.model:GetAttribute("Pose") == pose then
				unit.model:SetAttribute("Pose", nil)
			end
		end)
	end
end


-- All defenders that can tackle / cover right now (NPCs + you when you're on defense)
local function defenders(m)
	local list = {}
	for _, d in m.units.Defense do
		if not d.hidden then
			table.insert(list, d)
		end
	end
	if m.avatarUnit then
		table.insert(list, m.avatarUnit)
	end
	return list
end

local function defenderAt(m, slotId)
	if m.avatarUnit and m.avatarUnit.slot == slotId then
		return m.avatarUnit
	end
	return m.units.Defense[slotId]
end

-- Ball carrier -----------------------------------------------------------------------------

local function carrierPos(m)
	if m.play and m.play.state == "air" then
		return m.play.air.to -- while the ball is in the air, everyone keys on the landing spot
	end
	local c = m.play and m.play.carrier
	if c == "avatar" then
		local _, _, root = avatarParts(m, offHuman(m))
		return root and root.Position
	end
	return c and c:Position()
end

local function carrierVel(m)
	if m.play and m.play.state == "air" then
		return Vector3.zero
	end
	local c = m.play and m.play.carrier
	if c == "avatar" then
		local _, _, root = avatarParts(m, offHuman(m))
		return root and flat(root.AssemblyLinearVelocity) or Vector3.zero
	end
	return c and c:Velocity() or Vector3.zero
end

local function compileRoutes(m)
	local routes = {}
	for slotId, route in m.call.routes do
		if type(route) == "table" then
			local unit = m.units.Offense[slotId]
			local x0, y0 = m.field:ToField(unit.home)
			local out = x0 >= 0 and 1 or -1
			local points, depth = {}, 0
			for _, wp in route do
				local x = math.clamp(x0 + out * wp[1] * Y, -HALF_W + 3, HALF_W - 3)
				table.insert(points, m.field:ToWorld(x, y0 + wp[2] * Y, 0))
				depth = math.max(depth, wp[2])
			end
			-- short / medium / deep route: which route-running rating wins the break
			local rr = depth <= 8 and "SRR" or depth <= 16 and "MRR" or "DRR"
			routes[slotId] = { points = points, index = 1, rr = rr }
		end
	end
	return routes
end

-- Your ball: put your avatar in place of an offensive NPC (catch or handoff).
local function swapInto(m, slotId)
	local unit = m.units.Offense[slotId]
	local player = offHuman(m)
	local char, hum, root = avatarParts(m, player)
	if not root then
		return
	end
	local oldCF = root.CFrame
	local qb = m.units.Offense.QB
	root.Anchored = false
	char:PivotTo(unit.root.CFrame)
	root.AssemblyLinearVelocity = unit:Velocity()
	unit:Hide(true)
	qb:Hide(false)
	qb:Place(CFrame.new(oldCF.Position - Vector3.new(0, 3, 0)) * oldCF.Rotation)
	m.play.carrier = "avatar"
	m.play.carrierCard = unit.card
	m.play.carrierName = nameOf(unit)
	hum.WalkSpeed = unit.speed
	m.av[player] = { speed = unit.speed, ramp = unit.rampTime, accelFrom = os.clock() - unit.rampTime * 0.5 }
	m.play.state = "carry"
	setPose(qb, "block")
	holdBall(m, "avatar")
end

-- CPU ball: an NPC becomes the ball carrier.
local function giveTo(m, unit)
	m.play.carrier = unit
	m.play.carrierCard = unit.card
	m.play.carrierName = nameOf(unit)
	m.play.state = "carry"
	setPose(m.units.Offense.QB, nil)
	setPose(unit, "carry")
	holdBall(m, unit)
end

-- You on defense: jump into another defender (nearest the ball). The one you leave becomes AI.
local function switchControl(m, slotId)
	local target = m.units.Defense[slotId]
	local current = m.units.Defense[m.controlSlot]
	local player = defHuman(m)
	local char, hum, root = avatarParts(m, player)
	if not target or not current or target == current or not root then
		return
	end
	local anchored = root.Anchored
	local myCF = root.CFrame
	root.Anchored = false
	char:PivotTo(target.root.CFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = anchored
	target:Hide(true)
	current:Hide(false)
	current:Place(CFrame.new(myCF.Position - Vector3.new(0, 3, 0)) * myCF.Rotation)
	m.controlSlot = slotId
	m.control[other(m.possession)] = slotId
	m.avatarUnit = makeAvatarUnit(m, target, player)
	hum.WalkSpeed = target.speed
	local av = m.av[player]
	m.av[player] = { speed = target.speed, ramp = target.rampTime, accelFrom = av and av.accelFrom or os.clock() }
end

-- On defense, jump you to the defender closest to where the ball is going (throw, catch,
-- handoff), unless you're already near it. You can still switch yourself with Q.
local function autoSwitch(m, pos)
	if not MatchConfig.AutoSwitch or not defHuman(m) or not m.avatarUnit or not pos then
		return
	end
	local mine = hdist(m.avatarUnit:Position(), pos)
	local best, bestD
	for slotId, unit in m.units.Defense do
		if not unit.hidden then
			local d = hdist(unit:Position(), pos)
			if not bestD or d < bestD then
				best, bestD = slotId, d
			end
		end
	end
	if best and bestD + 4 < mine then
		switchControl(m, best)
		m.lastSwitch = os.clock()
	end
end

-- Play engine --------------------------------------------------------------------------------

local endPlay, throwBall -- forward

-- The ball carrier's ratings (the card of whoever has the ball)
local function carrierAttrs(m)
	local c = m.play.carrier
	if c and c ~= "avatar" and c.attrs then
		return c.attrs
	end
	return Ratings.Wrap(m.play.carrierCard and m.play.carrierCard.attrs)
end

-- A tackler arrives: the carrier answers with his best move for the angle (truck / stiff arm /
-- juke / spin from the front, spin or pure elusiveness from behind). TAK vs that move decides it;
-- a made tackle can jar the ball loose (POW vs CAR).
local function attemptTackle(m, def, now)
	local c = carrierAttrs(m)
	local d = def.attrs
	local cPos = carrierPos(m)
	local vel = carrierVel(m)
	local sack = m.play.state == "dropback"
	local fromBehind = vel.Magnitude > 4 and flat(def:Position() - cPos):Dot(vel.Unit) < -1
	local moves
	if sack then
		moves = { { "ESCAPED", math.max(c.ELU, c.AGI) - 10 } }
	elseif fromBehind then
		moves = { { "SPIN MOVE", c.SPM }, { "SLIPPED AWAY", (c.ELU + c.BCV) / 2 - 4 } }
	else
		moves = {
			{ "TRUCKED", c.TRK + (c.STR - d.STR) * 0.25 },
			{ "STIFF ARM", c.SFA + (c.STR - d.STR) * 0.15 },
			{ "JUKED", c.JKM + (c.AGI - d.AGI) * 0.15 },
			{ "SPIN MOVE", c.SPM },
		}
	end
	table.sort(moves, function(x, y)
		return x[2] > y[2]
	end)
	-- usually his best move, sometimes his second best
	local pick = (#moves > 1 and chance(0.25)) and moves[2] or moves[1]
	local moveName, move = pick[1], pick[2]
	local tak = d.TAK + (fromBehind and 6 or 0)
	local p = math.clamp(0.64 + (tak - move) * 0.013, 0.22, 0.94)
	if sack then
		p = math.clamp(0.72 + (d.TAK - move) * 0.01, 0.45, 0.96)
	end
	if def.isAvatar then
		p = math.min(0.97, p + 0.1) -- a little help when you make the hit
	end
	def.tackleReadyAt = now + (def.isAvatar and 0.8 or 1.4)
	if chance(p) then
		local pos = carrierPos(m)
		local _, fy = m.field:ToField(pos)
		-- the ball carrier goes down
		local carrier = m.play.carrier
		if carrier == "avatar" then
			fire(offHuman(m), { event = "fall" })
		elseif carrier then
			carrier:Fall()
		end
		burst(m, pos - Vector3.new(0, 2.5, 0), nil, 14, "dust")
		setPose(def, "dive", 1.2)
		m.play.bigHit = d.POW >= 80 and chance((d.POW - 70) / 60)
		local pFumble = math.clamp(0.008 + (d.POW - c.CAR) * 0.0014 + (m.play.bigHit and 0.015 or 0), 0.003, 0.06)
		if sack then
			callout(m, def, "SACK!", GOLD)
		elseif m.play.bigHit then
			callout(m, def, "BIG HIT!", GOLD)
		end
		if chance(pFumble) then
			callout(m, def, "FORCED FUMBLE!", GOLD)
			endPlay(m, "fumble", fy, def)
		else
			endPlay(m, sack and "sack" or "tackle", fy, def)
		end
	else
		-- beaten: the better the move beat him, the longer he's out of the play
		def.stunUntil = now + math.clamp(0.55 + (move - tak) * 0.01, 0.4, 1)
		log(("tackle broken: %s %d vs TAK %d (%.0f%% to tackle)"):format(moveName, move, tak, p * 100))
		callout(m, m.play.carrier, moveName .. "!", "good")
		tally(m, m.possession, "broken")
		if def.isAvatar or offHuman(m) then
			sendState(m, function(_, side)
				if side == m.possession then
					return moveName .. "!"
				end
				return moveName == "ESCAPED" and "HE ESCAPED!" or (moveName .. " - MISSED TACKLE!")
			end, "good")
		end
	end
end

-- NPC ball carrier: head for the end zone, steering away from nearby tacklers.
local function runnerMove(m, unit, now)
	local pos = unit:Position()
	local dir = m.field:Downfield()
	local push = Vector3.zero
	-- vision: good runners spot tacklers (and the open lane) earlier
	local sight = 5 + unit.attrs.BCV * 0.07
	for _, d in defenders(m) do
		local offset = flat(pos - d:Position())
		local dist = offset.Magnitude
		-- only react to tacklers in front of / beside the runner
		if dist < sight and dist > 0.1 and offset:Dot(dir) < 2 then
			push += offset.Unit * (sight - dist) / sight
		end
	end
	-- elusive runners cut harder; everyone mostly runs north-south
	local juke = math.clamp((unit.attrs.ELU - 40) / 60, 0.15, 1) * 0.75
	local steer = dir + Vector3.new(push.X, 0, push.Z) * juke
	local target = pos + steer.Unit * 10
	-- stay in bounds
	local tx, ty = m.field:ToField(target)
	tx = math.clamp(tx, -HALF_W + 4, HALF_W - 4)
	unit:MoveTo(m.field:ToWorld(tx, ty, 0), now)
end

-- CPU QB: wait for routes to develop, throw to whoever is most open, hurry under pressure.
local function cpuQbDecide(m, now)
	local play = m.play
	local qb = m.units.Offense.QB
	local t = now - play.t0
	play.throwAt = play.throwAt or rng:NextNumber(1.3, 2.6)
	local defs = defenders(m)
	local pressure = false
	for _, d in defs do
		if hdist(d:Position(), qb:Position()) < 6 then
			pressure = true
		end
	end
	local misread = (100 - qb.attrs.AWR) * 0.07 -- low awareness sometimes throws to a covered man
	local best, bestScore, bestOpen
	for slotId in play.routes do
		local rcv = m.units.Offense[slotId]
		local open = math.huge
		for _, d in defs do
			open = math.min(open, hdist(d:Position(), rcv:Position()))
		end
		local _, ry = m.field:ToField(rcv:Position())
		local score = math.min(open, 12) + (ry - m.los) * 0.05 + rng:NextNumber(-misread, misread)
		if not bestScore or score > bestScore then
			best, bestScore, bestOpen = rcv, score, open
		end
	end
	local poise = 0.5 + qb.attrs.TUP * 0.007 -- calm QBs stand in longer when pressured
	if best and ((t >= play.throwAt and bestOpen >= 3.5) or (pressure and t > poise) or t > 3.4) then
		throwBall(m, best)
	end
end

-- A receiver breaks off his stem: crisp route runners (SRR/MRR/DRR by route depth, plus AGI)
-- lose less speed in the cut, and a man defender he out-classes (vs MCV) bites and loses a step.
local function routeBreak(m, unit, route, coverage, now)
	local rr = unit.attrs[route.rr]
	unit.slowUntil = now + math.clamp(0.5 - (rr - 50) * 0.006 - (unit.attrs.AGI - 70) * 0.002, 0.12, 0.5)
	unit.slowFactor = 0.5
	if m.defCall == "zone" then
		return
	end
	for dSlot, oSlot in coverage do
		if oSlot == unit.slot then
			local d = defenderAt(m, dSlot)
			if d and not d.isAvatar then
				local lag = math.clamp(0.2 + (rr - d.attrs.MCV) * 0.012, 0.05, 0.6)
				d.reactAt = math.max(d.reactAt or 0, now + lag)
				if lag >= 0.36 then
					callout(m, unit, "SHOOK HIM!", "good")
				end
			end
		end
	end
end

-- Press at the snap (man / blitz): the corner's PRS vs the receiver's RLS. A jammed receiver is
-- held up at the line; a whiffed jam leaves the corner a step behind.
local function pressAtLine(m, now)
	if m.call.run or m.defCall == "zone" then
		return
	end
	for _, cb in { "CB1", "CB2" } do
		local wrSlot = MatchConfig.Coverage[cb]
		local wr = m.units.Offense[wrSlot]
		local d = defenderAt(m, cb)
		if d and wr and not wr.hidden and m.play.routes[wrSlot] then
			local edge = d.attrs.PRS - wr.attrs.RLS
			if chance(math.clamp(0.45 + edge * 0.025, 0.08, 0.92)) then
				wr.engagedUntil = now + math.clamp(0.45 + edge * 0.01, 0.25, 0.75)
				wr.engageFactor = 0.7
				callout(m, wr, "JAMMED", "bad")
				log(("press: %s jammed %s (PRS %d vs RLS %d)"):format(cb, wrSlot, d.attrs.PRS, wr.attrs.RLS))
			else
				d.stunUntil = now + 0.35
				callout(m, wr, "WON THE RELEASE", "good")
				log(("press: %s beat the jam by %s (RLS %d vs PRS %d)"):format(wrSlot, cb, wr.attrs.RLS, d.attrs.PRS))
			end
		end
	end
end

local function think(m, now)
	local play = m.play
	local ballPos = carrierPos(m)
	if not ballPos then
		return
	end
	local cVel = carrierVel(m)
	local off, def = m.units.Offense, m.units.Defense
	local defList = defenders(m)
	local call = m.defCall or "man"
	-- you're a free player: the AI safety picks up the man of whoever you control
	local coverage = MatchConfig.Coverage
	if m.avatarUnit and coverage[m.avatarUnit.slot] then
		coverage = table.clone(coverage)
		coverage.S = coverage[m.avatarUnit.slot]
	end

	-- offense ---------------------------------------------------------------------------
	for slotId, unit in off do
		if not unit.hidden then
			local route = play.routes[slotId]
			if play.carrier == unit then
				if play.state == "carry" then
					runnerMove(m, unit, now)
				else
					-- CPU QB in the pocket: settle a yard deeper than his spot
					unit:MoveTo(unit.home - m.field:Downfield() * Y, now)
				end
			elseif play.state == "air" and play.air.target == unit then
				-- the ball is coming to him: break off the route and attack the landing spot
				unit:MoveTo(play.air.to, now)
			elseif play.state ~= "carry" and route then
				local target = route.points[route.index]
				if hdist(unit:Position(), target) < 2.5 and route.index < #route.points then
					route.index += 1
					target = route.points[route.index]
					routeBreak(m, unit, route, coverage, now)
				end
				unit:MoveTo(target, now)
			else
				-- block: the assigned rusher in pass pro, otherwise the nearest threat to the ball
				local assigned = MatchConfig.BlockAssignments[slotId]
				local victim = assigned and defenderAt(m, assigned)
				if play.state == "carry" or not victim then
					local best, bestD = nil, 30
					for _, d in defList do
						local dd = hdist(d:Position(), unit:Position())
						if dd < bestD and hdist(d:Position(), ballPos) < 35 then
							best, bestD = d, dd
						end
					end
					victim = best
				end
				if victim then
					local between = victim:Position() + flat(ballPos - victim:Position()).Unit * 1.5
					unit:MoveTo(between, now)
					if hdist(unit:Position(), victim:Position()) < 4.5 then
						local b, v = unit.attrs, victim.attrs
						local power = v.STR - b.STR -- who wins the shove
						local keep -- how much of his speed the defender keeps while engaged
						if play.state == "carry" then
							-- run block: block shedding vs the blocker's drive (RBP) on big men, reach (RBF) on quick ones
							local blk = b.RBK * 0.5 + (v.STR >= v.AGI and b.RBP or b.RBF) * 0.5
							keep = math.clamp(0.3 + (v.BSH - blk) * 0.009 + power * 0.002, 0.08, 0.65)
						else
							-- pass rush: the rusher uses his better move; the blocker answers with anchor or feet
							local usePower = v.PMV >= v.FMV
							local move = usePower and v.PMV or v.FMV
							local blk = b.PBK * 0.5 + (usePower and b.PBP or b.PBF) * 0.5
							keep = math.clamp(0.18 + (move - blk) * 0.009 + (usePower and power * 0.002 or 0), 0.04, 0.5)
						end
						play.called = play.called or {}
						if play.state ~= "carry" and keep >= 0.34 and not play.called[victim] then
							play.called[victim] = true
							callout(m, victim, v.PMV >= v.FMV and "BULL RUSH" or "SWIM MOVE", GOLD)
						elseif keep <= 0.08 and not play.called[unit] then
							play.called[unit] = true
							callout(m, unit, "PANCAKE", GOLD)
						end
						if victim.isAvatar then
							keep = math.max(keep, 0.45) -- you can always fight through a block a bit
						end
						victim.engagedUntil = now + 0.3
						victim.engageFactor = 1 - keep
					end
				else
					unit:MoveTo(ballPos + m.field:Downfield() * 12, now)
				end
			end
		end
	end

	-- defense (AI defenders; the one you control is hidden and skipped) ------------------------
	local deepestY, deepestX = m.los, 0
	for slotId in play.routes do
		local x, y = m.field:ToField(off[slotId]:Position())
		if y > deepestY then
			deepestY, deepestX = y, x
		end
	end
	for slotId, unit in def do
		if not unit.hidden then
			local target
			local pursue = play.state == "carry"
			local readTime = math.clamp(0.95 - (unit.attrs.PRC - 50) * 0.012, 0.25, 0.95)
			local reading = pursue and play.handoffAt and now - play.handoffAt < readTime and slotId ~= "DL1" and slotId ~= "DL2"
			local ballSkill = (call == "zone" and unit.attrs.ZCV or unit.attrs.MCV) + unit.attrs.AWR
			local breakAfter = math.clamp(0.5 - (ballSkill - 100) * 0.005, 0.08, 0.5)
			local isLB = slotId == "LB1" or slotId == "LB2"
			if reading then
				target = nil
			elseif play.state == "air" and hdist(unit:Position(), play.air.to) < 40 and now - play.air.t0 >= breakAfter then
				target = play.air.to
			elseif pursue then
				local lead = math.clamp(hdist(unit:Position(), ballPos) / unit.speed, 0, 0.8) * (0.3 + unit.attrs.PUR * 0.008)
				target = ballPos + cVel * lead
			elseif slotId == "DL1" or slotId == "DL2" or (call == "blitz" and isLB) then
				target = ballPos
			elseif slotId == "S" and not coverage.S then
				target = m.field:ToWorld(deepestX * 0.5, math.max(m.los + 12 * Y, deepestY + 5 * Y), 0)
			else
				local mark = off[coverage[slotId]]
				if mark and not mark.hidden and play.routes[mark.slot] then
					local mx, my = m.field:ToField(mark:Position())
					if call == "zone" then
						local zcv = unit.attrs.ZCV
						if isLB then
							target = m.field:ToWorld(mx * (0.3 + zcv * 0.006), m.los + 5 * Y, 0)
						else
							local cushion = math.clamp(3.6 - (zcv - 50) * 0.05, 1.2, 3.6)
							target = m.field:ToWorld(mx, math.max(my + cushion * Y, m.los + 7 * Y), 0)
						end
					else
						local cov = unit.attrs.MCV
						if now >= (unit.reactAt or 0) then
							unit.coverPoint = mark:Position() + mark:Velocity() * 0.35 + m.field:Downfield() * 1.5
							unit.reactAt = now + math.clamp(0.5 - (cov - 50) * 0.007, 0.12, 0.5)
						end
						target = unit.coverPoint
					end
				else
					-- his man stayed in to block: spy the QB a few yards past the line
					local qx = m.field:ToField(ballPos)
					target = m.field:ToWorld(qx, m.los + 4 * Y, 0)
				end
			end
			unit:MoveTo(target or unit:Position(), now)
		end
	end

	if not offHuman(m) and play.state == "dropback" and not m.call.run then
		cpuQbDecide(m, now)
	end

	for _, side in m.units do
		for _, unit in side do
			unit:Animate()
		end
	end
end

local function updateBall(m, now)
	local play = m.play
	-- in the air: the server only tracks timing; every client draws the flight itself (MatchFX).
	-- in hand: the ball is welded to the carrier, so nothing to do here.
	if play.state == "air" then
		local a = play.air
		return (now - a.t0) / a.T >= 1
	end
	return false
end

-- The ball arrives: interception chances (coverage + the defender's hands), then the catch:
-- CTH when open, CIT with a defender on him (vs MCV/ZCV), SPC to reach off-target throws.
local function resolveCatch(m)
	local a = m.play.air
	local rcv = a.target
	local r = rcv.attrs
	local rcvDist = hdist(rcv:Position(), a.to)
	local nearest, sep = nil, math.huge
	for _, d in defenders(m) do
		local dd = hdist(d:Position(), a.to)
		if dd < sep then
			nearest, sep = d, dd
		end
	end
	local cov = nearest and (m.defCall == "zone" and nearest.attrs.ZCV or nearest.attrs.MCV) or 50
	-- you (on defense) near the landing spot: a real shot at the pick, otherwise a likely breakup
	local me = m.avatarUnit
	local meDist = me and hdist(me:Position(), a.to) or math.huge
	if me and meDist < 4.5 then
		local myCov = m.defCall == "zone" and me.attrs.ZCV or me.attrs.MCV
		local pInt = math.clamp(0.16 + (4.5 - meDist) * 0.09 + (myCov - 60) * 0.004 + (me.attrs.CTH - 50) * 0.004 + (rcvDist > 4 and 0.15 or 0), 0.12, 0.65)
		log(("pick check: you %.1f from the ball, chance %.0f%%"):format(meDist, pInt * 100))
		if chance(pInt) then
			callout(m, me, "PICKED OFF!", GOLD)
			endPlay(m, "int", nil, me)
			return
		end
	elseif nearest and not nearest.isAvatar and sep < 3.2 then
		-- ~2-3% normally, ~10% into tight coverage by a good cover man, more on bad throws
		local pInt = math.clamp(0.015 + (cov - 60) * 0.0018 + (nearest.attrs.CTH - 50) * 0.0012 + math.max(0, 2.5 - sep) * 0.04 + (rcvDist > 4 and 0.1 or 0), 0.01, 0.25)
		if chance(pInt) then
			callout(m, nearest, "PICKED OFF!", GOLD)
			endPlay(m, "int", nil, nearest)
			return
		end
	end
	-- spectacular catchers get to throws other receivers can't
	local reach = 3.6 + (r.SPC - 50) * 0.035
	if rcvDist <= reach then
		local breakup = (me and meDist < 4.5) and 0.3 or 0
		local pCatch = 0.58 + r.CTH * 0.0042
		if nearest and sep < 3 then
			-- contested: catch in traffic vs the defender's coverage
			pCatch -= (3 - sep) / 3 * math.clamp(0.32 + (cov - r.CIT) * 0.006, 0.08, 0.55)
		end
		if rcvDist > 1.5 then
			-- off target: spectacular catch
			pCatch -= (rcvDist - 1.5) * math.clamp(0.13 - (r.SPC - 50) * 0.0018, 0.03, 0.16)
		end
		pCatch = math.clamp(pCatch - breakup, 0.05, 0.97)
		log(("catch check: CTH %d CIT %d SPC %d, ball %.1f off, defender %.1f away (cover %d)%s, chance %.0f%%"):format(
			r.CTH, r.CIT, r.SPC, rcvDist, sep, cov, nearest and nearest.isAvatar and " (you)" or "", pCatch * 100))
		if chance(pCatch) then
			if nearest and sep < 2.2 then
				callout(m, rcv, "CATCH IN TRAFFIC", "good")
			elseif rcvDist > 2.4 then
				callout(m, rcv, "SPECTACULAR CATCH", "good")
			end
			local catchMsg = function(viewer, side)
				return side == m.possession and "CAUGHT! RUN!" or ("CAUGHT BY " .. nameOf(rcv, viewer) .. " - TACKLE HIM!")
			end
			m.play.caught = true
			if offHuman(m) then
				swapInto(m, rcv.slot)
			else
				giveTo(m, rcv)
			end
			autoSwitch(m, rcv:Position())
			sendState(m, catchMsg, "good")
			return
		end
		if breakup > 0 then
			callout(m, me, "BROKEN UP!", "bad")
			endPlay(m, "drop", nil, me, rcv)
		else
			callout(m, rcv, "DROPPED", "bad")
			endPlay(m, "drop", nil, nearest, rcv)
		end
		return
	end
	endPlay(m, "incomplete")
end

local function step(m)
	local play = m.play
	if not play or play.state == "dead" then
		return
	end
	local now = os.clock()

	if updateBall(m, now) then
		resolveCatch(m)
		return
	end

	-- your player: builds up to top speed (ACC); on defense slowed while a blocker is on you,
	-- frozen briefly after a missed tackle
	for player, av in m.av do
		local _, hum = avatarParts(m, player)
		if hum and av.speed then
			local speed = av.speed * MatchConfig.Ramp(av.ramp or 0.6, now - (av.accelFrom or 0))
			local u = m.avatarUnit
			if u and u.player == player then
				if now < u.stunUntil then
					speed *= 0.3
					av.accelFrom = u.stunUntil
				elseif now < u.engagedUntil then
					speed *= (1 - u.engageFactor)
				end
			end
			hum.WalkSpeed = speed
		end
	end

	local pos = carrierPos(m)
	if not pos then
		endPlay(m, "timeout", m.los)
		return
	end
	local fx, fy = m.field:ToField(pos)

	if play.state ~= "air" and math.abs(fx) > HALF_W then
		endPlay(m, "out", fy)
		return
	end
	if play.state == "carry" and fy >= L then
		endPlay(m, "td", fy)
		return
	end
	if offHuman(m) and play.state == "dropback" and fy > m.los + Y then
		play.state = "carry" -- QB scramble: no throwing past the line
		play.carrierCard = m.units.Offense.QB.card
		sendState(m, "SCRAMBLE!", GOLD)
	end
	if now - play.t0 > MatchConfig.MaxPlaySeconds then
		endPlay(m, "timeout", play.state == "air" and m.los or fy)
		return
	end

	-- tackles (and sacks) on the ball carrier
	if play.state == "dropback" or play.state == "carry" then
		for _, d in defenders(m) do
			local blocked = now < d.engagedUntil and not d.isAvatar
			if not blocked and now >= d.stunUntil and now >= (d.tackleReadyAt or 0) and hdist(d:Position(), pos) < (d.isAvatar and AVATAR_TACKLE_RANGE or TACKLE_RANGE) then
				attemptTackle(m, d, now)
				if play.state == "dead" then
					return
				end
				break
			end
		end
	end

	if now >= play.nextThink then
		play.nextThink = now + 0.1
		think(m, now)
	end
end

local startDrive, nextPlay, nextPossession, finishGame -- forward

function endPlay(m, result, spotY, defender, receiver)
	local play = m.play
	if not play or play.state == "dead" then
		return
	end
	local wasAir = play.state == "air"
	play.state = "dead"
	if play.conn then
		play.conn:Disconnect()
	end
	if wasAir and play.air then
		-- incomplete / dropped / picked: the ball ends up on the turf where it landed
		releaseBall(m)
		local ground = m.field:ToWorld(0, 0, 0).Y
		m.ball.CFrame = CFrame.new(play.air.to.X, ground + 0.4, play.air.to.Z) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 359)), math.rad(90))
		setBallVisible(m, true)
	end
	if result == "td" and play.carrier and play.carrier ~= "avatar" then
		setPose(play.carrier, "celebrate", 2.5)
	end
	for _, side in m.units do
		for _, unit in side do
			unit.humanoid:Move(Vector3.zero)
			if unit.runTrack and unit.runTrack.IsPlaying then
				unit.runTrack:Stop(0.4)
			end
		end
	end
	for p in m.av do
		local _, hum = avatarParts(m, p)
		if hum then
			hum.WalkSpeed = 0
		end
	end
	for _, p in m.humans do
		local _, hum = avatarParts(m, p)
		if hum then
			hum.WalkSpeed = 0
		end
	end

	local off, def = m.possession, other(m.possession)
	local yards = spotY and (spotY - m.los) / Y or 0
	if result == "td" then
		tally(m, off, "td")
		tally(m, off, play.caught and "passTd" or "rushTd")
	end
	if spotY and yards > 0 and (result == "td" or result == "tackle" or result == "out" or result == "timeout") then
		tally(m, off, "yards", math.floor(yards + 0.5))
	end
	if result == "sack" then
		tally(m, def, "sacks")
	elseif result == "int" then
		tally(m, def, "ints")
	elseif result == "fumble" then
		tally(m, def, "fumbles")
	end
	if result == "tackle" or result == "sack" or result == "fumble" then
		tally(m, def, "stops")
	end

	local driveOver, suffix = false, nil
	local tone -- "good"/"bad" for the offense, or function(viewer, side)
	if result == "td" then
		m.score[off] += MatchConfig.TouchdownPoints
		tone, driveOver = "good", true
		local ez = MatchConfig.EndZoneYards * Y
		local confetti = m[off].confetti
		for _, x in { -20, 0, 20 } do
			burst(m, m.field:ToWorld(x, L + ez / 2, 1), confetti, 70, "confetti")
		end
	elseif result == "fumble" or result == "int" then
		tone, driveOver = "bad", true
	elseif result == "incomplete" or result == "drop" then
		tone = function(_, side)
			return side == m.possession and Color3.fromRGB(255, 196, 46) or GREEN
		end
		spotY = m.los
	elseif spotY and spotY < 0 then
		m.score[def] += MatchConfig.SafetyPoints
		tone, driveOver = "bad", true
	else
		tone = function(_, side)
			if side == m.possession then
				return yards >= 0 and Color3.new(1, 1, 1) or Color3.fromRGB(255, 120, 90)
			end
			return yards <= 2 and GREEN or Color3.new(1, 1, 1)
		end
	end

	if not driveOver then
		m.los = math.clamp(spotY or m.los, Y, L - Y)
		if m.los >= m.firstDown then
			m.down = 1
			m.firstDown = math.min(m.los + MatchConfig.FirstDownYards * Y, L)
			suffix = "first"
		else
			m.down += 1
			if m.down > 4 then
				suffix = "downs"
				tone = "bad"
				driveOver = true
			end
		end
	end

	local offName = teamName(m, off)
	local function message(viewer, side)
		local mine = side == m.possession -- this viewer is on offense
		local msg
		if result == "td" then
			msg = mine and "TOUCHDOWN!" or (offName .. " TOUCHDOWN")
		elseif result == "fumble" then
			msg = mine and ("FUMBLE! " .. nameOf(defender, viewer) .. " forced it - turnover") or ("FUMBLE! Forced by " .. nameOf(defender, viewer) .. "!")
		elseif result == "int" then
			msg = (mine and "INTERCEPTED by " or "INTERCEPTION by ") .. nameOf(defender, viewer) .. (mine and "" or "!")
		elseif result == "drop" then
			if defender and defender.isAvatar then
				msg = "PASS BROKEN UP by " .. nameOf(defender, viewer) .. "!"
			else
				msg = "DROPPED by " .. nameOf(receiver, viewer)
			end
		elseif result == "incomplete" then
			msg = "INCOMPLETE"
		elseif spotY and spotY < 0 then
			msg = "SAFETY"
		else
			local by = nameOf(defender, viewer)
			local verb = result == "sack" and ("SACKED by " .. by) or result == "out" and "Out of bounds" or result == "timeout" and "Whistle" or ((play.bigHit and "BIG HIT by " or "Tackled by ") .. by)
			msg = ("%s  (%+d yds)"):format(verb, math.floor(yards + (yards >= 0 and 0.5 or -0.5)))
		end
		if suffix == "first" then
			msg ..= "  -  FIRST DOWN"
		elseif suffix == "downs" then
			msg ..= mine and "  -  TURNOVER ON DOWNS" or "  -  STOPPED ON DOWNS!"
		end
		return msg
	end

	m.phase = "result"
	m.clockEndsAt = nil
	m.field:SetScreen(("%s %d  -  %d %s"):format(teamName(m, "user"), m.score.user, m.score.cpu, teamName(m, "cpu")))
	log(("%s ball, %s/%s: %s after %.1fs -> %s"):format(m.possession, m.call and m.call.id or "?", m.defCall or "?", result, os.clock() - (play.t0 or os.clock()), message(nil, m.possession)))
	sendState(m, message, tone)
	local token = m.token
	task.delay(2.6, function()
		if m.token ~= token or not m.alive then
			return
		end
		if driveOver then
			nextPossession(m)
		else
			nextPlay(m)
		end
	end)
end

local function snap(m)
	local play = m.play
	local offHum, defHum = offHuman(m), defHuman(m)
	play.state = "dropback"
	play.t0 = os.clock()
	play.nextThink = 0
	play.routes = compileRoutes(m)
	play.carrier = offHum and "avatar" or m.units.Offense.QB
	m.clockEndsAt = nil
	play.carrierCard = m.units.Offense.QB.card
	m.phase = "live"
	for _, side in m.units do
		for _, unit in side do
			unit.accelFrom = play.t0
			unit.slowUntil = 0
			unit.reactAt = 0
		end
	end
	-- out of the stance: linemen (and anyone staying in to block) block, everyone else runs
	for _, side in m.units do
		for slotId, unit in side do
			local blocker = side == m.units.Offense and (slotId == "OL1" or slotId == "OL2" or m.call.routes[slotId] == "block")
			setPose(unit, blocker and "block" or nil)
		end
	end
	m.av = {}
	for p, mine in { [offHum or false] = m.units.Offense.QB, [defHum or false] = m.avatarUnit } do
		if p and mine then
			local _, hum, root = avatarParts(m, p)
			if root then
				root.Anchored = false
				hum.WalkSpeed = mine.speed
				m.av[p] = { speed = mine.speed, ramp = mine.rampTime or 0.6, accelFrom = play.t0 }
			end
		end
	end
	pressAtLine(m, play.t0)
	if m.call.run then
		local token = m.token
		task.delay(0.45, function()
			if m.token == token and m.play == play and play.state == "dropback" then
				play.handoffAt = os.clock()
				local rb = m.units.Offense.RB
				local rbPos = rb:Position()
				if offHuman(m) then
					swapInto(m, "RB")
				else
					giveTo(m, rb)
				end
				autoSwitch(m, rbPos)
				sendState(m, function(_, side)
					return side == m.possession and "HANDOFF - RUN!" or "IT'S A RUN!"
				end, GOLD)
			end
		end)
	end
	play.conn = RunService.Heartbeat:Connect(function()
		step(m)
	end)
	sendState(m)
end

-- Throw from the current QB to a receiver NPC (used by you and by the CPU QB).
function throwBall(m, rcv)
	local play = m.play
	local route = play.routes[rcv.slot]
	local from = carrierPos(m)
	if not from or not route or rcv.hidden then
		return
	end
	local qb = m.units.Offense.QB.attrs
	local ballSpeed = 40 + qb.THP * 0.4 -- THP 70 -> 68, 95 -> 78 studs/s
	if defHuman(m) then
		ballSpeed *= 0.8 -- throws hang a little longer when a human is on defense, so he can react
	end
	-- lead the receiver along his actual route (so throws hit him after his cut), at the speed
	-- he's really moving (still building up, jammed, or in a cut), not just his top speed
	local runSpeed = math.clamp((rcv:Velocity().Magnitude + rcv.speed) / 2, rcv.speed * 0.5, rcv.speed)
	local function along(t)
		local pos = flat(rcv:Position())
		local budget = runSpeed * t
		for i = route.index, #route.points do
			local wp = flat(route.points[i])
			local seg = (wp - pos).Magnitude
			if budget <= seg then
				return (seg > 0 and pos + (wp - pos).Unit * budget or pos) + Vector3.new(0, rcv:Position().Y, 0)
			end
			budget -= seg
			pos = wp
		end
		return pos + Vector3.new(0, rcv:Position().Y, 0)
	end
	local predicted = rcv:Position()
	local T = 0.1
	for _ = 1, 4 do
		T = hdist(predicted, from) / ballSpeed + 0.05
		predicted = along(T)
	end
	local dist = hdist(predicted, from)
	local yards = dist / Y
	-- accuracy for this distance: short / medium / deep, blended between
	local acc
	if yards <= 8 then
		acc = qb.SAC
	elseif yards <= 14 then
		acc = lerp(qb.SAC, qb.MAC, (yards - 8) / 6)
	elseif yards <= 20 then
		acc = qb.MAC
	elseif yards <= 26 then
		acc = lerp(qb.MAC, qb.DAC, (yards - 20) / 6)
	else
		acc = qb.DAC
	end
	-- arm strength: past his range the ball dies and sails
	local range = 18 + qb.THP * 0.35
	if yards > range then
		acc -= (yards - range) * 3
	end
	-- throwing on the move
	local moving = math.clamp((carrierVel(m).Magnitude - 6) / 10, 0, 1)
	if moving > 0 then
		acc = lerp(acc, qb.RUN - 4, moving)
	end
	-- a rusher in his face
	local closest = math.huge
	for _, d in defenders(m) do
		closest = math.min(closest, hdist(d:Position(), from))
	end
	local pressure = math.clamp((7 - closest) / 5, 0, 1)
	acc -= pressure * (100 - qb.TUP) * 0.45
	local errMag = (100 - math.clamp(acc, 20, 99)) * 0.038 * math.clamp(dist / 45, 0.5, 2.5) * rng:NextNumber(0.2, 1)
	log(("throw: %.0f yds, accuracy %.0f (moving %.0f%%, pressure %.0f%%), off by %.1f"):format(yards, acc, moving * 100, pressure * 100, errMag))
	local angle = rng:NextNumber(0, math.pi * 2)
	local to = predicted + Vector3.new(math.cos(angle) * errMag, 0, math.sin(angle) * errMag)
	play.air = {
		from = from + Vector3.new(0, 1.5, 0),
		to = Vector3.new(to.X, from.Y, to.Z),
		T = T,
		t0 = os.clock(),
		startedAt = workspace:GetServerTimeNow(), -- clients draw the flight from this
		h = math.clamp(dist * 0.18, 3, 22),
		target = rcv,
	}
	if not offHuman(m) then
		setPose(m.units.Offense.QB, "throw", 0.6)
	end
	releaseBall(m)
	setBallVisible(m, false)
	m.ball.CFrame = CFrame.new(play.air.from)
	play.carrier = nil
	play.state = "air"
	autoSwitch(m, play.air.to)
	sendState(m)
end

local function userThrow(m, player, key)
	local play = m.play
	local slotId = MatchConfig.Targets[key]
	if offHuman(m) ~= player or not play or play.state ~= "dropback" or m.call.run or not slotId or not play.routes[slotId] then
		return
	end
	throwBall(m, m.units.Offense[slotId])
end

local function cpuPlayCall(m)
	local toGo = (m.firstDown - m.los) / Y
	local options
	if m.down >= 3 and toGo > 6 then
		options = { { "quick", 45 }, { "deep", 45 }, { "run", 10 } }
	elseif toGo <= 3 then
		options = { { "quick", 30 }, { "deep", 15 }, { "run", 55 } }
	else
		options = { { "quick", 40 }, { "deep", 25 }, { "run", 35 } }
	end
	return MatchConfig.PlaysById[weighted(options)]
end

local function aiDefCall()
	return weighted({ { "man", 60 }, { "zone", 25 }, { "blitz", 15 } })
end

-- Both calls are in: line up for the snap
local function beginPresnap(m)
	m.play = { state = "presnap" }
	m.phase = "presnap"
	if offHuman(m) then
		tagTargets(m)
	end
	m.clockEndsAt = m.h2h and (workspace:GetServerTimeNow() + RankConfig.SnapSeconds) or nil
	sendState(m)
	if m.clockEndsAt then
		local token = m.token
		task.delay(RankConfig.SnapSeconds, function()
			if m.token == token and m.alive and m.phase == "presnap" then
				snap(m) -- play clock ran out: snap it
			end
		end)
	end
end

local function makeCall(m, which, id)
	if m.phase ~= "calls" then
		return
	end
	if which == "off" and not m.call then
		m.call = MatchConfig.PlaysById[id]
	elseif which == "def" and not m.defCall then
		m.defCall = id
	end
	if m.call and m.defCall then
		beginPresnap(m)
	else
		sendState(m) -- the one who called now waits for the other
	end
end

function nextPlay(m)
	m.token += 1
	m.play = nil
	m.call = nil
	m.defCall = nil
	m.phase = "calls"
	-- the AI side calls at once
	if not offHuman(m) then
		m.call = cpuPlayCall(m)
	end
	if not defHuman(m) then
		m.defCall = aiDefCall()
	end
	lineUp(m)
	m.clockEndsAt = m.h2h and (workspace:GetServerTimeNow() + RankConfig.CallSeconds) or nil
	sendState(m)
	if m.clockEndsAt then
		local token = m.token
		task.delay(RankConfig.CallSeconds, function()
			if m.token == token and m.alive and m.phase == "calls" then
				-- play clock ran out: call it for whoever hasn't
				if not m.call then
					makeCall(m, "off", cpuPlayCall(m).id)
				end
				if not m.defCall then
					makeCall(m, "def", aiDefCall())
				end
			end
		end)
	end
end

function startDrive(m, who)
	setPossession(m, who)
	m.los = MatchConfig.StartYard * Y
	m.down = 1
	m.firstDown = m.los + MatchConfig.FirstDownYards * Y
	nextPlay(m)
	sendState(m, function(_, side)
		if side == who then
			return ("YOUR BALL  -  DRIVE %d OF %d"):format(m.drive, MatchConfig.DrivesPerTeam)
		end
		return teamName(m, who) .. " BALL  -  DEFENSE!"
	end, function(_, side)
		return side == who and GREEN or GOLD
	end)
end

function nextPossession(m)
	if m.possession == "user" then
		startDrive(m, "cpu")
	else
		m.drive += 1
		if m.drive > MatchConfig.DrivesPerTeam then
			finishGame(m)
		else
			startDrive(m, "user")
		end
	end
end

-- Rewards for one human side. resultFor: "Win" / "Loss" / "Tie" from that side's view.
local function award(m, side, result, ratingChange)
	local player = m.humans[side]
	local vip = isPlayer(player) and StoreService.IsVIP(player) or false
	local coins
	if m.h2h then
		coins = RankConfig.Rewards[result] * (vip and 2 or 1)
	else
		coins = MatchConfig.RewardFor(result, m.difficulty.id) * (vip and 2 or 1)
	end
	local unlocked = {}
	local opp = other(side)
	if isPlayer(player) and PlayerData.Get(player) and not m.noRewards then
		PlayerData.AddCoins(player, coins)
		PlayerData.Update(player, function(data)
			if result == "Win" then
				data.stats.wins += 1
				for _, j in Jerseys.NewlyUnlocked(data.stats.wins - 1, data.stats.wins) do
					table.insert(unlocked, j.name)
				end
			elseif result == "Loss" then
				data.stats.losses += 1
			else
				data.stats.ties = (data.stats.ties or 0) + 1
			end
			if m.h2h then
				local h = data.h2h or { rating = RankConfig.StartRating, wins = 0, losses = 0, ties = 0 }
				data.h2h = h
				h[result == "Win" and "wins" or result == "Loss" and "losses" or "ties"] += 1
				if ratingChange then
					h.rating = ratingChange.new
				end
			end
		end)
		local win = result == "Win" and 1 or 0
		local hard = m.h2h or m.difficulty.order >= 3
		local t = m.tally[side]
		ChallengeService.Record(player, {
			games = 1,
			wins = win,
			winsPro = (win == 1 and (m.h2h or m.difficulty.order >= 2)) and 1 or 0,
			winsAllPro = (win == 1 and hard) and 1 or 0,
			shutouts = (win == 1 and m.score[opp] == 0) and 1 or 0,
			td = t.td, passTd = t.passTd, rushTd = t.rushTd, yards = t.yards,
			sacks = t.sacks, ints = t.ints, fumbles = t.fumbles, stops = t.stops, broken = t.broken,
		})
		task.spawn(PlayerData.SaveNow, player) -- after the challenge progress is in
		if win == 1 then
			local profile = PlayerData.Get(player)
			LeaderboardService.RecordWin(player, profile and profile.data.stats.wins or 0)
		end
		if ratingChange then
			LeaderboardService.RecordRating(player, ratingChange.new)
		end
	end
	return {
		result = result,
		coins = coins,
		vip = vip,
		unlocked = unlocked,
		difficulty = m.modeLabel,
		multiplier = m.h2h and 1 or m.difficulty.reward,
		tally = m.tally[side],
		rating = ratingChange,
		forfeit = m.forfeitBy ~= nil,
	}
end

local function ratingOf(player)
	local profile = isPlayer(player) and PlayerData.Get(player)
	local h = profile and profile.data.h2h
	return h and h.rating or RankConfig.StartRating
end

function finishGame(m)
	if m.phase == "final" then
		return
	end
	m.token += 1
	m.phase = "final"
	m.clockEndsAt = nil
	if m.play and m.play.conn then
		m.play.conn:Disconnect()
	end
	local a, b = m.score.user, m.score.cpu
	-- a forfeit is a loss for whoever left, whatever the score
	local resultA = a > b and "Win" or a < b and "Loss" or "Tie"
	if m.forfeitBy == "user" then
		resultA = "Loss"
	elseif m.forfeitBy == "cpu" then
		resultA = "Win"
	end
	local results = { user = resultA, cpu = resultA == "Win" and "Loss" or resultA == "Loss" and "Win" or "Tie" }
	local changes = {}
	if m.ranked then
		local ra, rb = ratingOf(m.humans.user), ratingOf(m.humans.cpu)
		local na, nb = RankConfig.Update(ra, rb, resultA == "Win" and 1 or resultA == "Tie" and 0.5 or 0)
		changes.user = { old = ra, new = na, division = RankConfig.Division(na).name }
		changes.cpu = { old = rb, new = nb, division = RankConfig.Division(nb).name }
	end
	m.final = {}
	for side in m.humans do
		m.final[side] = award(m, side, results[side], changes[side])
	end
	log(("game over (%s): %s %d - %d %s%s"):format(m.mode, teamName(m, "user"), a, b, teamName(m, "cpu"), m.forfeitBy and (" (forfeit by " .. m.forfeitBy .. ")") or ""))
	sendState(m, function(_, side)
		local r = results[side]
		if m.forfeitBy and m.forfeitBy ~= side then
			return "OPPONENT LEFT - YOU WIN!"
		end
		return r == "Win" and "YOU WIN!" or r == "Loss" and "YOU LOSE" or "TIE GAME"
	end, function(_, side)
		return results[side] == "Win" and GREEN or Color3.fromRGB(255, 196, 46)
	end)
end

-- Lifecycle -------------------------------------------------------------------------------

local function destroyMatch(m)
	if not m.alive then
		return
	end
	m.alive = false
	m.token += 1
	if m.play and m.play.conn then
		m.play.conn:Disconnect()
	end
	for _, team in { m.user, m.cpu } do
		for _, side in { team.off, team.def } do
			for _, unit in side do
				unit:Destroy()
			end
		end
	end
	if m.field then
		m.field:Destroy()
	end
	if m.onDestroy then
		m.onDestroy()
	end
end

-- One player leaves the game (quit, left the server, respawned): back to the lobby. In a live
-- head-to-head game that's a forfeit. The match is torn down once no humans are left.
local function exitPlayer(m, player)
	local side = sideOf(m, player)
	if not side then
		return
	end
	if m.h2h and m.alive and m.phase ~= "final" then
		m.forfeitBy = side
		finishGame(m)
	end
	m.humans[side] = nil
	if m.avatarUnit and m.avatarUnit.player == player then
		m.avatarUnit = nil
	end
	m.av[player] = nil
	if m.charConns[player] then
		m.charConns[player]:Disconnect()
		m.charConns[player] = nil
	end
	matches[player] = nil
	local char, hum, root = avatarParts(m, player)
	if root and (not isPlayer(player) or player.Parent) then
		root.Anchored = false
		hum.WalkSpeed = 16
		Npc.Unequip(char)
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") then
				d.CollisionGroup = "Default"
			end
		end
		local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
		char:PivotTo(spawn and (spawn.CFrame + Vector3.new(0, 4, 0)) or CFrame.new(0, 10, 0))
	end
	fire(player, { phase = "ended" })
	if isPlayer(player) then
		MatchService.PlayerExited:Fire(player)
	end
	if next(m.humans) == nil then
		destroyMatch(m)
	elseif m.phase ~= "final" then
		-- (vs CPU only has one human, so this is a head-to-head game that just ended above)
		sendState(m)
	end
end

local function buildTeam(m, cards, infos, primary, secondary, jersey)
	local team = { cards = cards, infos = infos, off = {}, def = {}, ratings = ratingsFor(cards) }
	for _, slot in LineupConfig.Slots do
		local side = slot.side == "Offense" and team.off or team.def
		side[slot.id] = Npc.new(slot.id, slot.side, cards[slot.id], infos[slot.id], primary, secondary, m.field.model, jersey)
		side[slot.id]:Hide(true)
	end
	return team
end

local function near(a, b)
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.45
end

local function jerseyOf(profile)
	local jersey = Jerseys.Get(profile and profile.data.jersey)
	if not profile or not Jerseys.IsUnlocked(jersey.id, profile.data.stats.wins) then
		jersey = Jerseys.Get(Jerseys.Default)
	end
	return jersey
end

-- Colors for side B when they clash with side A: white away jersey (or a darker shade if A is in white)
local function awayColors(aPrimary, bPrimary, bSecondary)
	if near(bPrimary, aPrimary) then
		bPrimary, bSecondary = Color3.fromRGB(236, 237, 242), bPrimary
		if near(bPrimary, aPrimary) then
			bPrimary, bSecondary = bSecondary:Lerp(Color3.new(0, 0, 0), 0.35), Color3.fromRGB(236, 237, 242)
		end
	end
	return bPrimary, bSecondary
end

local function humanTeamInfo(player, primary, secondary)
	local name = isPlayer(player) and player.DisplayName or (player and player.DisplayName) or "PLAYER"
	return { id = nil, city = "", name = name, primary = primary:ToHex(), secondary = secondary:ToHex(), human = true }
end

-- opts: { mode = "cpu" | "ranked" | "friendly", a = Player, b = Player (head-to-head), difficulty }
local function createMatch(opts)
	local a, b = opts.a, opts.b
	local h2h = b ~= nil
	local profileA = isPlayer(a) and PlayerData.Get(a)
	local profileB = isPlayer(b) and PlayerData.Get(b)
	local difficulty = opts.difficulty or MatchConfig.DifficultyById[MatchConfig.DefaultDifficulty]

	local m = {
		mode = opts.mode,
		h2h = h2h,
		ranked = opts.mode == "ranked",
		modeLabel = h2h and (opts.mode == "ranked" and "RANKED" or "FRIENDLY") or difficulty.name,
		humans = { user = a, cpu = b },
		alive = true,
		token = 0,
		score = { user = 0, cpu = 0 },
		drive = 1,
		difficulty = difficulty,
		tally = { user = {}, cpu = {} },
		control = {},
		av = {},
		charConns = {},
	}

	-- squads
	local cardsA, infosA = userSquad(profileA)
	local jerseyA = jerseyOf(profileA)
	local cardsB, infosB, teamB, primaryB, secondaryB, jerseyB
	if h2h then
		if profileB then
			cardsB, infosB = userSquad(profileB)
		else
			local _ -- test bot: a CPU squad around A's rating
			_, cardsB, infosB = cpuSquad(ratingsFor(cardsA).ovr)
		end
		jerseyB = jerseyOf(profileB)
		primaryB, secondaryB = awayColors(jerseyA.primary, jerseyB.primary, jerseyB.secondary)
		if primaryB ~= jerseyB.primary then
			jerseyB = nil -- wearing away colors: no special jersey effects
		end
		teamB = humanTeamInfo(b, primaryB, secondaryB)
	else
		local cpuTeam
		cpuTeam, cardsB, infosB = cpuSquad(math.clamp(ratingsFor(cardsA).ovr + difficulty.ovr, 50, 97))
		primaryB, secondaryB = awayColors(jerseyA.primary, Color3.fromHex(cpuTeam.primary), Color3.fromHex(cpuTeam.secondary))
		teamB = cpuTeam
	end

	local buildStart = os.clock()
	local ok, err = pcall(function()
		m.field = Field.new(Color3.fromRGB(16, 120, 80), primaryB, {
			homeName = h2h and string.upper(a.DisplayName) or "GRIDIRON",
			awayName = teamB.name,
			screenText = "",
			crowd = { jerseyA.secondary, jerseyA.primary, primaryB, secondaryB, Color3.fromRGB(240, 240, 245) },
		})
		m.user = buildTeam(m, cardsA, infosA, jerseyA.primary, jerseyA.secondary, jerseyA)
		m.user.team = h2h and humanTeamInfo(a, jerseyA.primary, jerseyA.secondary) or { name = a.DisplayName, city = "", primary = jerseyA.primary:ToHex(), secondary = jerseyA.secondary:ToHex(), human = true }
		m.user.confetti = jerseyA.secondary
		m.cpu = buildTeam(m, cardsB, infosB, primaryB, secondaryB, jerseyB)
		m.cpu.team = teamB
		m.cpu.confetti = secondaryB
		m.ball, m.ballTrail = makeBall()

		for side, p in m.humans do
			local char = p.Character
			Npc.SetCollisionGroup(char)
			local jersey = side == "user" and jerseyA or jerseyB
			Npc.Equip(char, side == "user" and jerseyA.primary or primaryB, side == "user" and jerseyA.secondary or secondaryB, jersey)
			matches[p] = m
			if isPlayer(p) then
				m.charConns[p] = p.CharacterAdded:Connect(function()
					exitPlayer(m, p) -- died/respawned mid-game
				end)
			end
		end
		log(("%s: %s (%d) vs %s (%d), built in %.1fs"):format(m.modeLabel, teamName(m, "user"), m.user.ratings.ovr, teamName(m, "cpu"), m.cpu.ratings.ovr, os.clock() - buildStart))
		startDrive(m, "user")
	end)
	if not ok then
		warn("[Match] couldn't start:", err)
		for _, p in { a, b } do
			if p then
				matches[p] = nil
			end
		end
		pcall(destroyMatch, m)
		return nil, err
	end
	return m
end

local function ready(player)
	local profile = isPlayer(player) and PlayerData.Get(player)
	local char = player.Character
	return profile and CardDatabase.IsReady() and char and char:FindFirstChild("HumanoidRootPart")
end

function MatchService.InMatch(player)
	return matches[player] ~= nil
end

-- Head-to-head between two players in this server (from H2HService). ranked: rating on the line.
function MatchService.StartH2H(a, b, ranked)
	if matches[a] or matches[b] then
		return false, "A player is already in a game."
	end
	if not ready(a) or not (ready(b) or not isPlayer(b)) then
		return false, "Still loading."
	end
	local m, err = createMatch({ mode = ranked and "ranked" or "friendly", a = a, b = b })
	return m ~= nil, err
end

local function handleAction(player, action, arg)
	local m = matches[player]
	if not m or not m.alive then
		return
	end
	local side = sideOf(m, player)
	if not side then
		return
	end
	local onOffense = side == m.possession
	if action == "call" and onOffense and MatchConfig.PlaysById[arg] then
		makeCall(m, "off", arg)
	elseif action == "defcall" and not onOffense and MatchConfig.DefenseCallsById[arg] then
		makeCall(m, "def", arg)
	elseif action == "snap" and m.phase == "presnap" and (onOffense or not offHuman(m)) then
		snap(m)
	elseif action == "throw" and m.phase == "live" and type(arg) == "number" and onOffense then
		userThrow(m, player, arg)
	elseif action == "switch" and not onOffense and (m.phase == "presnap" or m.phase == "live" or m.phase == "calls") then
		local now = os.clock()
		if now - (m.lastSwitch or 0) < 0.4 then
			return
		end
		m.lastSwitch = now
		if m.phase == "live" then
			-- jump to the AI defender nearest the ball
			local ballPos = m.play.state == "air" and m.play.air.to or carrierPos(m)
			local best, bestD
			for slotId, unit in m.units.Defense do
				if not unit.hidden and ballPos then
					local d = hdist(unit:Position(), ballPos)
					if not bestD or d < bestD then
						best, bestD = slotId, d
					end
				end
			end
			if best then
				switchControl(m, best)
			end
		else
			-- before the snap: cycle through the defenders
			local cycle = MatchConfig.ControlCycle
			local i = table.find(cycle, m.controlSlot) or 0
			switchControl(m, cycle[i % #cycle + 1])
		end
		sendState(m)
	elseif action == "leave" then
		exitPlayer(m, player)
	end
end

-- Studio only: a scripted opponent for testing head-to-head with one player
local function startTestBot(player)
	local desc = Instance.new("HumanoidDescription")
	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	rig.Name = "TestBot"
	rig:PivotTo(CFrame.new(0, 6, 30))
	rig.Parent = workspace
	rig.HumanoidRootPart:SetNetworkOwner(nil)
	local bot = { DisplayName = "TEST BOT", Name = "TestBot", UserId = -1, Character = rig, Parent = workspace, isBot = true }
	local okStart, err = MatchService.StartH2H(player, bot, false)
	if not okStart then
		rig:Destroy()
		return { ok = false, err = err }
	end
	local m = matches[bot]
	m.noRewards = true -- test games don't touch anyone's record
	m.onDestroy = function()
		rig:Destroy()
	end
	task.spawn(function()
		local lastPhase
		while m.alive and m.humans.cpu == bot do
			task.wait(0.25)
			local onOffense = m.possession == "cpu"
			local hum = rig:FindFirstChildOfClass("Humanoid")
			if m.phase == "final" then
				task.wait(2)
				handleAction(bot, "leave")
				break
			elseif m.phase == "calls" then
				if onOffense and not m.call then
					task.wait(1)
					handleAction(bot, "call", cpuPlayCall(m).id)
				elseif not onOffense and not m.defCall then
					task.wait(1)
					handleAction(bot, "defcall", aiDefCall())
				end
			elseif m.phase == "presnap" and onOffense and lastPhase ~= "presnap" then
				task.wait(1.2)
				handleAction(bot, "snap")
			elseif m.phase == "live" and m.play then
				if onOffense and m.play.state == "dropback" then
					if os.clock() - m.play.t0 > 1.8 then
						handleAction(bot, "throw", rng:NextInteger(1, 3))
					end
				elseif onOffense and m.play.state == "carry" and hum then
					hum:MoveTo(rig.HumanoidRootPart.Position + m.field:Downfield() * 20)
				elseif not onOffense and hum then
					local target = m.play.state == "air" and m.play.air.to or carrierPos(m)
					if target then
						hum:MoveTo(target)
					end
				end
			end
			lastPhase = m.phase
		end
	end)
	return { ok = true }
end

function MatchService.Start(remoteFolder)
	remotes = remoteFolder

	remotes.StartMatch.OnServerInvoke = function(player, difficultyId)
		if matches[player] then
			return { ok = false, err = "You're already in a game." }
		end
		if not ready(player) then
			return { ok = false, err = "Still loading, try again in a moment." }
		end
		local difficulty = MatchConfig.DifficultyById[difficultyId] or MatchConfig.DifficultyById[MatchConfig.DefaultDifficulty]
		PlayerData.Update(player, function(data)
			data.difficulty = difficulty.id
		end)
		local m = createMatch({ mode = "cpu", a = player, difficulty = difficulty })
		if not m then
			return { ok = false, err = "Couldn't start the game, please try again." }
		end
		return { ok = true }
	end

	remotes.MatchAction.OnServerEvent:Connect(handleAction)

	if RunService:IsStudio() then
		local dev = remotes:FindFirstChild("DevStartH2H") or Instance.new("RemoteFunction")
		dev.Name = "DevStartH2H"
		dev.Parent = remotes
		dev.OnServerInvoke = startTestBot
	end

	Players.PlayerRemoving:Connect(function(player)
		local m = matches[player]
		if m then
			exitPlayer(m, player)
		end
	end)
end

return MatchService
