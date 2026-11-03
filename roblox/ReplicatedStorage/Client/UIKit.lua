-- UIKit: shared look for every Gridiron Dynasty screen.
-- Dark glass panels, neon accents, icon buttons with hover/press motion, chips, toasts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Assets = require(ReplicatedStorage.Shared.Assets)

local UI = {}

UI.Color = {
	BG = Color3.fromRGB(7, 9, 15),
	Panel = Color3.fromRGB(14, 18, 30),
	Panel2 = Color3.fromRGB(22, 28, 44),
	Stroke = Color3.fromRGB(44, 54, 82),
	Text = Color3.fromRGB(240, 243, 250),
	Muted = Color3.fromRGB(140, 150, 175),
	Accent = Color3.fromRGB(46, 255, 140),
	Gold = Color3.fromRGB(255, 196, 46),
	Blue = Color3.fromRGB(64, 160, 255),
	Red = Color3.fromRGB(255, 84, 96),
	Purple = Color3.fromRGB(176, 92, 255),
}
local C = UI.Color

UI.Font = {
	Heavy = Font.fromEnum(Enum.Font.GothamBlack),
	Bold = Font.fromEnum(Enum.Font.GothamBold),
	Medium = Font.fromEnum(Enum.Font.GothamMedium),
}

-- fallback glyphs when an icon image isn't uploaded yet
local GLYPH = { football = "🏈", packs = "🎴", lineup = "📋", collection = "🗂", coin = "🪙", trophy = "🏆", close = "✕", switch = "⇄", whistle = "📣" }

function UI.new(className, props, children)
	local inst = Instance.new(className)
	for k, v in props or {} do
		inst[k] = v
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	return inst
end
local new = UI.new

function UI.corner(px)
	return new("UICorner", { CornerRadius = UDim.new(0, px or 10) })
end

function UI.stroke(color, thickness, transparency)
	return new("UIStroke", { Color = color or C.Stroke, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function UI.pad(px)
	return new("UIPadding", { PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px), PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px) })
end

function UI.text(props)
	local l = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = C.Text, FontFace = UI.Font.Bold, TextScaled = true })
	for k, v in props do
		l[k] = v
	end
	return l
end

function UI.icon(name, props)
	local id = Assets["icon_" .. name]
	local inst
	if id and id ~= "" then
		inst = new("ImageLabel", { BackgroundTransparency = 1, Image = id, ScaleType = Enum.ScaleType.Fit })
	else
		inst = UI.text({ Text = GLYPH[name] or "•", FontFace = UI.Font.Heavy })
	end
	for k, v in props or {} do
		if inst:IsA("TextLabel") and k == "ImageColor3" then
			inst.TextColor3 = v
		elseif not (inst:IsA("TextLabel") and k == "ImageTransparency") then
			inst[k] = v
		end
	end
	return inst
end

-- Glass panel background (dark, slight top light, thin stroke)
function UI.glass(props, children)
	local f = new("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, BorderSizePixel = 0 }, {
		UI.corner(14),
		UI.stroke(C.Stroke, 1, 0.1),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 175, 190)) }),
	})
	for k, v in props or {} do
		f[k] = v
	end
	for _, child in children or {} do
		child.Parent = f
	end
	return f
end

local KINDS = {
	primary = { bg = C.Accent, bg2 = Color3.fromRGB(20, 200, 120), text = C.BG },
	gold = { bg = C.Gold, bg2 = Color3.fromRGB(240, 150, 30), text = C.BG },
	blue = { bg = C.Blue, bg2 = Color3.fromRGB(40, 110, 230), text = C.Text },
	danger = { bg = C.Red, bg2 = Color3.fromRGB(200, 40, 70), text = C.Text },
	purple = { bg = C.Purple, bg2 = Color3.fromRGB(120, 50, 220), text = C.Text },
	dark = { bg = C.Panel2, bg2 = Color3.fromRGB(16, 20, 32), text = C.Text, stroke = C.Stroke },
	disabled = { bg = Color3.fromRGB(46, 52, 70), bg2 = Color3.fromRGB(36, 40, 56), text = C.Muted },
}

