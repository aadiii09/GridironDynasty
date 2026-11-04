-- MatchFX (client): makes matches feel like football.
--   * Poses: stances, blocking, ball tucked on the carry, throwing motion, diving tackles and
--     celebrations, layered on top of the run/idle animations by rotating the R15 joints.
--     NPC poses come from the server ("Pose" attribute); your own avatar's pose is worked out here.
--   * Ball flight: drawn locally from the throw's arc, so it's perfectly smooth (no network lag).
--   * Sound: whistles, throws, catches, hits, crowd cheers/groans and the stadium crowd loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Sounds = require(ReplicatedStorage.Client.Sounds)

local MatchFX = {}

local player = Players.LocalPlayer
local rad = math.rad
local A = CFrame.Angles

-- Joint targets per pose (joint name -> CFrame, applied in the joint's own space).
-- R15 axes: +X rotation swings a limb forward; negative X bends a knee; negative X on the
-- waist leans forward.
local POSES = {
	stance3 = { -- 3-point stance (linemen): low, hand on the turf
		Root = CFrame.new(0, -0.85, 0) * A(rad(-32), 0, 0),
		Waist = A(rad(-20), 0, 0),
		Neck = A(rad(40), 0, 0),
		RightHip = A(rad(80), 0, 0), RightKnee = A(rad(-85), 0, 0),
		LeftHip = A(rad(60), 0, 0), LeftKnee = A(rad(-80), 0, 0),
		RightShoulder = A(rad(70), 0, 0), RightElbow = A(rad(5), 0, 0),
		LeftShoulder = A(rad(20), 0, rad(-8)), LeftElbow = A(rad(40), 0, 0),
	},
	stance2 = { -- 2-point stance (skill players, linebackers, DBs): knees bent, ready
		Root = CFrame.new(0, -0.55, 0) * A(rad(-14), 0, 0),
		Waist = A(rad(-16), 0, 0),
		Neck = A(rad(22), 0, 0),
		RightHip = A(rad(45), 0, 0), RightKnee = A(rad(-55), 0, 0),
		LeftHip = A(rad(40), 0, 0), LeftKnee = A(rad(-50), 0, 0),
		RightShoulder = A(rad(28), 0, 0), RightElbow = A(rad(35), 0, 0),
		LeftShoulder = A(rad(28), 0, 0), LeftElbow = A(rad(35), 0, 0),
	},
	qb = { -- QB in shotgun: upright, ball held at the chest
		Root = CFrame.new(0, -0.3, 0) * A(rad(-6), 0, 0),
		RightHip = A(rad(20), 0, 0), RightKnee = A(rad(-25), 0, 0),
		LeftHip = A(rad(20), 0, 0), LeftKnee = A(rad(-25), 0, 0),
		RightShoulder = A(rad(55), 0, rad(-20)), RightElbow = A(rad(95), 0, 0),
		LeftShoulder = A(rad(55), 0, rad(20)), LeftElbow = A(rad(95), 0, 0),
	},
	block = { -- pass/run blocking: hands up and out, chest forward
		Root = CFrame.new(0, -0.45, 0) * A(rad(-12), 0, 0),
		Waist = A(rad(-14), 0, 0),
		RightShoulder = A(rad(85), 0, rad(-10)), RightElbow = A(rad(45), 0, 0),
		LeftShoulder = A(rad(85), 0, rad(10)), LeftElbow = A(rad(45), 0, 0),
		RightHip = A(rad(30), 0, 0), RightKnee = A(rad(-40), 0, 0),
		LeftHip = A(rad(30), 0, 0), LeftKnee = A(rad(-40), 0, 0),
	},
	carry = { -- ball tucked high and tight in the right arm, upper body only (legs keep running)
		RightShoulder = A(rad(35), 0, rad(-25)), RightElbow = A(rad(115), 0, 0),
		Waist = A(rad(-8), 0, 0),
	},
	throw = { -- throwing arm cocked back over the shoulder, off arm pointing at the target
		RightShoulder = A(rad(160), 0, rad(-25)), RightElbow = A(rad(70), 0, 0),
		LeftShoulder = A(rad(85), 0, rad(15)), LeftElbow = A(rad(10), 0, 0),
		Waist = A(rad(6), rad(-30), 0),
	},
	dive = { -- tackle: launching forward, arms wrapping
		Root = CFrame.new(0, -0.9, -0.6) * A(rad(-60), 0, 0),
		RightShoulder = A(rad(150), 0, rad(-10)), RightElbow = A(rad(20), 0, 0),
		LeftShoulder = A(rad(150), 0, rad(10)), LeftElbow = A(rad(20), 0, 0),
		RightHip = A(rad(-15), 0, 0), LeftHip = A(rad(10), 0, 0),
	},
	celebrate = { -- arms up!
		RightShoulder = A(rad(165), 0, rad(-25)), RightElbow = A(rad(10), 0, 0),
		LeftShoulder = A(rad(165), 0, rad(25)), LeftElbow = A(rad(10), 0, 0),
		Neck = A(rad(-15), 0, 0),
	},
}
-- the throwing arm comes forward through the release
local THROW_RELEASE = { RightShoulder = A(rad(70), 0, rad(-10)), RightElbow = A(rad(10), 0, 0), Waist = A(rad(-10), rad(20), 0) }

local JOINT_PARENT = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg",
}

