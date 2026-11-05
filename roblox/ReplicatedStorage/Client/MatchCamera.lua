-- Broadcast-style match camera (client).
--   Your ball, before/at the snap: high "all-22" view from behind the line so you see the field.
--   Ball in the air: the camera rides behind the ball to the catch.
--   Ball carrier (you): elevated chase cam looking downfield.
--   CPU ball: high view from behind your defense; during the play it follows you + the ball.
-- Driven by MatchUI: MatchCamera.Update(state) on every server state, Stop() when the game ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Settings = require(ReplicatedStorage.Client.Settings)

local MatchCamera = {}

local player = Players.LocalPlayer
local state = nil
local active = false
local lastBallPos, ballDir = nil, nil
local UP = Vector3.new(0, 1, 0)
local smooth = nil -- the camera's smoothed CFrame (shake is added on top, never fed back in)
local shakeAmp, shakeUntil, shakeLength = 0, 0, 0

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function avatarRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function targetCFrame(dt)
	local s = state
	if not s or not s.losWorld or not s.downfield then
		return nil, 0
	end
	local los, down = s.losWorld, s.downfield
	local root = avatarRoot()
	local userBall = s.possession == "user"
	local ball = s.ball
	local playState = s.phase == "live" and s.playState or nil

	-- CPU throw while you're on defense: stay high behind your defense, framing you and the
	-- landing spot (gold circle), so you can get there for the pick
	if playState == "air" and not userBall and s.air and root then
		local p = root.Position
		local mid = p:Lerp(s.air.to, 0.5)
		return CFrame.lookAt(mid + down * 30 + UP * 28, mid), 5
	end

	-- your throw: ride behind the ball (the smooth locally-drawn ball from MatchFX)
	local flightPos = MatchCamera.BallPosition and MatchCamera.BallPosition()
	if playState == "air" and (flightPos or (ball and ball.Parent)) then
		local p = flightPos or ball.Position
		if lastBallPos then
			local v = flat(p - lastBallPos)
			if v.Magnitude > 0.05 then
				ballDir = ballDir and ballDir:Lerp(v.Unit, math.min(1, dt * 8)) or v.Unit
			end
		end
		lastBallPos = p
		local dir = ballDir or (userBall and down or -down)
		local camPos = p - dir * 17 + UP * 8
		return CFrame.lookAt(camPos, p + dir * 6), 7
	end
	lastBallPos, ballDir = nil, nil

	if userBall then
		if playState == "carry" and root and s.mode == "custom" and not s.youCarry then
			-- custom game, a teammate has the ball: frame you and him from behind
			local p = root.Position
			local look = ball and ball.Parent and ball.Position or p
			local mid = p:Lerp(look, 0.5)
			return CFrame.lookAt(mid - down * 26 + UP * 20, mid + down * 4), 5
		end
		if playState == "carry" and root then
			-- chase cam on you with the ball
			local p = root.Position
			return CFrame.lookAt(p - down * 20 + UP * 13, p + down * 14), 6
		end
		if s.mode == "custom" and not s.canThrow and playState == "dropback" and root then
			-- custom game, you're not the QB: frame you and the ball from behind the offense
			local p = root.Position
			local look = ball and ball.Parent and ball.Position or los
			local mid = p:Lerp(look, 0.35)
			return CFrame.lookAt(mid - down * 30 + UP * 26, mid), 5
		end
		-- high view from behind the offense, sliding a little with the QB
		local x = root and flat(root.Position - los) or Vector3.zero
		local lateral = x - down * x:Dot(down)
		local focus = los + down * 10 + lateral * 0.35
		return CFrame.lookAt(los - down * 36 + UP * 27 + lateral * 0.35, focus), 4
	end

	-- CPU has the ball: you're on defense
	if (playState == "dropback" or playState == "carry") and root then
		local p = root.Position
		local look = ball and ball.Parent and ball.Position or los
		local mid = p:Lerp(look, 0.4)
		return CFrame.lookAt(mid + down * 30 + UP * 28, mid), 5
	end
	local focus = los - down * 2
	return CFrame.lookAt(los + down * 44 + UP * 30, focus), 4
end

local function step(dt)
	if not active then
		return
	end
	local cam = workspace.CurrentCamera
	local target, speed = targetCFrame(dt)
	if not target then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable or not smooth then
		cam.CameraType = Enum.CameraType.Scriptable
		smooth = target
	end
	local alpha = 1 - math.exp(-dt * speed)
	smooth = smooth:Lerp(target, alpha)
	local shake = CFrame.identity
	local now = os.clock()
	if now < shakeUntil then
		local k = shakeAmp * ((shakeUntil - now) / shakeLength) ^ 2
		shake = CFrame.new(math.noise(now * 22, 1.3) * k, math.noise(now * 22, 7.1) * k, 0)
			* CFrame.Angles(math.noise(now * 18, 3.7) * k * 0.02, math.noise(now * 18, 5.9) * k * 0.02, math.noise(now * 18, 9.2) * k * 0.03)
	end
	cam.CFrame = smooth * shake
	cam.FieldOfView = 62
end

-- A quick jolt for big hits (off in Settings -> CAMERA SHAKE)
function MatchCamera.Shake(amount, duration)
	if not Settings.Get("shake") then
		return
	end
	local now = os.clock()
	local left = math.max(0, shakeUntil - now)
	shakeAmp = math.max(amount, left > 0 and shakeAmp or 0)
	shakeLength = math.max(duration or 0.35, left)
	shakeUntil = now + shakeLength
end

function MatchCamera.Update(newState)
	state = newState
	if not active then
		active = true
		RunService:BindToRenderStep("GridironMatchCamera", Enum.RenderPriority.Camera.Value + 1, step)
	end
end

function MatchCamera.Stop()
	if active then
		active = false
		RunService:UnbindFromRenderStep("GridironMatchCamera")
	end
	state = nil
	smooth = nil
	shakeUntil = 0
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

return MatchCamera
