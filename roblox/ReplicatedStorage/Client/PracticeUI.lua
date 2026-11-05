-- PracticeUI (client): practice mode, a playground to get reps at everything in the game.
--   PLAY -> PRACTICE tab: pick a drill (MainUI calls Render(body, deps)).
--   In practice: a drill list on the left to switch any time, with a tip for the drill you're on
--   (MatchUI calls Update(gui, state) on every server state).
-- No coins, no record, no play clock, and the drive never ends (MatchService PRACTICE).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(ReplicatedStorage.Client.UIKit)
local Keybinds = require(ReplicatedStorage.Client.Keybinds)
local ScreenFit = require(ReplicatedStorage.Client.ScreenFit)

local C = UI.Color
local F = UI.Font
local new = UI.new
local TOUCH = ScreenFit.IsTouch()

local PracticeUI = {}

-- the key (PC) or button name (phones) for an action, in brackets
local function k(action, touchName)
	if TOUCH then
		return touchName or string.upper(action)
	end
	return "[" .. Keybinds.Text(action) .. "]"
end

PracticeUI.Drills = {
	{
		id = "qb", name = "QB", title = "PASSING", color = C.Accent, icon = "football",
		desc = "You're the quarterback. Call a play, read the defense and throw.",
		tip = function()
			if TOUCH then
				return "Pick a play, tap SNAP, then tap the field where you want the ball. Throw it where your receiver is GOING, not where he is."
			end
			return ("Pick a play, %s to snap, aim with the mouse and %s to throw. Lead your receiver: throw where he's going."):format(k("snap"), k("throw"))
		end,
	},
	{
		id = "wr", name = "WR", title = "CATCHING", color = C.Gold, icon = "football",
		desc = "You're the top receiver. Run your route - the QB throws to you every play.",
		tip = function()
			return ("Run your route. When it's thrown, get to the GOLD CIRCLE and %s as it arrives. %s to jump for it. Then run!"):format(k("catch", "tap CATCH"), k("jump", "JUMP"))
		end,
	},
	{
		id = "rb", name = "RB", title = "RUNNING", color = C.Blue, icon = "football",
		desc = "Every play is a handoff to you. Find the hole and make people miss.",
		tip = function()
			return ("Take the handoff and find a hole. Right before a tackler gets to you: %s juke, %s spin, %s stiff arm. %s to dive for extra yards."):format(
				k("juke", "JUKE"), k("spin", "SPIN"), k("stiff", "STIFF ARM"), k("dive", "DIVE"))
		end,
	},
	{
		id = "cover", name = "DB", title = "COVERAGE", color = C.Purple, icon = "switch",
		desc = "You're the cornerback on their best receiver. They throw at your man a lot.",
		tip = function()
			return ("Stay with the WR1. When the ball's in the air, beat him to the GOLD CIRCLE: %s to pick it, %s to break it up. Missed? %s to dive-tackle."):format(
				k("catch", "CATCH"), k("jump", "JUMP"), k("dive", "DIVE TACKLE"))
		end,
	},
	{
		id = "tackle", name = "LB", title = "TACKLING", color = C.Red, icon = "whistle",
		desc = "You're a linebacker against the run. Every play is a run at you.",
		tip = function()
			return ("Read the handoff, then run at the ball carrier (GOLD outline). %s to dive at him when you're close - a diving tackle reaches further."):format(k("dive", "DIVE TACKLE"))
		end,
	},
}
local byId = {}
for _, d in PracticeUI.Drills do
	byId[d.id] = d
end

-- PLAY -> PRACTICE ------------------------------------------------------------------------------
-- deps: { start = function(drillId) } (closes the menu and starts practice)
function PracticeUI.Render(body, deps)
	UI.text({ Text = "PRACTICE ANY PART OF THE GAME  -  NO COINS, NO RECORD, NO PLAY CLOCK. SWITCH DRILLS ANY TIME.", FontFace = F.Bold, TextColor3 = C.Muted, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), ZIndex = 71 }).Parent = body
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 290), Position = UDim2.fromOffset(0, 30), ZIndex = 71 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	row.Parent = body
	for i, d in PracticeUI.Drills do
		local card = new("TextButton", { Name = "Drill_" .. d.id, AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(152, 284), LayoutOrder = i, ZIndex = 71 }, {
			UI.corner(14),
			UI.stroke(d.color, 1, 0.3),
		})
		local top = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 86), ZIndex = 72 }, { UI.corner(14) })
		UI.flowGradient(top, d.color, d.color:Lerp(C.BG, 0.5), d.color)
		top.Parent = card
		UI.text({ Text = d.name, FontFace = F.Display, TextScaled = false, TextSize = 38, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 42), Position = UDim2.fromOffset(0, 8), ZIndex = 73 }).Parent = card
		UI.text({ Text = d.title, FontFace = F.Heavy, TextColor3 = C.BG, TextScaled = false, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 56), ZIndex = 73 }).Parent = card
		UI.text({ Text = d.desc, FontFace = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextScaled = false, TextSize = 13, Size = UDim2.new(1, -20, 0, 120), Position = UDim2.fromOffset(10, 98), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 72 }).Parent = card
		local function go()
			deps.start(d.id)
		end
		UI.button({ name = "Start", kind = "dark", text = "PRACTICE", size = UDim2.new(1, -20, 0, 46), position = UDim2.new(0, 10, 1, -58), textSize = 17, z = 73 }, go).Parent = card
		card.Activated:Connect(go)
		card.Parent = row
	end
