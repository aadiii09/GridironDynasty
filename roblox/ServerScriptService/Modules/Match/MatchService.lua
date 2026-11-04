-- MatchService (server): solo 7v7 games vs an AI team. Both sides are played live.
--
-- Your ball: pick a play, snap, throw (keys 1-4) or hand off; after a catch/handoff your avatar
--   takes over the ball carrier.
-- CPU ball: pick a defense (man / deep zone / blitz) and play one defender (Q switches to the
--   defender nearest the ball). The CPU QB reads coverage and throws to the open man; its
--   ball carriers dodge tacklers.
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

local MatchService = {}

local Y = MatchConfig.Yard
local L = MatchConfig.FieldLength()
local HALF_W = MatchConfig.HalfWidth()
local TACKLE_RANGE = 3.2
local USER_PRIMARY = Color3.fromRGB(20, 22, 30)
local USER_SECONDARY = Color3.fromRGB(46, 255, 140)
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

local function fillerCard(pos)
	local attrs = {}
	for _, k in Ratings.All do
		attrs[k] = 40
	end
	return { id = "FILLER", pid = "FILLER", ovr = 40, pos = pos, attrs = attrs }
end

-- Squads ------------------------------------------------------------------------------

local function userSquad(profile)
	local cards, infos = {}, {}
	for _, slot in LineupConfig.Slots do
		local uid = profile.data.lineup[slot.id]
		local entry = uid and profile.data.cards[uid]
		local card = entry and CardDatabase.Get(entry.id)
		cards[slot.id] = card or fillerCard(slot.pos)
		infos[slot.id] = card and CardDatabase.GetPlayerInfo(card.pid) or { last = "Backup", number = 0 }
	end
	return cards, infos
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
	end)
end

-- Avatar ----------------------------------------------------------------------------------

local function avatarParts(m)
	local char = m.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return char, hum, root
end

