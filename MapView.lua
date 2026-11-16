-- inspired by the game choo choo charles
-- made by fading. dc (or discord): fadingxy_
-- Press the button (or M key) to open the map i fukin guess

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local START_HEIGHT = 450
local MIN_HEIGHT = 80
local MAX_HEIGHT = 1200
local MAP_CENTER = Vector3.new(0, 0, 0)
local MAP_RADIUS = 3000
local MAP_FOV = 40
local OPEN_KEY = Enum.KeyCode.M
local ZOOM_STEP = 0.12
local SMOOTHNESS = 14
local TWEEN_TIME = 0.7
local SEPIA_LOOK = true
local START_AT_PLAYER = true

local BUTTON_IMAGE = "rbxassetid://6031094678" -- working map icon

local MISSION_TYPES = {
	R = { Color = Color3.fromRGB(40, 120, 255), Text = "Required mission" },
	N = { Color = Color3.fromRGB(255, 190, 50), Text = "Optional mission" },
}
local MISSION_IMAGE = "rbxassetid://116471861153777"
local STUD_TO_METER = 0.28
local DOUBLE_TAP_TIME = 0.4

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------
local isOpen = false
local isReady = false
local isClosing = false
local session = 0
local saved = nil
local targetPos = Vector3.new(0, START_HEIGHT, 0)
local currentPos = targetPos
local dragInput = nil
local pinching = false
local pinchStartHeight = START_HEIGHT
local hintShown = false

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local mapCameraPart = workspace:FindFirstChild("MapCameraPart")
if not mapCameraPart then
	mapCameraPart = Instance.new("Part")
	mapCameraPart.Name = "MapCameraPart"
	mapCameraPart.Size = Vector3.new(1, 1, 1)
	mapCameraPart.Anchored = true
	mapCameraPart.CanCollide = false
	mapCameraPart.CanQuery = false
	mapCameraPart.CanTouch = false
	mapCameraPart.CastShadow = false
	mapCameraPart.Transparency = 1
	mapCameraPart.Position = MAP_CENTER + Vector3.new(0, START_HEIGHT, 0)
	mapCameraPart.Parent = workspace
end

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local lockedStats = nil
local function setControls(enabled)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		lockedStats = nil
		return
	end
	if enabled then
		if lockedStats and lockedStats.Humanoid == hum then
			hum.WalkSpeed = lockedStats.WalkSpeed
			hum.JumpPower = lockedStats.JumpPower
			hum.JumpHeight = lockedStats.JumpHeight
		end
		lockedStats = nil
	else
		lockedStats = {
			Humanoid = hum,
			WalkSpeed = hum.WalkSpeed,
			JumpPower = hum.JumpPower,
			JumpHeight = hum.JumpHeight,
		}
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	end
end

local function clampPos(p)
	local flat = Vector3.new(p.X - MAP_CENTER.X, 0, p.Z - MAP_CENTER.Z)
	if flat.Magnitude > MAP_RADIUS then
		flat = flat.Unit * MAP_RADIUS
	end
	return Vector3.new(
		MAP_CENTER.X + flat.X,
		math.clamp(p.Y, MIN_HEIGHT, MAX_HEIGHT),
		MAP_CENTER.Z + flat.Z
	)
end

local function buildCFrame(pos)
	return CFrame.lookAt(pos, pos - Vector3.new(0, 1, 0), Vector3.new(0, 0, -1))
end

local function setHeight(h)
	targetPos = clampPos(Vector3.new(targetPos.X, h, targetPos.Z))
end

local function panBy(delta)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local worldPerPixel = 2 * targetPos.Y * math.tan(math.rad(cam.FieldOfView / 2)) / cam.ViewportSize.Y
	targetPos = clampPos(targetPos + Vector3.new(-delta.X * worldPerPixel, 0, -delta.Y * worldPerPixel))
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local PAPER = Color3.fromRGB(236, 220, 186)
local BROWN = Color3.fromRGB(94, 66, 36)
local INK = Color3.fromRGB(60, 40, 20)

local old = playerGui:FindFirstChild("MapViewGui")
if old then old:Destroy() end