end

-- In practice: the drill list + tip -------------------------------------------------------------
local hud, list, tipText, shownSig, header
local sendDrill

local function buildHud(gui, fire)
	sendDrill = fire
	hud = new("Frame", { Name = "Practice", BackgroundTransparency = 1, Position = TOUCH and UDim2.fromOffset(12, 150) or UDim2.fromOffset(16, 62), Size = UDim2.fromOffset(TOUCH and 200 or 300, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 8 }, {
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	hud.Parent = gui
	-- header: on phones it opens / closes the drill list (it would cover the joystick otherwise)
	header = new("TextButton", { Name = "Header", AutoButtonColor = false, Text = "", BackgroundColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0, ZIndex = 9 }, { UI.corner(8) })
	UI.text({ Name = "Label", Text = "PRACTICE", FontFace = F.Heavy, TextColor3 = C.BG, TextScaled = false, TextSize = 14, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10 }).Parent = header
	header.Parent = hud
	list = new("Frame", { BackgroundTransparency = 1, Visible = not TOUCH, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, ZIndex = 8 }, {
		new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	list.Parent = hud
	local tipBox = UI.glass({ Name = "Tip", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 8, Visible = not TOUCH })
	tipBox:FindFirstChildOfClass("UIStroke").Color = C.Gold
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }).Parent = tipBox
	tipText = UI.text({ Text = "", FontFace = F.Medium, TextScaled = false, TextSize = 14, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9 })
	tipText.Parent = tipBox
	tipBox.Parent = hud
	header.Activated:Connect(function()
		if TOUCH then
			UI.clickSound()
			list.Visible = not list.Visible
		end
	end)
end

-- gui: MatchUI's ScreenGui; fire(drillId) tells the server to switch
function PracticeUI.Update(gui, s, fire)
	local p = s and s.practice
	if not p then
		if hud then
			hud.Visible = false
		end
		return
	end
	if not hud then
		buildHud(gui, fire)
	end
	hud.Visible = true
	local drill = byId[p.drill]
	if drill then
		tipText.Text = drill.tip()
		header.Label.Text = ("PRACTICE  -  %s %s%s"):format(drill.name, drill.title, TOUCH and (list.Visible and "   ^" or "   v") or "")
	end
	-- the switch buttons only redraw when the drill changes
	if shownSig == p.drill then
		return
	end
	shownSig = p.drill
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i, d in PracticeUI.Drills do
		local on = d.id == p.drill
		local b = new("TextButton", { Name = "Drill_" .. d.id, AutoButtonColor = false, Text = "", BackgroundColor3 = on and d.color or C.Panel, BackgroundTransparency = on and 0 or 0.25, Size = UDim2.new(1, 0, 0, TOUCH and 34 or 36), LayoutOrder = i, ZIndex = 9 }, {
			UI.corner(9),
			UI.stroke(d.color, 1, on and 0 or 0.5),
		})
		UI.text({ Text = d.name, FontFace = F.Display, TextColor3 = on and C.BG or d.color, TextScaled = false, TextSize = 20, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 44, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10 }).Parent = b
		UI.text({ Text = d.title, FontFace = F.Bold, TextColor3 = on and C.BG or C.Text, TextScaled = false, TextSize = 13, Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -60, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10 }).Parent = b
		b.Activated:Connect(function()
			if d.id ~= shownSig then
				UI.clickSound()
				sendDrill(d.id)
			end
			if TOUCH then
				list.Visible = false
			end
		end)
		b.Parent = list
	end
end

function PracticeUI.Reset()
	shownSig = nil
	if hud then
		hud.Visible = false
	end
end

return PracticeUI