-- Button with optional icon, gradient fill, hover lift and press squish.
function UI.button(opts, onClick)
	local kind = KINDS[opts.kind or "primary"]
	local b = new("TextButton", {
		Name = opts.name or "Button",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = opts.size or UDim2.fromOffset(160, 44),
		Position = opts.position or UDim2.new(),
		AnchorPoint = opts.anchor or Vector2.zero,
		LayoutOrder = opts.order or 0,
		ZIndex = opts.z or 1,
	}, {
		UI.corner(opts.radius or 10),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(kind.bg, kind.bg2) }),
	})
	if kind.stroke then
		UI.stroke(kind.stroke, 1).Parent = b
	end
	local scale = new("UIScale", { Scale = 1 })
	scale.Parent = b
	local content = new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = b.ZIndex }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		UI.pad(opts.padding or 8),
	})
	content.Parent = b
	if opts.icon then
		UI.icon(opts.icon, { Name = "Icon", Size = UDim2.fromScale(opts.iconScale or 0.75, opts.iconScale or 0.75), SizeConstraint = Enum.SizeConstraint.RelativeYY, ImageColor3 = kind.text, LayoutOrder = 1, ZIndex = b.ZIndex }).Parent = content
	end
	local label = UI.text({ Name = "Label", Text = opts.text or "", FontFace = UI.Font.Heavy, TextColor3 = kind.text, Size = UDim2.new(0, 0, 0.82, 0), AutomaticSize = Enum.AutomaticSize.X, TextScaled = false, TextSize = opts.textSize or 18, LayoutOrder = 2, ZIndex = b.ZIndex })
	if opts.text == nil or opts.text == "" then
		label.Visible = false
	end
	label.Parent = content
	b:SetAttribute("Kind", opts.kind or "primary")

	local hoverTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, hoverTween, { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, hoverTween, { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.95 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, hoverTween, { Scale = 1.05 }):Play()
	end)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function UI.setButton(b, textValue, kindName)
	local label = b:FindFirstChild("Label", true)
	if label and textValue then
		label.Text = textValue
		label.Visible = textValue ~= ""
	end
	if kindName and b:GetAttribute("Kind") ~= kindName then
		local kind = KINDS[kindName]
		b:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(kind.bg, kind.bg2)
		if label then
			label.TextColor3 = kind.text
		end
		local ic = b.Content:FindFirstChild("Icon")
		if ic and ic:IsA("ImageLabel") then
			ic.ImageColor3 = kind.text
		end
		b:SetAttribute("Kind", kindName)
	end
end

-- Little rounded tag
function UI.chip(textValue, color, props)
	local c = new("TextLabel", {
		BackgroundColor3 = color or C.Panel2,
		Text = textValue,
		TextColor3 = C.Text,
		FontFace = UI.Font.Heavy,
		TextSize = 12,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
	}, { UI.corner(11), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	for k, v in props or {} do
		c[k] = v
	end
	return c
end

-- Pop-in animation for a GuiObject (uses a UIScale)
function UI.pop(gui, duration)
	local scale = gui:FindFirstChild("PopScale") or new("UIScale", { Name = "PopScale" })
	scale.Parent = gui
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(duration or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Background blur while a menu is open
local blur
function UI.blur(on)
	blur = blur or new("BlurEffect", { Name = "MenuBlur", Size = 0, Parent = Lighting })
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = on and 14 or 0 }):Play()
end

-- Toasts (bottom center)
local toastHolder
function UI.toast(screenGui, msg, color)
	if not toastHolder or not toastHolder.Parent then
		toastHolder = new("Frame", {
			Name = "Toasts",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -150),
			Size = UDim2.fromOffset(420, 200),
			ZIndex = 100,
		}, {
			new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }),
		})
		toastHolder.Parent = screenGui
	end
	local t = UI.glass({ Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 100 }, {
		new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }),
		UI.text({ Text = msg, TextScaled = false, TextSize = 17, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextColor3 = color or C.Text, ZIndex = 101 }),
	})
	t:FindFirstChildOfClass("UIStroke").Color = color or C.Accent
	t.Parent = toastHolder
	UI.pop(t, 0.2)
	task.delay(2.8, function()
		t:Destroy()
	end)
end

function UI.commas(n)
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

return UI
