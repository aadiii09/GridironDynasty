-- MatchService (server): solo 7v7 games vs an AI team.
--
-- You play offense live: pick a play, snap, then throw (keys 1-4) or hand off. After a catch
-- or handoff your avatar takes over the ball carrier. Every NPC moves and plays by its card:
-- SPD = speed, CTH = catching, COV = coverage reaction, PRS vs BLK = pass rush vs blocking,
-- TAK vs CAR/AGI = tackling vs breaking tackles, THP/THA = throw speed and accuracy.
-- The CPU's own possessions are simulated from team ratings (playable defense comes later).

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

local MatchService = {}

local Y = MatchConfig.Yard
local L = MatchConfig.FieldLength()
local HALF_W = MatchConfig.HalfWidth()
local TACKLE_RANGE = 3.2
local USER_PRIMARY = Color3.fromRGB(20, 22, 30)
local USER_SECONDARY = Color3.fromRGB(46, 255, 140)

local remotes
local matches = {} -- [Player] = match
local rng = Random.new()

local function log(...)
	print("[Match]", ...)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function hdist(a, b)
	return flat(a - b).Magnitude
end

local function fillerCard(pos)
	local attrs = {}
	for _, k in { "SPD", "AGI", "STR", "CTH", "CAR", "THP", "THA", "BLK", "TAK", "COV", "PRS" } do
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
				-- prefer this team's players, then closeness to the wanted rating
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

-- State to client ------------------------------------------------------------------------

local function sendState(m, message, color)
	local targets = {}
	for i, slotId in MatchConfig.Targets do
		local route = m.call and m.call.routes[slotId]
		local unit = m.units.Offense[slotId]
		table.insert(targets, {
			key = i,
			slot = slotId,
			pos = unit.card.pos,
			name = string.upper(m.userInfos[slotId].last or ""),
			available = type(route) == "table",
		})
	end
	remotes.MatchState:FireClient(m.player, {
		phase = m.phase,
		you = m.score.you,
		cpu = m.score.cpu,
		opponent = { id = m.cpuTeam.id, city = m.cpuTeam.city, name = m.cpuTeam.name, primary = m.cpuTeam.primary, secondary = m.cpuTeam.secondary },
		drive = m.drive,
		drives = MatchConfig.DrivesPerTeam,
		down = m.down,
		toGo = m.firstDown >= L and "GOAL" or tostring(math.max(1, math.ceil((m.firstDown - m.los) / Y - 0.01))),
		spot = MatchConfig.SpotText(m.los / Y),
		ratings = { you = m.userRatings, cpu = m.cpuRatings },
		play = m.call and m.call.id,
		playState = m.play and m.play.state,
		targets = targets,
		message = message,
		messageColor = color and color:ToHex(),
		final = m.final,
	})
end

-- Avatar helpers ---------------------------------------------------------------------------

local function avatarParts(m)
	local char = m.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return char, hum, root
end