local gui = make("ScreenGui", {
	Name = "MapViewGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- ========== button (draggable) ==========
local mapButton = make("ImageButton", {
	Name = "MapButton",
	Size = UDim2.fromOffset(70, 70),
	Position = UDim2.new(1, -90, 1, -180),
	AnchorPoint = Vector2.new(0, 0),
	BackgroundTransparency = 1,
	Image = BUTTON_IMAGE,
	ImageTransparency = 0,
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 5,
}, gui)

mapButton.MouseEnter:Connect(function()
	TweenService:Create(mapButton, TweenInfo.new(0.15), { ImageTransparency = 0.2 }):Play()
end)
mapButton.MouseLeave:Connect(function()
	TweenService:Create(mapButton, TweenInfo.new(0.15), { ImageTransparency = 0 }):Play()
end)

-- drag state
local dragging = false
local dragStart = nil
local startPos = nil
local wasDragged = false

mapButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		wasDragged = false
		dragStart = input.Position
		startPos = mapButton.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart
		if delta.Magnitude > 10 then
			wasDragged = true
			mapButton.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
-- ============================================

-- Full screen overlay
local overlay = make("Frame", {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Active = true,
	Visible = false,
}, gui)

local hint = make("TextLabel", {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -22),
	Size = UDim2.fromOffset(330, 44),
	BackgroundColor3 = PAPER,
	Text = "Drag to look around  |  Pinch or scroll to zoom  |  Double tap a dot to set a waypoint",
	Visible = false,
	TextColor3 = INK,
	Font = Enum.Font.Antique,
	TextSize = 14,
	TextWrapped = true,
}, overlay)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, hint)
make("UIStroke", { Color = BROWN, Thickness = 2 }, hint)

local closeButton = make("TextButton", {
	Name = "Close",
	Size = UDim2.fromOffset(46, 46),
	Position = UDim2.new(1, -68, 0, 22),
	BackgroundTransparency = 1,
	Text = "X",
	TextColor3 = Color3.fromRGB(0, 0, 0),
	Font = Enum.Font.GothamBold,
	TextSize = 30,
}, overlay)

local marker = make("Frame", {
	Name = "Marker",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(14, 14),
	BackgroundColor3 = Color3.fromRGB(235, 60, 60),
	BorderSizePixel = 0,
	Visible = false,
}, overlay)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, marker)

local missionDots = {}
local selectedDot = nil
local popupToken = 0

local popup = make("TextLabel", {
	Name = "MissionPopup",
	AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.fromOffset(170, 30),
	BackgroundColor3 = PAPER,
	Text = "",
	TextColor3 = INK,
	Font = Enum.Font.Antique,
	TextSize = 16,
	Visible = false,
	ZIndex = 10,
}, overlay)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, popup)
make("UIStroke", { Color = BROWN, Thickness = 2 }, popup)

local function showPopup(entry, text)
	selectedDot = entry
	popup.Text = text
	popup.Visible = true
	popupToken += 1
	local token = popupToken
	task.delay(3, function()
		if popupToken == token then
			popup.Visible = false
			selectedDot = nil
		end
	end)
end

local waypointPart = nil
local WAYPOINT_MARGIN = 50