local rigs = {} -- [Model] = { joints = {name = Motor6D}, weight = 0, pose = nil, poseStart = 0 }
local state, prev = nil, nil
local localPose = nil -- your avatar's pose
local localPoseUntil = 0

local function rigFor(model)
	local r = rigs[model]
	if r then
		return r
	end
	r = { joints = {}, weight = 0, pose = nil, poseStart = 0 }
	for jointName, partName in JOINT_PARENT do
		local p = model:FindFirstChild(partName)
		local j = p and p:FindFirstChild(jointName)
		-- classic rigs use Motor6D; current Roblox rigs use AnimationConstraint (both have Transform)
		if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
			r.joints[jointName] = j
		end
	end
	rigs[model] = r
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)
	return r
end

local function applyPose(model, pose, dt)
	local r = rigFor(model)
	if pose ~= r.pose then
		if pose then
			r.lastPose = pose
		end
		r.pose = pose
		r.poseStart = os.clock()
	end
	local target = pose and 1 or 0
	r.weight += (target - r.weight) * math.min(1, dt * (pose == "dive" and 14 or 9))
	if r.weight < 0.01 then
		return
	end
	local def = POSES[r.pose or r.lastPose]
	if not def then
		return
	end
	local release = (r.pose or r.lastPose) == "throw" and os.clock() - r.poseStart > 0.28
	for name, joint in r.joints do
		local cf = (release and THROW_RELEASE[name]) or def[name]
		if cf then
			joint.Transform = joint.Transform:Lerp(cf, r.weight)
		end
	end
end

-- Your avatar's pose comes from the match state (the server doesn't animate you)
local function avatarPose()
	if not state then
		return nil
	end
	if os.clock() < localPoseUntil then
		return localPose
	end
	local userBall = state.possession == "user"
	if state.phase == "presnap" or state.phase == "playcall" or state.phase == "defcall" then
		return userBall and "qb" or "stance2"
	end
	if state.phase == "live" and userBall then
		if state.playState == "carry" then
			return "carry"
		elseif state.playState == "dropback" then
			return "qb"
		end
	end
	return nil
end

-- Local ball flight ---------------------------------------------------------------------
local flightBall, flightTrail
local function makeFlightBall()
	local art = ReplicatedStorage:FindFirstChild("Art")
	local mesh = art and art:FindFirstChild("Football")
	local b
	if mesh then
		b = mesh:Clone()
		b.Size = b.Size * 1.7
		b.TextureID = mesh.TextureID
	else
		b = Instance.new("Part")
		b.Size = Vector3.new(0.75, 0.75, 1.25)
		b.Color = Color3.fromRGB(122, 64, 34)
		Instance.new("SpecialMesh", b).MeshType = Enum.MeshType.Sphere
	end
	b.Name = "FlightBall"
	b.Anchored = true
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.18, 0)
	a0.Parent = b
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.18, 0)
	a1.Parent = b
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.4
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.LightEmission = 0.7
	trail.Parent = b
	return b, trail
end

local function arcPoint(air, s)
	return air.from:Lerp(air.to, s) + Vector3.new(0, 4 * air.h * s * (1 - s), 0)
end

