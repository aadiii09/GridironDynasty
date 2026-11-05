-- Match camera (client): follows YOUR player from behind, like being on the field.
--   Lined up: behind you and a little high, looking down the field so you can read it.
--   QB in the pocket: higher, leaning toward where you're aiming the throw.
--   Ball in the air: behind you, looking at where it's coming down.
--   You have the ball: a chase cam that turns with you.
--   Anyone else on offense (blocking, running a route): behind you, keeping the ball in view.
--   On defense: always behind you looking straight at the offense; it never swings to follow the
--   ball, so your controls stay the same all play. Once the ball is thrown or caught it rises
--   and pulls back (still facing the same way) so you can see the catch even behind you, the
--   ball carrier glows through other players, and an arrow at the screen edge points to him if
--   he's still out of view.
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
local MAX_FRAME = 72 -- on defense the camera pulls back for a ball carrier up to this far away (studs)
local YARD = require(ReplicatedStorage.Shared.MatchConfig).Yard

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
		-- defense: the camera never turns (so your controls never flip), but once the ball is thrown
		-- or caught it rises and pulls back to keep you AND the ball / carrier in the picture,
		-- even when the catch is behind you or off to the side
		local h = steer(face, dt, 5)
		local target = (live == "air" and s.air and s.air.to) or (live == "carry" and ballPos) or nil
		if target then
			local d = flat(target - p)
			if d.Magnitude > MAX_FRAME then
				d = d.Unit * MAX_FRAME -- further than that: keep you on screen, the arrow points to him
			end
			local along = d:Dot(h) -- + = in front of you (the normal view already sees that way)
			local side = (d - h * along).Magnitude
			local behind = math.max(0, -along)
			local need = math.min(MAX_FRAME, math.sqrt(behind * behind + (side * 0.8) ^ 2) + math.max(0, along) * 0.25)
			local k = math.clamp(need / 25, 0, 1)
			local focus = p + d * ((along >= 0 and 0.3 or 0.5) * k)
			local look = (p + h * 16):Lerp(focus, k) + UP
			return CFrame.lookAt(focus - h * (15 + need * 0.45) + UP * (9 + need * 0.6), look), 5
		end
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

-- Defense: find the ball carrier (the ball is welded to his hand), make him glow through other
-- players, and point an arrow at him from the screen edge when he's out of view.
local glow, arrowGui, pin, pointer, arrowText = nil, nil, nil, nil, nil
local RED, DARK = Color3.fromRGB(235, 50, 45), Color3.fromRGB(20, 10, 10)

-- a map pin: a round badge with the distance, and a square turned so one corner points at him
local function buildArrow()
	arrowGui = Instance.new("ScreenGui")
	arrowGui.Name = "CarrierArrow"
	arrowGui.ResetOnSpawn = false
	arrowGui.IgnoreGuiInset = true
	arrowGui.DisplayOrder = 5
	arrowGui.Enabled = false
	pointer = Instance.new("Frame")
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(30, 30)
	pointer.BackgroundColor3 = RED
	pointer.BorderSizePixel = 0
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = DARK
	st.Parent = pointer
	pointer.Parent = arrowGui
	pin = Instance.new("Frame")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Size = UDim2.fromOffset(52, 52)
	pin.BackgroundColor3 = RED
	pin.BorderSizePixel = 0
	pin.ZIndex = 2
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = pin
	local st2 = Instance.new("UIStroke")
	st2.Thickness = 2
	st2.Color = DARK
	st2.Parent = pin
	arrowText = Instance.new("TextLabel")
	arrowText.Size = UDim2.fromScale(1, 1)
	arrowText.BackgroundTransparency = 1
	arrowText.Font = Enum.Font.GothamBlack
	arrowText.TextSize = 14
	arrowText.LineHeight = 0.9
	arrowText.TextColor3 = Color3.new(1, 1, 1)
	arrowText.ZIndex = 3
	arrowText.Parent = pin
	pin.Parent = arrowGui
	arrowGui.Parent = player:WaitForChild("PlayerGui")
end

local function clearCarrier()
	if glow then
		glow:Destroy()
		glow = nil
	end
	if arrowGui then
		arrowGui.Enabled = false
	end
end

local function trackCarrier(cam)
	local s = state
	local ball = s and s.possession ~= "user" and s.phase == "live" and s.playState == "carry" and s.ball
	local weld = ball and ball.Parent and ball:FindFirstChild("HoldWeld")
	local hand = weld and weld.Part0
	local model = hand and hand:FindFirstAncestorOfClass("Model")
	if not model or model == player.Character then
		clearCarrier()
		return
	end
	if not glow or glow.Parent ~= model then
		if glow then
			glow:Destroy()
		end
		glow = Instance.new("Highlight")
		glow.Name = "CarrierGlow"
		glow.FillColor = Color3.fromRGB(255, 70, 60)
		glow.FillTransparency = 0.7
		glow.OutlineColor = Color3.fromRGB(255, 220, 90)
		glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		glow.Parent = model
	end
	if not arrowGui or not arrowGui.Parent then
		buildArrow()
	end
	local pos = (model:FindFirstChild("HumanoidRootPart") or hand).Position
	local vp = cam.ViewportSize
	local sp, onScreen = cam:WorldToViewportPoint(pos)
	local margin = 50
	if onScreen and sp.X > margin and sp.X < vp.X - margin and sp.Y > margin and sp.Y < vp.Y - margin then
		arrowGui.Enabled = false
		return
	end
	-- direction from the screen centre (flipped when he's behind the camera), pinned to the edge
	local c = vp / 2
	local dir = Vector2.new(sp.X, sp.Y) - c
	if sp.Z < 0 then
		dir = -dir
	end
	if dir.Magnitude < 1 then
		dir = Vector2.new(0, 1)
	end
	local edge = c - Vector2.new(margin + 16, margin + 16)
	local scale = math.min(edge.X / math.max(math.abs(dir.X), 1e-3), edge.Y / math.max(math.abs(dir.Y), 1e-3))
	local at = c + dir * scale
	pin.Position = UDim2.fromOffset(at.X, at.Y)
	local tip = at + dir.Unit * 18
	pointer.Position = UDim2.fromOffset(tip.X, tip.Y)
	pointer.Rotation = math.deg(math.atan2(dir.Y, dir.X)) - 45 -- a corner faces him
	local root = avatarRoot()
	local yards = root and math.floor(flat(pos - root.Position).Magnitude / YARD + 0.5) or 0
	arrowText.Text = yards .. "\nYD"
	arrowGui.Enabled = true
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
	trackCarrier(cam)
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
	clearCarrier()
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