local waypointHud = make("Frame", {
	Name = "WaypointHud",
	AnchorPoint = Vector2.new(0.5, 0.33),
	Size = UDim2.fromOffset(70, 60),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
make("ImageLabel", {
	Name = "Arrow",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(40, 40),
	BackgroundTransparency = 1,
	Image = MISSION_IMAGE,
	ScaleType = Enum.ScaleType.Fit,
}, waypointHud)
local waypointText = make("TextLabel", {
	Name = "Meters",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 42),
	Size = UDim2.fromOffset(70, 18),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextStrokeTransparency = 0.4,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
}, waypointHud)

local function clearMissionDots()
	for _, entry in ipairs(missionDots) do
		entry.Button:Destroy()
	end
	missionDots = {}
	selectedDot = nil
	popup.Visible = false
end

local function buildMissionDots()
	clearMissionDots()
	for _, inst in ipairs(workspace:GetDescendants()) do
		local info = MISSION_TYPES[inst.Name]
		if info and inst:IsA("BasePart") and inst ~= mapCameraPart then
			local button = make("TextButton", {
				Name = "MissionDot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(36, 36),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 2,
			}, overlay)
			local dot = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = info.Color,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, button)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)

			local entry = { Button = button, Part = inst }
			button.Activated:Connect(function()
				local now = os.clock()
				if entry.LastTap and now - entry.LastTap <= DOUBLE_TAP_TIME then
					entry.LastTap = nil
					if waypointPart == inst then
						waypointPart = nil
						showPopup(entry, "Waypoint removed")
					else
						waypointPart = inst
						showPopup(entry, "Waypoint set")
					end
					return
				end
				entry.LastTap = now
				showPopup(entry, info.Text)
			end)
			table.insert(missionDots, entry)
		end
	end
end

local tint = make("ColorCorrectionEffect", { Name = "MapTint" }, Lighting)

local function tweenTint(on)
	if not SEPIA_LOOK then return end
	local goal
	if on then
		goal = { TintColor = Color3.fromRGB(255, 236, 205), Saturation = -0.35, Contrast = 0.1 }
	else
		goal = { TintColor = Color3.fromRGB(255, 255, 255), Saturation = 0, Contrast = 0 }
	end
	TweenService:Create(tint, TweenInfo.new(TWEEN_TIME), goal):Play()
end

---------------------------------------------------------------------
-- OPEN / CLOSE
---------------------------------------------------------------------
local function openMap()
	if isOpen or isClosing then return end
	local cam = workspace.CurrentCamera
	if not cam then return end

	isOpen = true
	isReady = false
	session += 1
	local mySession = session

	saved = {
		Type = cam.CameraType,
		CFrame = cam.CFrame,
		FOV = cam.FieldOfView,
		Subject = cam.CameraSubject,
	}

	setControls(false)
	mapButton.Visible = false

	local root = getRoot()
	local start = MAP_CENTER
	if START_AT_PLAYER and root then
		start = root.Position
	end
	targetPos = clampPos(Vector3.new(start.X, START_HEIGHT, start.Z))
	currentPos = targetPos

	mapCameraPart.CFrame = buildCFrame(currentPos)

	cam.CameraType = Enum.CameraType.Scriptable
	tweenTint(true)

	local tween = TweenService:Create(
		cam,
		TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ CFrame = mapCameraPart.CFrame, FieldOfView = MAP_FOV }
	)
	tween.Completed:Connect(function()
		if isOpen and session == mySession then
			isReady = true
			overlay.Visible = true
			buildMissionDots()
			if not hintShown then
				hintShown = true
				hint.Visible = true
				task.delay(6, function()
					hint.Visible = false
				end)
			end
		end
	end)
	tween:Play()
end

local function closeMap()
	if not isOpen or isClosing then return end
	isClosing = true
	isReady = false
	dragInput = nil
	pinching = false
	overlay.Visible = false
	marker.Visible = false
	clearMissionDots()
	session += 1

	local cam = workspace.CurrentCamera
	tweenTint(false)

	local function finish()
		isOpen = false
		isClosing = false
		if cam and saved then
			cam.CameraType = saved.Type
			if saved.Subject then
				cam.CameraSubject = saved.Subject
			end
			cam.FieldOfView = saved.FOV
		end
		setControls(true)
		mapButton.Visible = true
	end

	if cam and saved then
		local tween = TweenService:Create(
			cam,
			TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = saved.CFrame, FieldOfView = saved.FOV }
		)
		tween.Completed:Connect(finish)
		tween:Play()
	else
		finish()
	end
end

-- connect button AFTER openMap exists
mapButton.Activated:Connect(function()
	if wasDragged then return end -- only open if it was a real click
	openMap()
end)

closeButton.Activated:Connect(closeMap)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == OPEN_KEY then
		if isOpen then
			closeMap()
		else
			openMap()
		end
	end
end)

