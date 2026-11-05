-- ScreenFit (client): makes a ScreenGui designed for desktop work on any screen.
-- Everything is moved into a "virtual canvas" frame that is at least MIN_HEIGHT x MIN_WIDTH
-- design pixels, then scaled down to the real screen with one UIScale. Desktop = scale 1;
-- a phone in landscape (~844x390) gets a ~0.7 scale of a 1200x560 canvas.
--
--   local fit = ScreenFit.Apply(screenGui)   -- after the UI is built
--   fit.root     -- parent new UI here
--   fit.size()   -- canvas size (use instead of screenGui.AbsoluteSize for layout math)
--   fit.scale()  -- current scale
--
-- Testing: screenGui:SetAttribute("FakeScreen", Vector2.new(844, 390)) lays the UI out for
-- that screen size (top-left corner, clipped) so phone layouts can be checked on a PC.

local UserInputService = game:GetService("UserInputService")

local ScreenFit = {}

local MIN_HEIGHT = 560
local MIN_WIDTH = 1100

function ScreenFit.IsTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function ScreenFit.Apply(gui)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	for _, c in gui:GetChildren() do
		if c:IsA("GuiObject") then
			c.Parent = root
		end
	end
	root.Parent = gui

	local fit = { root = root }
	local canvas = Vector2.new(1920, 1080)
	local changed = Instance.new("BindableEvent")
	fit.changed = changed.Event

	local function update()
		local fake = gui:GetAttribute("FakeScreen")
		local screen = typeof(fake) == "Vector2" and fake or gui.AbsoluteSize
		if screen.X < 10 or screen.Y < 10 then
			return
		end
		local s = math.clamp(math.min(1, screen.Y / MIN_HEIGHT, screen.X / MIN_WIDTH), 0.35, 1)
		uiScale.Scale = s
		canvas = Vector2.new(screen.X / s, screen.Y / s)
		root.Size = UDim2.fromOffset(canvas.X, canvas.Y)
		root.ClipsDescendants = typeof(fake) == "Vector2"
		changed:Fire(canvas, s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	gui:GetAttributeChangedSignal("FakeScreen"):Connect(update)
	update()

	function fit.size()
		return canvas
	end
	function fit.scale()
		return uiScale.Scale
	end
	return fit
end

return ScreenFit