local function placeAvatar(m, cf, anchored)
	local char, hum, root = avatarParts(m)
	if not root then
		return
	end
	root.Anchored = false
	char:PivotTo(cf + Vector3.new(0, 3, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = anchored
	hum.WalkSpeed = m.avatarSpeed or 16
end

-- Formation ---------------------------------------------------------------------------------

local function lineUp(m)
	for slotId, unit in m.units.Offense do
		local spot = MatchConfig.Formation.Offense[slotId]
		local cf = m.field:CFrameAt(spot[1] * Y, m.los + spot[2] * Y, 0, true)
		unit.home = cf.Position
		if slotId == "QB" then
			unit:Hide(true)
			m.avatarSpeed = unit.speed
			placeAvatar(m, cf, true)
		else
			unit:Hide(false)
			unit:Place(cf)
			unit:SetTag(("%s %s"):format(unit.card.pos, string.upper(m.userInfos[slotId].last or "")))
		end
	end
	for slotId, unit in m.units.Defense do
		local spot = MatchConfig.Formation.Defense[slotId]
		unit:Hide(false)
		unit:Place(m.field:CFrameAt(spot[1] * Y, m.los + spot[2] * Y, 0, false))
	end
	m.field:SetMarkers(m.los, m.firstDown)
	m.ball.Parent = m.field.model
end

local function tagTargets(m)
	for i, slotId in MatchConfig.Targets do
		local unit = m.units.Offense[slotId]
		local route = m.call and m.call.routes[slotId]
		if type(route) == "table" and not m.call.run then
			unit:SetTag(("[%d] %s %s"):format(i, unit.card.pos, string.upper(m.userInfos[slotId].last or "")), Color3.fromRGB(255, 214, 40))
		end
	end
end

-- Play engine --------------------------------------------------------------------------------

local endPlay -- forward

local function carrierPos(m)
	local _, _, root = avatarParts(m)
	return root and root.Position
end

local function carrierVel(m)
	local _, _, root = avatarParts(m)
	return root and flat(root.AssemblyLinearVelocity) or Vector3.zero
end

local function compileRoutes(m)
	local routes = {}
	for slotId, route in m.call.routes do
		if type(route) == "table" then
			local unit = m.units.Offense[slotId]
			local x0, y0 = m.field:ToField(unit.home)
			local out = x0 >= 0 and 1 or -1
			local points = {}
			for _, wp in route do
				local x = math.clamp(x0 + out * wp[1] * Y, -HALF_W + 3, HALF_W - 3)
				table.insert(points, m.field:ToWorld(x, y0 + wp[2] * Y, 0))
			end
			routes[slotId] = { points = points, index = 1 }
		end
	end
	return routes
end

-- Put the user's avatar in place of an offensive NPC (catch or handoff).
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
	m.play.carrierSlot = slotId
	m.play.carrierCard = unit.card
	hum.WalkSpeed = unit.speed
	m.play.state = "carry"
end

local function attemptTackle(m, def, now)
	local carrier = m.play.carrierCard.attrs
	local elusive = math.max(carrier.CAR or 40, carrier.AGI or 40)
	local p = math.clamp(0.6 + ((def.attrs.TAK or 50) - elusive) * 0.012, 0.25, 0.93)
	def.tackleReadyAt = now + 1.4
	if rng:NextNumber() < p then
		local _, fy = m.field:ToField(carrierPos(m))
		endPlay(m, m.play.state == "dropback" and "sack" or "tackle", fy, def)
	else
		def.stunUntil = now + 1.1
		sendState(m, "BROKEN TACKLE!", Color3.fromRGB(46, 255, 140))
	end
end

local function think(m, now)
	local play = m.play
	local qbPos = carrierPos(m)
	if not qbPos then
		return
	end
	local cVel = carrierVel(m)
	local off, def = m.units.Offense, m.units.Defense

	-- offense (your NPCs) -------------------------------------------------------------
	for slotId, unit in off do
		if not unit.hidden then
			local route = play.routes[slotId]
			if play.state ~= "carry" and route then
				local target = route.points[route.index]
				if hdist(unit:Position(), target) < 2.5 and route.index < #route.points then
					route.index += 1
					target = route.points[route.index]
				end
				unit:MoveTo(target, now)
			else
				-- block: pass pro on the assigned rusher, otherwise the nearest threat to the ball
				local victim = MatchConfig.BlockAssignments[slotId] and def[MatchConfig.BlockAssignments[slotId]]
				if play.state == "carry" or not victim then
					local best, bestD = nil, 30
					for _, d in def do
						local dd = hdist(d:Position(), unit:Position())
						if dd < bestD and hdist(d:Position(), qbPos) < 35 then
							best, bestD = d, dd
						end
					end
					victim = best
				end
				if victim then
					local between = victim:Position() + flat(qbPos - victim:Position()).Unit * 1.5
					unit:MoveTo(between, now)
					if hdist(unit:Position(), victim:Position()) < 4.5 then
						-- engaged: the defender keeps only a fraction of his speed.
						-- Pass rush: PRS vs BLK (even matchup = ~18% speed, ~5s before a sack).
						-- Run/after catch: TAK vs BLK.
						local blk = unit.attrs.BLK or 40
						local keep
						if play.state == "carry" then
							keep = math.clamp(0.3 + ((victim.attrs.TAK or 50) - blk) * 0.008, 0.1, 0.6)
						else
							keep = math.clamp(0.18 + ((victim.attrs.PRS or 50) - blk) * 0.008, 0.05, 0.45)
						end
						victim.engagedUntil = now + 0.3
						victim.engageFactor = 1 - keep
					end
				else
					unit:MoveTo(qbPos + Vector3.new(0, 0, -12), now)
				end
			end
		end
	end

	-- defense (CPU) ----------------------------------------------------------------------
	local deepestY, deepestX = m.los, 0
	for slotId, route in play.routes do
		local x, y = m.field:ToField(off[slotId]:Position())
		if y > deepestY then
			deepestY, deepestX = y, x
		end
	end

	for slotId, unit in def do
		local target
		local pursue = play.state == "carry"
		local reading = pursue and play.handoffAt and now - play.handoffAt < 0.6 and slotId ~= "DL1" and slotId ~= "DL2"
		if reading then
			target = nil -- linebackers/DBs read the run for a moment before they chase
		elseif play.state == "air" and hdist(unit:Position(), play.air.to) < 40 then
			target = play.air.to
		elseif pursue then
			local lead = math.clamp(hdist(unit:Position(), qbPos) / unit.speed, 0, 0.8)
			target = qbPos + cVel * lead
		elseif slotId == "DL1" or slotId == "DL2" then
			target = qbPos
		elseif slotId == "S" then
			target = m.field:ToWorld(deepestX * 0.5, math.max(m.los + 12 * Y, deepestY + 5 * Y), 0)
		else
			local mark = off[MatchConfig.Coverage[slotId]]
			if mark and not mark.hidden and play.routes[mark.slot] then
				local cov = unit.attrs.COV or 50
				if now >= (unit.reactAt or 0) then
					unit.coverPoint = mark:Position() + mark:Velocity() * 0.35 + Vector3.new(0, 0, -1.5)
					unit.reactAt = now + math.clamp(0.5 - (cov - 50) * 0.007, 0.12, 0.5)
				end
				target = unit.coverPoint
			else
				-- man is blocking: spy the QB a few yards past the line
				local qx = m.field:ToField(qbPos)
				target = m.field:ToWorld(qx, m.los + 4 * Y, 0)
			end
		end
		unit:MoveTo(target or unit:Position(), now)
	end
end

local function updateBall(m, now)
	local play = m.play
	if play.state == "air" then
		local a = play.air
		local s = math.clamp((now - a.t0) / a.T, 0, 1)
		local p = a.from:Lerp(a.to, s) + Vector3.new(0, 4 * a.h * s * (1 - s), 0)
		m.ball.CFrame = CFrame.new(p)
		return s >= 1
	end
	local char = m.player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("HumanoidRootPart"))
	if hand then
		m.ball.CFrame = hand.CFrame * CFrame.new(0, -0.6, -0.3)
	end
	return false
end

local function resolveCatch(m)
	local a = m.play.air
	local rcv = a.target
	local rcvDist = hdist(rcv:Position(), a.to)
	local nearest, sep = nil, math.huge
	for _, d in m.units.Defense do
		local dd = hdist(d:Position(), a.to)
		if dd < sep then
			nearest, sep = d, dd
		end
	end
	if nearest and sep < 3.2 then
		-- ~2-3% normally, ~10% into tight coverage by a good cover man, more on bad throws
		local pInt = math.clamp(0.02 + ((nearest.attrs.COV or 50) - 60) * 0.002 + math.max(0, 2.5 - sep) * 0.04 + (rcvDist > 4 and 0.1 or 0), 0.01, 0.25)
		if rng:NextNumber() < pInt then
			endPlay(m, "int", nil, nearest)
			return
		end
	end
	if rcvDist <= 4.5 then
		local cth = rcv.attrs.CTH or 50
		local pCatch = math.clamp(0.55 + cth * 0.004 - math.max(0, 3 - sep) * 0.08 - math.max(0, rcvDist - 1.5) * 0.05, 0.05, 0.97)
		log(("catch check: CTH %d, ball %.1f studs off, nearest defender %.1f, chance %.0f%%"):format(cth, rcvDist, sep, pCatch * 100))
		if rng:NextNumber() < pCatch then
			swapInto(m, rcv.slot)
			m.ball.CFrame = CFrame.new(rcv:Position())
			sendState(m, "CAUGHT! RUN!", Color3.fromRGB(46, 255, 140))
			return
		end
		endPlay(m, "drop", nil, nil, rcv)
		return
	end
	log(("off target: ball %.1f studs from receiver"):format(rcvDist))
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

	local pos = carrierPos(m)
	if not pos then
		endPlay(m, "timeout", m.los)
		return
	end
	local fx, fy = m.field:ToField(pos)

	if play.state == "dropback" or play.state == "carry" or play.state == "air" then
		if math.abs(fx) > HALF_W and play.state ~= "air" then
			endPlay(m, "out", fy)
			return
		end
		if play.state == "carry" and fy >= L then
			endPlay(m, "td", fy)
			return
		end
		if play.state == "dropback" and fy > m.los + Y then
			play.state = "carry" -- QB scramble: no throwing past the line
			play.carrierCard = m.units.Offense.QB.card
			sendState(m, "SCRAMBLE!", Color3.fromRGB(255, 214, 40))
		end
		if now - play.t0 > MatchConfig.MaxPlaySeconds then
			endPlay(m, "timeout", play.state == "air" and m.los or fy)
			return
		end
	end

	-- tackles (and sacks) on the ball carrier
	if play.state == "dropback" or play.state == "carry" then
		for _, d in m.units.Defense do
			-- a defender who is locked up with a blocker can't make the tackle
			local blocked = now < d.engagedUntil
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

local startDrive, nextPlay, cpuDrive, finishGame -- forward

function endPlay(m, result, spotY, defender, receiver)
	local play = m.play
	if not play or play.state == "dead" then
		return
	end
	play.state = "dead"
	if play.conn then
		play.conn:Disconnect()
	end
	for _, unit in m.units.Offense do
		unit.humanoid:Move(Vector3.zero)
	end
	for _, unit in m.units.Defense do
		unit.humanoid:Move(Vector3.zero)
	end
	local _, hum = avatarParts(m)
	if hum then
		hum.WalkSpeed = 0
	end

	local yards = spotY and (spotY - m.los) / Y or 0
	local msg, color, driveOver = nil, Color3.new(1, 1, 1), false
	local defName = defender and string.upper(m.cpuInfos[defender.slot].last or "") or ""

	if result == "td" then
		m.score.you += MatchConfig.TouchdownPoints
		msg, color, driveOver = "TOUCHDOWN!", Color3.fromRGB(46, 255, 140), true
	elseif result == "int" then
		msg, color, driveOver = "INTERCEPTED by " .. defName, Color3.fromRGB(255, 90, 90), true
	elseif result == "incomplete" or result == "drop" then
		msg = result == "drop" and ("DROPPED by " .. string.upper(m.userInfos[receiver.slot].last or "")) or "INCOMPLETE"
		color = Color3.fromRGB(255, 196, 46)
		spotY = m.los
	elseif spotY and spotY < 0 then
		m.score.cpu += MatchConfig.SafetyPoints
		msg, color, driveOver = "SAFETY", Color3.fromRGB(255, 90, 90), true
	else
		local verb = result == "sack" and ("SACKED by " .. defName) or result == "out" and "Out of bounds" or result == "timeout" and "Whistle" or ("Tackled by " .. defName)
		msg = ("%s  (%+d yds)"):format(verb, math.floor(yards + (yards >= 0 and 0.5 or -0.5)))
		color = yards >= 0 and Color3.new(1, 1, 1) or Color3.fromRGB(255, 120, 90)
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
				msg ..= "  -  TURNOVER ON DOWNS"
				driveOver = true
			end
		end
	end

	m.phase = "result"
	log(("play %s: %s after %.1fs -> %s"):format(m.call and m.call.id or "?", result, os.clock() - (play.t0 or os.clock()), msg))
	sendState(m, msg, color)
	local token = m.token
	task.delay(2.6, function()
		if m.token ~= token or not m.alive then
			return
		end
		if driveOver then
			cpuDrive(m)
		else
			nextPlay(m)
		end
	end)
end

local function snap(m)
	local play = m.play
	play.state = "dropback"
	play.t0 = os.clock()
	play.nextThink = 0
	play.routes = compileRoutes(m)
	play.carrierCard = m.units.Offense.QB.card
	m.phase = "live"
	local _, hum, root = avatarParts(m)
	if root then
		root.Anchored = false
		hum.WalkSpeed = m.units.Offense.QB.speed
	end
	if m.call.run then
		local token = m.token
		task.delay(0.45, function()
			if m.token == token and m.play == play and play.state == "dropback" then
				play.handoffAt = os.clock()
				swapInto(m, "RB")
				sendState(m, "HANDOFF - RUN!", Color3.fromRGB(46, 255, 140))
			end
		end)
	end
	play.conn = RunService.Heartbeat:Connect(function()
		step(m)
	end)
	sendState(m)
end

local function throw(m, key)
	local play = m.play
	local slotId = MatchConfig.Targets[key]
	if not play or play.state ~= "dropback" or m.call.run or not slotId or not play.routes[slotId] then
		return
	end
	local rcv = m.units.Offense[slotId]
	local from = carrierPos(m)
	if not from or rcv.hidden then
		return
	end
	local qb = m.units.Offense.QB.attrs
	local ballSpeed = 45 + (qb.THP or 50) * 0.35
	-- lead the receiver along his actual route (so throws hit him after his cut)
	local route = play.routes[slotId]
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
		return pos + Vector3.new(0, rcv:Position().Y, 0) -- route finished: he sits there
	end
	local predicted = rcv:Position()
	local T = 0.1
	for _ = 1, 4 do
		T = hdist(predicted, from) / ballSpeed + 0.05
		predicted = along(T)
	end
	local dist = hdist(predicted, from)
	local errMag = (100 - (qb.THA or 50)) * 0.035 * math.clamp(dist / 45, 0.5, 2.5) * rng:NextNumber(0.2, 1)
	local angle = rng:NextNumber(0, math.pi * 2)
	local to = predicted + Vector3.new(math.cos(angle) * errMag, 0, math.sin(angle) * errMag)
	play.air = {
		from = from + Vector3.new(0, 1.5, 0),
		to = Vector3.new(to.X, from.Y, to.Z),
		T = T,
		t0 = os.clock(),
		h = math.clamp(dist * 0.18, 3, 22),
		target = rcv,
	}
	play.state = "air"
	sendState(m)
end

function nextPlay(m)
	m.token += 1
	m.play = nil
	m.call = nil
	m.phase = "playcall"
	lineUp(m)
	sendState(m)
end

function startDrive(m)
	m.los = MatchConfig.StartYard * Y
	m.down = 1
	m.firstDown = m.los + MatchConfig.FirstDownYards * Y
	nextPlay(m)
	sendState(m, ("DRIVE %d OF %d"):format(m.drive, MatchConfig.DrivesPerTeam), Color3.fromRGB(46, 255, 140))
end

function cpuDrive(m)
	m.token += 1
	m.phase = "cpu"
	local cpuName = string.upper(m.cpuTeam.name)
	local p = math.clamp(0.4 + (m.cpuRatings.off - m.userRatings.def) * 0.025, 0.1, 0.8)
	local roll = rng:NextNumber()
	local msg, color
	if roll < p then
		m.score.cpu += MatchConfig.TouchdownPoints
		msg, color = cpuName .. " DRIVE: TOUCHDOWN", Color3.fromRGB(255, 90, 90)
	elseif roll < p + (1 - p) * 0.2 then
		msg, color = "YOUR DEFENSE INTERCEPTS " .. cpuName .. "!", Color3.fromRGB(46, 255, 140)
	elseif roll < p + (1 - p) * 0.6 then
		msg, color = "YOUR DEFENSE FORCES A PUNT", Color3.fromRGB(46, 255, 140)
	else
		msg, color = "STOPPED ON 4TH DOWN!", Color3.fromRGB(46, 255, 140)
	end
	sendState(m, msg, color)
	local token = m.token
	task.delay(3, function()
		if m.token ~= token or not m.alive then
			return
		end
		m.drive += 1
		if m.drive > MatchConfig.DrivesPerTeam then
			finishGame(m)
		else
			startDrive(m)
		end
	end)
end

function finishGame(m)
	m.token += 1
	m.phase = "final"
	local you, cpu = m.score.you, m.score.cpu
	local result = you > cpu and "Win" or you < cpu and "Loss" or "Tie"
	local coins = MatchConfig.Rewards[result]
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
	m.final = { result = result, coins = coins }
	log(m.player.Name, result, you, cpu)
	sendState(m, result == "Win" and "YOU WIN!" or result == "Loss" and "YOU LOSE" or "TIE GAME", result == "Win" and Color3.fromRGB(46, 255, 140) or Color3.fromRGB(255, 196, 46))
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
	for _, side in m.units do
		for _, unit in side do
			unit:Destroy()
		end
	end
	m.field:Destroy()
	if m.charConn then
		m.charConn:Disconnect()
	end
	matches[m.player] = nil
	local char, hum, root = avatarParts(m)
	if root and m.player.Parent then
		root.Anchored = false
		hum.WalkSpeed = 16
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

function MatchService.Start(remoteFolder)
	remotes = remoteFolder

	remotes.StartMatch.OnServerInvoke = function(player)
		if matches[player] then
			return { ok = false, err = "You're already in a game." }
		end
		local profile = PlayerData.Get(player)
		local char, _, root = player.Character, nil, player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not profile or not CardDatabase.IsReady() or not root then
			return { ok = false, err = "Still loading, try again in a moment." }
		end

		local userCards, userInfos = userSquad(profile)
		local userRatings = ratingsFor(userCards)
		local cpuTeam, cpuCards, cpuInfos = cpuSquad(userRatings.ovr)
		local cpuPrimary = Color3.fromHex(cpuTeam.primary)
		local cpuSecondary = Color3.fromHex(cpuTeam.secondary)

		local m = {
			player = player,
			alive = true,
			token = 0,
			score = { you = 0, cpu = 0 },
			drive = 1,
			userInfos = userInfos,
			cpuInfos = cpuInfos,
			cpuTeam = cpuTeam,
			userRatings = userRatings,
			cpuRatings = ratingsFor(cpuCards),
			units = { Offense = {}, Defense = {} },
		}
		matches[player] = m
		m.field = Field.new(USER_SECONDARY, cpuPrimary)

		for _, slot in LineupConfig.Slots do
			if slot.side == "Offense" then
				m.units.Offense[slot.id] = Npc.new(slot.id, "Offense", userCards[slot.id], userInfos[slot.id], USER_PRIMARY, USER_SECONDARY, m.field.model)
			else
				m.units.Defense[slot.id] = Npc.new(slot.id, "Defense", cpuCards[slot.id], cpuInfos[slot.id], cpuPrimary, cpuSecondary, m.field.model)
			end
		end

		local ball = Instance.new("Part")
		ball.Name = "Football"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(1.1, 1.1, 1.1)
		ball.Color = Color3.fromRGB(122, 66, 36)
		ball.Material = Enum.Material.Leather
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		m.ball = ball

		Npc.SetCollisionGroup(char)
		m.charConn = player.CharacterAdded:Connect(function()
			cleanup(m) -- died/respawned mid-game: end it
		end)

		log(player.Name, "vs", cpuTeam.city, cpuTeam.name, "you", userRatings.ovr, "cpu", m.cpuRatings.ovr)
		startDrive(m)
		return { ok = true }
	end

	remotes.MatchAction.OnServerEvent:Connect(function(player, action, arg)
		local m = matches[player]
		if not m or not m.alive then
			return
		end
		if action == "call" and m.phase == "playcall" and MatchConfig.PlaysById[arg] then
			m.call = MatchConfig.PlaysById[arg]
			m.play = { state = "presnap" }
			m.phase = "presnap"
			tagTargets(m)
			sendState(m)
		elseif action == "snap" and m.phase == "presnap" then
			snap(m)
		elseif action == "throw" and m.phase == "live" and type(arg) == "number" then
			throw(m, arg)
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