-- The avatar as a defender "unit" so blocking, tackling and coverage treat it like an NPC.
local function makeAvatarUnit(m, npc)
	local u = {
		isAvatar = true,
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
		local _, _, root = avatarParts(m)
		return root and root.Position or Vector3.zero
	end
	function u:Velocity()
		local _, _, root = avatarParts(m)
		return root and flat(root.AssemblyLinearVelocity) or Vector3.zero
	end
	return u
end

local function nameOf(unit)
	if unit and unit.isAvatar then
		return "YOU"
	end
	return unit and string.upper(unit.info and unit.info.last or "") or ""
end

-- State to client -----------------------------------------------------------------------

local function sendState(m, message, color)
	local userBall = m.possession == "user"
	local targets = {}
	if userBall then
		for i, slotId in MatchConfig.Targets do
			local route = m.call and m.call.routes[slotId]
			local unit = m.units.Offense[slotId]
			table.insert(targets, { key = i, slot = slotId, pos = unit.card.pos, name = nameOf(unit), available = type(route) == "table" })
		end
	end
	local controlled = not userBall and m.units.Defense[m.controlSlot]
	-- field position from YOUR point of view
	local yourYards = userBall and m.los / Y or MatchConfig.FieldYards - m.los / Y
	remotes.MatchState:FireClient(m.player, {
		phase = m.phase,
		possession = m.possession,
		you = m.score.you,
		cpu = m.score.cpu,
		opponent = { id = m.cpu.team.id, city = m.cpu.team.city, name = m.cpu.team.name, primary = m.cpu.team.primary, secondary = m.cpu.team.secondary },
		drive = m.drive,
		drives = MatchConfig.DrivesPerTeam,
		down = m.down,
		toGo = m.firstDown >= L and "GOAL" or tostring(math.max(1, math.ceil((m.firstDown - m.los) / Y - 0.01))),
		spot = MatchConfig.SpotText(yourYards),
		ratings = { you = m.user.ratings, cpu = m.cpu.ratings },
		play = m.call and m.call.id,
		defCall = m.defCall,
		playState = m.play and m.play.state,
		air = (m.play and m.play.state == "air" and m.play.air) and {
			from = m.play.air.from,
			to = m.play.air.to,
			T = m.play.air.T,
			h = m.play.air.h,
			startedAt = m.play.air.startedAt,
		} or nil,
		targets = targets,
		control = controlled and { slot = m.controlSlot, pos = controlled.card.pos, name = nameOf(controlled) } or nil,
		-- for the broadcast camera
		losWorld = m.field:ToWorld(0, m.los, 0),
		downfield = m.field:Downfield(),
		ball = m.ball,
		message = message,
		messageColor = color and color:ToHex(),
		final = m.final,
	})
end

-- Possession + formation --------------------------------------------------------------------

local function setPossession(m, who)
	m.possession = who
	m.field.flipped = who == "cpu"
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

local function placeAvatar(m, cf, speed)
	local char, hum, root = avatarParts(m)
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
	local userBall = m.possession == "user"
	for slotId, unit in m.units.Offense do
		local spot = MatchConfig.Formation.Offense[slotId]
		local cf = m.field:CFrameAt(spot[1] * Y, m.los + spot[2] * Y, 0, true)
		unit.home = cf.Position
		if userBall and slotId == "QB" then
			unit:Hide(true)
			placeAvatar(m, cf, unit.speed)
		else
			unit:Hide(false)
			unit:Place(cf)
			unit:SetTag(("%s %s"):format(unit.card.pos, nameOf(unit)))
		end
	end
	m.avatarUnit = nil
	for slotId, unit in m.units.Defense do
		local spot = MatchConfig.Formation.Defense[slotId]
		local cf = m.field:CFrameAt(spot[1] * Y, m.los + spot[2] * Y, 0, false)
		unit.home = cf.Position
		if not userBall and slotId == m.controlSlot then
			unit:Hide(true)
			placeAvatar(m, cf, unit.speed)
			m.avatarUnit = makeAvatarUnit(m, unit)
		else
			unit:Hide(false)
			unit:Place(cf)
			unit:SetTag(("%s %s"):format(unit.card.pos, nameOf(unit)))
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
	holdBall(m, userBall and "avatar" or m.units.Offense.QB)
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
			unit:SetTag(("[%d] %s %s"):format(i, unit.card.pos, nameOf(unit)), GOLD)
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
	local char = holder == "avatar" and m.player.Character or (holder and holder.model)
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
		local _, _, root = avatarParts(m)
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
		local _, _, root = avatarParts(m)
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
	local char, hum, root = avatarParts(m)
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
	m.avatarSpeed, m.avatarRamp, m.avatarAccelFrom = unit.speed, unit.rampTime, os.clock() - unit.rampTime * 0.5
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
	local char, hum, root = avatarParts(m)
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
	m.avatarUnit = makeAvatarUnit(m, target)
	hum.WalkSpeed = target.speed
	m.avatarSpeed, m.avatarRamp = target.speed, target.rampTime
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
	def.tackleReadyAt = now + (def.isAvatar and 0.8 or 1.4)
	if chance(p) then
		local pos = carrierPos(m)
		local _, fy = m.field:ToField(pos)
		-- the ball carrier goes down
		local carrier = m.play.carrier
		if carrier == "avatar" then
			remotes.MatchState:FireClient(m.player, { event = "fall" })
		elseif carrier then
			carrier:Fall()
		end
		burst(m, pos - Vector3.new(0, 2.5, 0), nil, 14, "dust")
		setPose(def, "dive", 1.2)
		m.play.bigHit = d.POW >= 80 and chance((d.POW - 70) / 60)
		local pFumble = math.clamp(0.008 + (d.POW - c.CAR) * 0.0014 + (m.play.bigHit and 0.015 or 0), 0.003, 0.06)
		if chance(pFumble) then
			endPlay(m, "fumble", fy, def)
		else
			endPlay(m, sack and "sack" or "tackle", fy, def)
		end
	else
		-- beaten: the better the move beat him, the longer he's out of the play
		def.stunUntil = now + math.clamp(0.55 + (move - tak) * 0.01, 0.4, 1)
		log(("tackle broken: %s %d vs TAK %d (%.0f%% to tackle)"):format(moveName, move, tak, p * 100))
		if def.isAvatar then
			sendState(m, moveName == "ESCAPED" and "HE ESCAPED!" or (moveName .. " - MISSED TACKLE!"), RED)
		elseif m.possession == "user" then
			sendState(m, moveName .. "!", GREEN)
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
				d.reactAt = math.max(d.reactAt or 0, now + math.clamp(0.2 + (rr - d.attrs.MCV) * 0.012, 0.05, 0.6))
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
				log(("press: %s jammed %s (PRS %d vs RLS %d)"):format(cb, wrSlot, d.attrs.PRS, wr.attrs.RLS))
			else
				d.stunUntil = now + 0.35
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
	local userBall = m.possession == "user"
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

	if not userBall and play.state == "dropback" and not m.call.run then
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
	if nearest and nearest.isAvatar and sep < 3 then
		-- you got under the throw: your best chance at a pick
		local pInt = math.clamp(0.3 + (cov - 60) * 0.004 + (nearest.attrs.CTH - 50) * 0.004 + (3 - sep) * 0.08 + (rcvDist > 4 and 0.2 or 0), 0.12, 0.75)
		if chance(pInt) then
			endPlay(m, "int", nil, nearest)
			return
		end
	elseif nearest and sep < 3.2 then
		-- ~2-3% normally, ~10% into tight coverage by a good cover man, more on bad throws
		local pInt = math.clamp(0.015 + (cov - 60) * 0.0018 + (nearest.attrs.CTH - 50) * 0.0012 + math.max(0, 2.5 - sep) * 0.04 + (rcvDist > 4 and 0.1 or 0), 0.01, 0.25)
		if chance(pInt) then
			endPlay(m, "int", nil, nearest)
			return
		end
	end
	-- spectacular catchers get to throws other receivers can't
	local reach = 3.6 + (r.SPC - 50) * 0.035
	if rcvDist <= reach then
		local breakup = (nearest and nearest.isAvatar and sep < 3) and 0.15 or 0
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
			if m.possession == "user" then
				swapInto(m, rcv.slot)
				sendState(m, "CAUGHT! RUN!", GREEN)
			else
				giveTo(m, rcv)
				sendState(m, "CAUGHT BY " .. nameOf(rcv) .. " - TACKLE HIM!", RED)
			end
			return
		end
		endPlay(m, "drop", nil, nearest, rcv)
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
	local _, myHum = avatarParts(m)
	if myHum and m.avatarSpeed then
		local speed = m.avatarSpeed * MatchConfig.Ramp(m.avatarRamp or 0.6, now - (m.avatarAccelFrom or 0))
		local u = m.avatarUnit
		if u then
			if now < u.stunUntil then
				speed *= 0.3
				m.avatarAccelFrom = u.stunUntil
			elseif now < u.engagedUntil then
				speed *= (1 - u.engageFactor)
			end
		end
		myHum.WalkSpeed = speed
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
	if m.possession == "user" and play.state == "dropback" and fy > m.los + Y then
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
			if not blocked and now >= d.stunUntil and now >= (d.tackleReadyAt or 0) and hdist(d:Position(), pos) < TACKLE_RANGE then
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
	local _, hum = avatarParts(m)
	if hum then
		hum.WalkSpeed = 0
	end

	local userBall = m.possession == "user"
	local yards = spotY and (spotY - m.los) / Y or 0
	local msg, color, driveOver = nil, Color3.new(1, 1, 1), false
	local good, bad = GREEN, RED
	if not userBall then
		good, bad = RED, GREEN -- from your point of view, CPU gains are bad
	end

	if result == "td" then
		if userBall then
			m.score.you += MatchConfig.TouchdownPoints
			msg = "TOUCHDOWN!"
		else
			m.score.cpu += MatchConfig.TouchdownPoints
			msg = string.upper(m.cpu.team.name) .. " TOUCHDOWN"
		end
		color, driveOver = good, true
		local ez = MatchConfig.EndZoneYards * Y
		for _, x in { -20, 0, 20 } do
			burst(m, m.field:ToWorld(x, L + ez / 2, 1), userBall and USER_SECONDARY or Color3.fromHex(m.cpu.team.secondary), 70, "confetti")
		end
	elseif result == "fumble" then
		msg = userBall and ("FUMBLE! " .. nameOf(defender) .. " forced it - turnover") or ("FUMBLE! Forced by " .. nameOf(defender) .. "!")
		color, driveOver = bad, true
	elseif result == "int" then
		msg = (userBall and "INTERCEPTED by " or "INTERCEPTION by ") .. nameOf(defender) .. (userBall and "" or "!")
		color, driveOver = bad, true
	elseif result == "incomplete" or result == "drop" then
		if result == "drop" then
			msg = "DROPPED by " .. nameOf(receiver)
			if defender and defender.isAvatar then
				msg = "PASS BROKEN UP by YOU!"
			end
		else
			msg = "INCOMPLETE"
		end
		color = userBall and Color3.fromRGB(255, 196, 46) or GREEN
		spotY = m.los
	elseif spotY and spotY < 0 then
		if userBall then
			m.score.cpu += MatchConfig.SafetyPoints
		else
			m.score.you += MatchConfig.SafetyPoints
		end
		msg, color, driveOver = "SAFETY", bad, true
	else
		local by = nameOf(defender)
		local verb = result == "sack" and ("SACKED by " .. by) or result == "out" and "Out of bounds" or result == "timeout" and "Whistle" or ((play.bigHit and "BIG HIT by " or "Tackled by ") .. by)
		msg = ("%s  (%+d yds)"):format(verb, math.floor(yards + (yards >= 0 and 0.5 or -0.5)))
		if userBall then
			color = yards >= 0 and Color3.new(1, 1, 1) or Color3.fromRGB(255, 120, 90)
		else
			color = yards <= 2 and GREEN or Color3.new(1, 1, 1)
		end
	end

	if not driveOver then
		m.los = math.clamp(spotY or m.los, Y, L - Y)
		if m.los >= m.firstDown then
			m.down = 1
			m.firstDown = math.min(m.los + MatchConfig.FirstDownYards * Y, L)
			msg ..= "  -  FIRST DOWN"
		else
			m.down += 1
			if m.down > 4 then
				msg ..= userBall and "  -  TURNOVER ON DOWNS" or "  -  STOPPED ON DOWNS!"
				if not userBall then
					color = GREEN
				end
				driveOver = true
			end
		end
	end

	m.phase = "result"
	m.field:SetScreen(("YOU %d  -  %d %s"):format(m.score.you, m.score.cpu, string.upper(m.cpu.team.name)))
	log(("%s ball, %s/%s: %s after %.1fs -> %s"):format(m.possession, m.call and m.call.id or "?", m.defCall or "?", result, os.clock() - (play.t0 or os.clock()), msg))
	sendState(m, msg, color)
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
	local userBall = m.possession == "user"
	play.state = "dropback"
	play.t0 = os.clock()
	play.nextThink = 0
	play.routes = compileRoutes(m)
	play.carrier = userBall and "avatar" or m.units.Offense.QB
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
	local _, hum, root = avatarParts(m)
	if root then
		root.Anchored = false
		hum.WalkSpeed = userBall and m.units.Offense.QB.speed or (m.avatarUnit and m.avatarUnit.speed or 16)
		local mine = userBall and m.units.Offense.QB or m.avatarUnit
		m.avatarSpeed = mine and mine.speed or 16
		m.avatarRamp = mine and mine.rampTime or 0.6
		m.avatarAccelFrom = play.t0
	end
	pressAtLine(m, play.t0)
	if m.call.run then
		local token = m.token
		task.delay(0.45, function()
			if m.token == token and m.play == play and play.state == "dropback" then
				play.handoffAt = os.clock()
				if userBall then
					swapInto(m, "RB")
					sendState(m, "HANDOFF - RUN!", GREEN)
				else
					giveTo(m, m.units.Offense.RB)
					sendState(m, "IT'S A RUN!", GOLD)
				end
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
	-- lead the receiver along his actual route (so throws hit him after his cut)
	local function along(t)
		local pos = flat(rcv:Position())
		local budget = rcv.speed * t
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
	if m.possession ~= "user" then
		setPose(m.units.Offense.QB, "throw", 0.6)
	end
	releaseBall(m)
	setBallVisible(m, false)
	m.ball.CFrame = CFrame.new(play.air.from)
	play.carrier = nil
	play.state = "air"
	sendState(m)
end

local function userThrow(m, key)
	local play = m.play
	local slotId = MatchConfig.Targets[key]
	if m.possession ~= "user" or not play or play.state ~= "dropback" or m.call.run or not slotId or not play.routes[slotId] then
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

function nextPlay(m)
	m.token += 1
	m.play = nil
	m.call = nil
	m.defCall = nil
	m.phase = m.possession == "user" and "playcall" or "defcall"
	lineUp(m)
	sendState(m)
end

function startDrive(m, who)
	setPossession(m, who)
	m.los = MatchConfig.StartYard * Y
	m.down = 1
	m.firstDown = m.los + MatchConfig.FirstDownYards * Y
	m.controlSlot = m.controlSlot or MatchConfig.DefaultControl
	nextPlay(m)
	if who == "user" then
		sendState(m, ("YOUR BALL  -  DRIVE %d OF %d"):format(m.drive, MatchConfig.DrivesPerTeam), GREEN)
	else
		sendState(m, string.upper(m.cpu.team.name) .. " BALL  -  DEFENSE!", GOLD)
	end
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

function finishGame(m)
	m.token += 1
	m.phase = "final"
	local you, cpu = m.score.you, m.score.cpu
	local result = you > cpu and "Win" or you < cpu and "Loss" or "Tie"
	local vip = StoreService.IsVIP(m.player)
	local coins = MatchConfig.Rewards[result] * (vip and 2 or 1)
	if PlayerData.Get(m.player) then
		PlayerData.AddCoins(m.player, coins)
		PlayerData.Update(m.player, function(data)
			if result == "Win" then
				data.stats.wins += 1
			elseif result == "Loss" then
				data.stats.losses += 1
			else
				data.stats.ties = (data.stats.ties or 0) + 1
			end
		end)
		task.spawn(PlayerData.SaveNow, m.player)
	end
	m.final = { result = result, coins = coins, vip = vip }
	log(m.player.Name, result, you, cpu)
	sendState(m, result == "Win" and "YOU WIN!" or result == "Loss" and "YOU LOSE" or "TIE GAME", result == "Win" and GREEN or Color3.fromRGB(255, 196, 46))
end

-- Lifecycle -------------------------------------------------------------------------------

local function cleanup(m)
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
	if m.charConn then
		m.charConn:Disconnect()
	end
	matches[m.player] = nil
	local char, hum, root = avatarParts(m)
	if root and m.player.Parent then
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
	if m.player.Parent then
		remotes.MatchState:FireClient(m.player, { phase = "ended" })
	end
end

local function buildTeam(m, cards, infos, primary, secondary)
	local team = { cards = cards, infos = infos, off = {}, def = {}, ratings = ratingsFor(cards) }
	for _, slot in LineupConfig.Slots do
		local side = slot.side == "Offense" and team.off or team.def
		side[slot.id] = Npc.new(slot.id, slot.side, cards[slot.id], infos[slot.id], primary, secondary, m.field.model)
		side[slot.id]:Hide(true)
	end
	return team
end

function MatchService.Start(remoteFolder)
	remotes = remoteFolder

	remotes.StartMatch.OnServerInvoke = function(player)
		if matches[player] then
			return { ok = false, err = "You're already in a game." }
		end
		local profile = PlayerData.Get(player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not profile or not CardDatabase.IsReady() or not root then
			return { ok = false, err = "Still loading, try again in a moment." }
		end

		local userCards, userInfos = userSquad(profile)
		local userOvr = ratingsFor(userCards).ovr
		local cpuTeam, cpuCards, cpuInfos = cpuSquad(userOvr)
		local cpuPrimary = Color3.fromHex(cpuTeam.primary)
		local cpuSecondary = Color3.fromHex(cpuTeam.secondary)

		local m = {
			player = player,
			alive = true,
			token = 0,
			score = { you = 0, cpu = 0 },
			drive = 1,
		}
		matches[player] = m
		local buildStart = os.clock()
		local ok, err = pcall(function()
			m.field = Field.new(Color3.fromRGB(16, 120, 80), cpuPrimary, {
				homeName = "GRIDIRON",
				awayName = cpuTeam.name,
				screenText = ("YOU 0  -  0 %s"):format(string.upper(cpuTeam.name)),
				crowd = { USER_SECONDARY, USER_PRIMARY, cpuPrimary, cpuSecondary, Color3.fromRGB(240, 240, 245) },
			})
			m.user = buildTeam(m, userCards, userInfos, USER_PRIMARY, USER_SECONDARY)
			m.cpu = buildTeam(m, cpuCards, cpuInfos, cpuPrimary, cpuSecondary)
			m.cpu.team = cpuTeam
			m.ball, m.ballTrail = makeBall()

			Npc.SetCollisionGroup(char)
			Npc.Equip(char, USER_PRIMARY, USER_SECONDARY)
			m.charConn = player.CharacterAdded:Connect(function()
				cleanup(m) -- died/respawned mid-game: end it
			end)

			log(player.Name, "vs", cpuTeam.city, cpuTeam.name, "you", m.user.ratings.ovr, "cpu", m.cpu.ratings.ovr, ("built in %.1fs"):format(os.clock() - buildStart))
			startDrive(m, "user")
		end)
		if not ok then
			warn("[Match] couldn't start:", err)
			pcall(cleanup, m)
			matches[player] = nil
			return { ok = false, err = "Couldn't start the game, please try again." }
		end
		return { ok = true }
	end

	remotes.MatchAction.OnServerEvent:Connect(function(player, action, arg)
		local m = matches[player]
		if not m or not m.alive then
			return
		end
		if action == "call" and m.phase == "playcall" and MatchConfig.PlaysById[arg] then
			m.call = MatchConfig.PlaysById[arg]
			m.defCall = weighted({ { "man", 60 }, { "zone", 25 }, { "blitz", 15 } })
			m.play = { state = "presnap" }
			m.phase = "presnap"
			tagTargets(m)
			sendState(m)
		elseif action == "defcall" and m.phase == "defcall" and MatchConfig.DefenseCallsById[arg] then
			m.defCall = arg
			m.call = cpuPlayCall(m)
			m.play = { state = "presnap" }
			m.phase = "presnap"
			sendState(m)
		elseif action == "snap" and m.phase == "presnap" then
			snap(m)
		elseif action == "throw" and m.phase == "live" and type(arg) == "number" then
			userThrow(m, arg)
		elseif action == "switch" and m.possession == "cpu" and (m.phase == "presnap" or m.phase == "live" or m.phase == "defcall") then
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
			cleanup(m)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local m = matches[player]
		if m then
			cleanup(m)
		end
	end)
end

return MatchService