player.CharacterAdded:Connect(function()
	if isOpen then
		closeMap()
	end
end)

---------------------------------------------------------------------
-- DRAG + ZOOM INPUT (for the map itself)
---------------------------------------------------------------------
overlay.InputBegan:Connect(function(input)
	if not isReady or dragInput then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not isReady then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		setHeight(targetPos.Y * (1 - input.Position.Z * ZOOM_STEP))
		return
	end

	if pinching or not dragInput then return end

	local isMouseDrag = input.UserInputType == Enum.UserInputType.MouseMovement
		and dragInput.UserInputType == Enum.UserInputType.MouseButton1
	if isMouseDrag or input == dragInput then
		panBy(input.Delta)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input == dragInput then
		dragInput = nil
	end
end)

UserInputService.TouchPinch:Connect(function(_, scale, _, state)
	if not isReady then return end
	if state == Enum.UserInputState.Begin then
		pinching = true
		dragInput = nil
		pinchStartHeight = targetPos.Y
	elseif state == Enum.UserInputState.Change then
		setHeight(pinchStartHeight / math.max(scale, 0.05))
	else
		pinching = false
	end
end)

---------------------------------------------------------------------
-- UPDATE LOOP
---------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not waypointPart or not waypointPart.Parent then
		waypointPart = nil
		waypointHud.Visible = false
		return
	end
	if isOpen or not cam then
		waypointHud.Visible = false
		return
	end

	local pos = waypointPart.Position
	local v = cam:WorldToViewportPoint(pos)
	local screen = cam.ViewportSize
	local center = screen / 2
	local x, y = v.X, v.Y
	local inside = v.Z > 0
		and x > WAYPOINT_MARGIN and x < screen.X - WAYPOINT_MARGIN
		and y > WAYPOINT_MARGIN and y < screen.Y - WAYPOINT_MARGIN

	if not inside then
		local dir = Vector2.new(x, y) - center
		if v.Z < 0 then
			dir = -dir
		end
		if dir.Magnitude < 1 then
			dir = Vector2.new(0, 1)
		end
		local sx = (center.X - WAYPOINT_MARGIN) / math.max(math.abs(dir.X), 0.001)
		local sy = (center.Y - WAYPOINT_MARGIN) / math.max(math.abs(dir.Y), 0.001)
		local s = math.min(sx, sy)
		x = center.X + dir.X * s
		y = center.Y + dir.Y * s
	end

	waypointHud.Position = UDim2.fromOffset(x, y)

	local root = getRoot()
	if root then
		local meters = (root.Position - pos).Magnitude * STUD_TO_METER
		waypointText.Text = string.format("%d M", math.floor(meters + 0.5))
	end
	waypointHud.Visible = true
end)

RunService.RenderStepped:Connect(function(dt)
	if not isOpen then return end
	local cam = workspace.CurrentCamera
	if not cam then return end

	if isReady then
		local alpha = 1 - math.exp(-SMOOTHNESS * dt)
		currentPos = currentPos:Lerp(targetPos, alpha)
		mapCameraPart.CFrame = buildCFrame(currentPos)
		cam.CFrame = mapCameraPart.CFrame

		local root = getRoot()
		if root then
			local v, onScreen = cam:WorldToViewportPoint(root.Position)
			marker.Position = UDim2.fromOffset(v.X, v.Y)
			marker.Visible = onScreen
		else
			marker.Visible = false
		end

		for _, entry in ipairs(missionDots) do
			local part = entry.Part
			if part and part.Parent then
				local v, onScreen = cam:WorldToViewportPoint(part.Position)
				entry.Button.Position = UDim2.fromOffset(v.X, v.Y)
				entry.Button.Visible = onScreen
			else
				entry.Button.Visible = false
			end
		end

		if selectedDot then
			if selectedDot.Button.Visible then
				popup.Position = UDim2.fromOffset(
					selectedDot.Button.Position.X.Offset,
					selectedDot.Button.Position.Y.Offset - 18
				)
				popup.Visible = true
			else
				popup.Visible = false
			end
		end
	end
end)

print("[MapView] loaded - button is draggable + clickable")