local function updateFlight()
	local air = state and state.phase == "live" and state.playState == "air" and state.air
	if not air then
		if flightBall then
			flightBall.Parent = nil
		end
		MatchFX.BallPosition = nil
		return
	end
	if not flightBall then
		flightBall, flightTrail = makeFlightBall()
	end
	if not flightBall.Parent then
		flightTrail.Enabled = false
		flightBall.Parent = workspace
		task.defer(function()
			flightTrail.Enabled = true
		end)
	end
	local s = math.clamp((workspace:GetServerTimeNow() - air.startedAt) / air.T, 0, 1)
	local p = arcPoint(air, s)
	local ahead = arcPoint(air, math.min(1, s + 0.03))
	local look = (ahead - p).Magnitude > 0.01 and CFrame.lookAt(p, ahead) or CFrame.new(p)
	-- mesh long axis is X: turn it to point along the flight, then spiral
	flightBall.CFrame = look * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(os.clock() * 22, 0, 0)
	MatchFX.BallPosition = p
end

-- Per-frame: after animations, before physics ---------------------------------------------
local connection
local function step(dt)
	updateFlight()
	if not state then
		return
	end
	local field = state.ball and state.ball.Parent
	if field then
		for _, model in field:GetChildren() do
			if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
				local head = model:FindFirstChild("Head")
				if head and head.Transparency < 1 then -- skip hidden (benched) NPCs
					applyPose(model, model:GetAttribute("Pose"), dt)
				end
			end
		end
	end
	local char = player.Character
	if char then
		applyPose(char, avatarPose(), dt)
	end
end

-- Sound cues from state changes -------------------------------------------------------------
local function cues(s, p)
	local userBall = s.possession == "user"
	local msg = s.message or ""
	-- snap
	if s.phase == "live" and (not p or p.phase ~= "live") then
		Sounds.Play("bodyfall", 0.5, 1.2)
	end
	-- throw
	if s.playState == "air" and (not p or p.playState ~= "air") then
		Sounds.Play("whoosh", 1, 0.9 + math.random() * 0.2)
		if userBall then
			localPose, localPoseUntil = "throw", os.clock() + 0.55
		end
	end
	-- catch
	if p and p.playState == "air" and s.playState == "carry" then
		Sounds.Play("catch")
	end
	-- broken tackles (TRUCKED! / JUKED! / STIFF ARM! / SPIN MOVE! / MISSED TACKLE)
	if s.phase == "live" and msg ~= "" and msg ~= (p and p.message or "") and (msg:find("TACKLE") or msg:find("TRUCKED") or msg:find("JUKED") or msg:find("STIFF ARM") or msg:find("SPIN MOVE") or msg:find("SLIPPED") or msg:find("ESCAPED")) then
		Sounds.Play("tackle", msg:find("TRUCKED") and 1 or 0.6, msg:find("TRUCKED") and 0.85 or 1.15)
	end
	-- play over
	if s.phase == "result" and (not p or p.phase ~= "result") then
		task.delay(0.15, function()
			Sounds.Play("whistle")
		end)
		if msg:find("TOUCHDOWN") then
			Sounds.Play(userBall and "cheer" or "groan", 1.2)
		elseif msg:find("INTERCEPT") or msg:find("SACKED") or msg:find("FUMBLE") then
			Sounds.Play("tackle")
			Sounds.Play(userBall and "groan" or "cheer", 0.9)
		elseif msg:find("BIG HIT") then
			Sounds.Play("tackle", 1.3, 0.8)
			Sounds.Play("bodyfall", 1)
			Sounds.Play("cheer", 0.5)
		elseif msg:find("Tackled") then
			Sounds.Play("tackle", 1, 0.9 + math.random() * 0.2)
			Sounds.Play("bodyfall", 0.8)
		elseif msg:find("DROPPED") or msg:find("INCOMPLETE") or msg:find("BROKEN UP") then
			Sounds.Play(userBall and "groan" or "cheer", 0.5)
		end
		if msg:find("FIRST DOWN") and userBall then
			Sounds.Play("cheer", 0.45)
		end
	end
	if s.phase == "final" and (not p or p.phase ~= "final") then
		Sounds.Play(s.final and s.final.result == "Win" and "cheer" or "groan", 1.3)
	end
end

function MatchFX.Update(s)
	prev, state = state, s
	if not connection then
		connection = RunService.Stepped:Connect(function(_, dt)
			step(dt)
		end)
		Sounds.SetLoop("crowdLoop")
	end
	cues(s, prev)
end

function MatchFX.Fall()
	Sounds.Play("tackle")
	Sounds.Play("bodyfall", 0.8)
end

function MatchFX.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	state, prev = nil, nil
	if flightBall then
		flightBall.Parent = nil
	end
	MatchFX.BallPosition = nil
	table.clear(rigs)
	Sounds.SetLoop("lobbyMusic")
end

return MatchFX
