-- Match camera (client): follows YOUR player from behind, like being on the field.
--   Lined up: behind you and a little high, looking down the field so you can read it.
--   QB in the pocket: higher, leaning toward where you're aiming the throw.
--   Ball in the air: behind you, looking at where it's coming down.
--   You have the ball: a chase cam that turns with you.
--   Anyone else on offense (blocking, running a route): behind you, keeping the ball in view.
--   On defense: always behind you looking straight at the offense; it never swings to follow the
--   ball, so your controls stay the same all play.
-- Everything is smoothed (position and the direction it looks), so switching players or a new
-- play never cuts hard; big jumps (a new line of scrimmage) snap.
-- Driven by MatchUI: MatchCamera.Update(state) on every server state, Stop() when the game ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Settings = require(ReplicatedStorage.Client.Settings)

local MatchCamera = {}
MatchCamera.AimPoint = nil -- where the QB is aiming (set by MatchUI)
MatchCamera.BallPosition = nil -- function -> the locally drawn ball in flight (set by MatchUI)

local player = Players.LocalPlayer
local state = nil
local active = false
local UP = Vector3.new(0, 1, 0)
local smooth = nil -- the camera's smoothed CFrame (shake is added on top, never fed back in)
local heading = nil -- smoothed flat direction the camera looks along
local shakeAmp, shakeUntil, shakeLength = 0, 0, 0
local SNAP_DISTANCE = 70 -- a target this far away (new play, new possession) cuts instead of flying

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function avatarRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- turn the camera's heading toward `dir` at `rate` (per second)
local function steer(dir, dt, rate)
	dir = flat(dir)
	if dir.Magnitude < 0.01 then
		return heading or Vector3.new(0, 0, -1)
	end
	dir = dir.Unit
	if not heading then
		heading = dir
	else
		local h = heading:Lerp(dir, math.min(1, dt * rate))
		heading = h.Magnitude > 0.01 and h.Unit or dir
	end
	return heading
end

local function targetCFrame(dt)
	local s = state
	if not s or not s.losWorld or not s.downfield then
		return nil, 0
	end
	local los, down = s.losWorld, s.downfield
	local userBall = s.possession == "user"
	local face = userBall and down or -down -- the way your team looks
	local root = avatarRoot()
	local live = s.phase == "live" and s.playState or nil
	local flight = MatchCamera.BallPosition and MatchCamera.BallPosition()
	local ballPos = flight or (s.ball and s.ball.Parent and s.ball.Position) or los

	if s.phase == "final" or not root then
		local h = steer(face, dt, 2)
		return CFrame.lookAt(los - h * 40 + UP * 34, los + h * 12), 2.5
	end
	local p = root.Position

	if not live then
		-- lined up (calling the play, pre-snap, between plays)
		local h = steer(face, dt, 6)
		return CFrame.lookAt(p - h * 16 + UP * 11, p + h * 18 + UP), 6
	end

	if live == "dropback" and s.canThrow then
		-- QB in the pocket: look downfield, leaning toward the aim
		local look = p + face * 26
		if MatchCamera.AimPoint then
			look = look:Lerp(MatchCamera.AimPoint, 0.45)
		end
		local h = steer(look - p, dt, 4)
		return CFrame.lookAt(p - h * 13 + UP * 12.5, look), 6
	end

	if not userBall then
		-- defense: a steady view behind you facing the offense (it does not chase the ball)
		local h = steer(face, dt, 5)
		return CFrame.lookAt(p - h * 15 + UP * 9, p + h * 16 + UP), 6
	end

	if live == "air" and s.air then
		-- ball in the air: behind you, looking where it comes down
		local to = s.air.to
		local dir = flat(to - p).Magnitude > 6 and (to - p) or face
		local h = steer(dir, dt, 4)
		return CFrame.lookAt(p - h * 14 + UP * 7.5, p:Lerp(to, 0.5) + UP * 1.5), 6
	end

	if s.youCarry then
		-- you have the ball: turn with you, mostly the way you're running
		local vel = flat(root.AssemblyLinearVelocity)
		local dir = (vel.Magnitude > 4 and vel.Unit or face) + face * 0.6
		local h = steer(dir, dt, 3.5)
		return CFrame.lookAt(p - h * 13 + UP * 6.5, p + h * 18), 7
	end

	-- blocking, covering, chasing: behind you with the ball in view
	local toBall = flat(ballPos - p)
	local dir = toBall.Magnitude > 5 and (toBall.Unit + face * 0.4) or face
	local h = steer(dir, dt, 3)
	return CFrame.lookAt(p - h * 14 + UP * 8, p:Lerp(ballPos, 0.35) + UP), 6
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
	if cam.CameraType ~= Enum.CameraType.Scriptable or not smooth or (smooth.Position - target.Position).Magnitude > SNAP_DISTANCE then
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
	cam.FieldOfView = 70
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
	heading = nil
	shakeUntil = 0
	MatchCamera.AimPoint = nil
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
