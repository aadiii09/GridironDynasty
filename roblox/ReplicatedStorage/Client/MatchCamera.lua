-- Broadcast-style match camera (client).
--   Your ball, before/at the snap: high "all-22" view from behind the line so you see the field.
--   Ball in the air: the camera rides behind the ball to the catch.
--   Ball carrier (you): elevated chase cam looking downfield.
--   CPU ball: high view from behind your defense; during the play it follows you + the ball.
-- Driven by MatchUI: MatchCamera.Update(state) on every server state, Stop() when the game ends.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MatchCamera = {}

local player = Players.LocalPlayer
local state = nil
local active = false
local lastBallPos, ballDir = nil, nil
local UP = Vector3.new(0, 1, 0)

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

	-- ball in the air: ride behind it
	if playState == "air" and ball and ball.Parent then
		local p = ball.Position
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
		if playState == "carry" and root then
			-- chase cam on you with the ball
			local p = root.Position
			return CFrame.lookAt(p - down * 20 + UP * 13, p + down * 14), 6
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
		local mid = p:Lerp(look, 0.5)
		return CFrame.lookAt(p + down * 24 + UP * 20, mid), 5
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
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = target
	end
	local alpha = 1 - math.exp(-dt * speed)
	cam.CFrame = cam.CFrame:Lerp(target, alpha)
	cam.FieldOfView = 62
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
