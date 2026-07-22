--[[ MAXI HUB · maxi-hub-esp.lua — Drawing ESP (логика из Unnamed-ESP, без их UI) ]]

local MaxiHubESP = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local HAS_DRAWING = false
pcall(function()
	local test = Drawing.new("Line")
	test:Remove()
	HAS_DRAWING = true
end)

local PRESET_COLORS = {
	{ 0, 198, 178 },
	{ 0, 200, 100 },
	{ 100, 220, 80 },
	{ 200, 220, 60 },
	{ 255, 180, 40 },
	{ 255, 120, 40 },
	{ 255, 70, 70 },
	{ 255, 100, 180 },
	{ 180, 80, 255 },
	{ 80, 140, 255 },
	{ 100, 200, 255 },
	{ 160, 160, 255 },
	{ 140, 140, 140 },
	{ 220, 220, 220 },
	{ 40, 40, 40 },
	{ 255, 255, 255 },
}

local espState = {
	config = nil,
	tracked = {},
	renderConn = nil,
	scanAt = 0,
}

local function colorFromRgb(rgb)
	if type(rgb) ~= "table" then
		return Color3.fromRGB(0, 198, 178)
	end
	return Color3.fromRGB(rgb[1] or 0, rgb[2] or 198, rgb[3] or 178)
end

local function rgbEqual(a, b)
	return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function worldToScreen(pos)
	local v, onScreen = Camera:WorldToViewportPoint(pos)
	return Vector2.new(v.X, v.Y), onScreen, v.Z
end

local function getTracerOrigin()
	local vp = Camera.ViewportSize
	return Vector2.new(vp.X * 0.5, vp.Y)
end

local function newDrawings()
	if not HAS_DRAWING then
		return nil
	end
	local tracer = Drawing.new("Line")
	tracer.Thickness = 1
	tracer.Visible = false
	local tracerOutline = Drawing.new("Line")
	tracerOutline.Thickness = 3
	tracerOutline.Color = Color3.fromRGB(25, 25, 25)
	tracerOutline.Visible = false
	local nameTag = Drawing.new("Text")
	nameTag.Center = true
	nameTag.Outline = true
	nameTag.Visible = false
	local box = Drawing.new("Square")
	box.Filled = false
	box.Thickness = 1
	box.Visible = false
	return {
		tracer = tracer,
		tracerOutline = tracerOutline,
		nameTag = nameTag,
		box = box,
	}
end

local function hideDrawings(drawings)
	if not drawings then return end
	for _, d in pairs(drawings) do
		d.Visible = false
	end
end

local function removeDrawings(drawings)
	if not drawings then return end
	for _, d in pairs(drawings) do
		pcall(function() d:Remove() end)
	end
end

local function destroyAllTracked()
	for key, item in pairs(espState.tracked) do
		removeDrawings(item.drawings)
		espState.tracked[key] = nil
	end
end

local function getEspPartFromNode(node)
	if not node then return nil end
	if node:IsA("BasePart") then return node end
	local billboard = node:FindFirstChild("BillboardPart")
	if billboard and billboard:IsA("BasePart") then return billboard end
	for _, name in ipairs({ "Hitbox", "RealHitbox" }) do
		local part = node:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then return part end
	end
	return node:FindFirstChildWhichIsA("BasePart", true)
end

local function addTarget(list, key, part, label, color)
	if part and part.Parent and part:IsA("BasePart") then
		table.insert(list, { key = key, part = part, label = label or part.Name, color = color })
	end
end

local function collectTargets(config)
	local list = {}
	local colors = config.EspColors or {}

	pcall(function()
		local interactions = workspace:FindFirstChild("Interactions")
		local nodes = interactions and interactions:FindFirstChild("Nodes")

		if config.EspTrees and nodes then
			local food = nodes:FindFirstChild("Food")
			if food then
				for _, node in ipairs(food:GetChildren()) do
					local part = getEspPartFromNode(node)
					addTarget(list, "tree:" .. node:GetFullName(), part, node.Name, colorFromRgb(colors.trees))
				end
			end
		end

		if config.EspStones and nodes then
			local resources = nodes:FindFirstChild("Resources")
			if resources then
				for _, node in ipairs(resources:GetChildren()) do
					local part = getEspPartFromNode(node)
					addTarget(list, "stone:" .. node:GetFullName(), part, node.Name, colorFromRgb(colors.stones or colors.resources))
				end
			end
		end

		if config.EspResources and nodes then
			local resources = nodes:FindFirstChild("Resources")
			if resources then
				for _, node in ipairs(resources:GetChildren()) do
					local part = getEspPartFromNode(node)
					addTarget(list, "res:" .. node:GetFullName(), part, node.Name, colorFromRgb(colors.resources))
				end
			end
		end
	end)

	if config.EspDragons then
		pcall(function()
			local chars = workspace:FindFirstChild("Characters")
			if chars then
				for _, charFolder in ipairs(chars:GetChildren()) do
					local dragons = charFolder:FindFirstChild("Dragons")
					if dragons then
						for _, dragon in ipairs(dragons:GetChildren()) do
							local hitbox = dragon:FindFirstChild("RealHitbox")
							if hitbox and hitbox:IsA("BasePart") then
								addTarget(list, "dragon:" .. dragon:GetFullName(), hitbox, "Dragon", colorFromRgb(colors.dragons))
							end
						end
					end
				end
			end
		end)
	end

	if config.EspPlayers then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				local char = plr.Character
				local head = char and char:FindFirstChild("Head")
				if head then
					addTarget(list, "plr:" .. plr.Name, head, plr.Name, colorFromRgb(colors.players))
				end
			end
		end
	end

	return list
end

local function syncTracked(targets)
	local seen = {}
	for _, target in ipairs(targets) do
		seen[target.key] = true
		local item = espState.tracked[target.key]
		if not item then
			item = {
				drawings = newDrawings(),
			}
			espState.tracked[target.key] = item
		end
		item.part = target.part
		item.label = target.label
		item.color = target.color
	end
	for key, item in pairs(espState.tracked) do
		if not seen[key] then
			removeDrawings(item.drawings)
			espState.tracked[key] = nil
		end
	end
end

local function renderTracked()
	if not HAS_DRAWING or not espState.config or not espState.config.enabled then
		return
	end

	local config = espState.config
	local origin = getTracerOrigin()
	local textSize = config.EspTextSize or 14

	for _, item in pairs(espState.tracked) do
		local drawings = item.drawings
		local part = item.part
		if drawings and part and part.Parent then
			local screenPos, onScreen, depth = worldToScreen(part.Position)
			if onScreen and depth > 0 then
				local color = item.color or Color3.fromRGB(0, 198, 178)

				local tracerColor = colorFromRgb(config.EspColors and config.EspColors.tracer) or color

				if config.EspTracers then
					drawings.tracerOutline.From = origin
					drawings.tracerOutline.To = screenPos
					drawings.tracerOutline.Visible = true
					drawings.tracer.From = origin
					drawings.tracer.To = screenPos
					drawings.tracer.Color = tracerColor
					drawings.tracer.Visible = true
				else
					drawings.tracer.Visible = false
					drawings.tracerOutline.Visible = false
				end

				if config.EspNames then
					drawings.nameTag.Text = item.label or part.Name
					drawings.nameTag.Size = textSize
					drawings.nameTag.Position = screenPos - Vector2.new(0, textSize + 2)
					drawings.nameTag.Color = color
					drawings.nameTag.Visible = true
				else
					drawings.nameTag.Visible = false
				end

				local boxSize = math.clamp(2200 / math.max(depth, 1), 18, 120)
				drawings.box.Size = Vector2.new(boxSize, boxSize)
				drawings.box.Position = screenPos - Vector2.new(boxSize * 0.5, boxSize * 0.5)
				drawings.box.Color = color
				drawings.box.Visible = true
			else
				hideDrawings(drawings)
			end
		else
			hideDrawings(drawings)
		end
	end
end

local function onRenderStep()
	if not espState.config or not espState.config.enabled then
		destroyAllTracked()
		return
	end

	if tick() - espState.scanAt > 1 then
		espState.scanAt = tick()
		syncTracked(collectTargets(espState.config))
	end

	renderTracked()
end

local function ensureRenderLoop()
	if espState.renderConn then return end
	espState.renderConn = RunService.RenderStepped:Connect(onRenderStep)
end

local function stopRenderLoop()
	if espState.renderConn then
		espState.renderConn:Disconnect()
		espState.renderConn = nil
	end
end

function MaxiHubESP.stop()
	espState.config = nil
	stopRenderLoop()
	destroyAllTracked()
end

function MaxiHubESP.refresh(config)
	espState.config = config
	if not config or not config.enabled then
		MaxiHubESP.stop()
		return
	end
	if not HAS_DRAWING then
		warn("[MAXI HUB ESP] Drawing API недоступен в этом executor")
		return
	end
	ensureRenderLoop()
	espState.scanAt = 0
	syncTracked(collectTargets(config))
end

function MaxiHubESP.buildTab(page, opts)
	opts = opts or {}
	local COLORS = opts.COLORS
	local makeScrollPage = opts.makeScrollPage
	local makeListWrap = opts.makeListWrap
	local addCorner = opts.addCorner
	local makeFlowToggle = opts.makeFlowToggle
	local makeFlowSlider = opts.makeFlowSlider
	local makeSectionTitle = opts.makeSectionTitle
	local L = opts.L or function(k) return k end
	local registerLocale = opts.registerLocale
	local getConfig = opts.getConfig
	local onFieldChange = opts.onFieldChange

	local function setField(key, value)
		if onFieldChange then
			onFieldChange(key, value)
		end
	end

	if not page or not COLORS or not makeSectionTitle then
		return
	end

	local cfg = getConfig and getConfig() or {}

	local scroll = makeScrollPage(page)
	local wrap = makeListWrap(scroll)
	wrap:SetAttribute("MaxiHubCardToggles", true)

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local function makeColorGrid(parent, colorKey, layoutOrder)
		local box = Instance.new("Frame")
		box.Size = UDim2.new(1, 0, 0, 0)
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.BackgroundColor3 = COLORS.card
		box.BorderSizePixel = 0
		box.LayoutOrder = layoutOrder
		box.Parent = parent
		addCorner(box, 8)

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = box

		local head = Instance.new("Frame")
		head.Size = UDim2.new(1, 0, 0, 20)
		head.BackgroundTransparency = 1
		head.Parent = box

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -30, 1, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.Gotham
		title.TextSize = 10
		title.TextColor3 = COLORS.muted
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = L("esp_rgb")
		title.Parent = head
		if registerLocale then registerLocale(title, "esp_rgb") end

		local preview = Instance.new("Frame")
		preview.Size = UDim2.new(0, 18, 0, 18)
		preview.Position = UDim2.new(1, -18, 0, 1)
		preview.BorderSizePixel = 0
		preview.Parent = head
		addCorner(preview, 4)

		local colors = cfg.EspColors or {}
		local current = colors[colorKey] or { 0, 198, 178 }
		preview.BackgroundColor3 = colorFromRgb(current)

		local grid = Instance.new("Frame")
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.BackgroundTransparency = 1
		grid.Parent = box

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.new(0, 22, 0, 22)
		gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
		gridLayout.FillDirectionMaxCells = 8
		gridLayout.Parent = grid

		for _, rgb in ipairs(PRESET_COLORS) do
			local swatch = Instance.new("TextButton")
			swatch.Size = UDim2.new(0, 22, 0, 22)
			swatch.BackgroundColor3 = colorFromRgb(rgb)
			swatch.BorderSizePixel = 0
			swatch.Text = ""
			swatch.AutoButtonColor = false
			swatch.Parent = grid
			addCorner(swatch, 4)

			if rgbEqual(current, rgb) then
				local sel = Instance.new("UIStroke")
				sel.Color = COLORS.text
				sel.Thickness = 2
				sel.Parent = swatch
			end

			swatch.MouseButton1Click:Connect(function()
				local c = getConfig and getConfig() or {}
				c.EspColors = c.EspColors or {}
				c.EspColors[colorKey] = { rgb[1], rgb[2], rgb[3] }
				setField("EspColors", c.EspColors)
				preview.BackgroundColor3 = colorFromRgb(rgb)
				for _, child in ipairs(grid:GetChildren()) do
					if child:IsA("TextButton") then
						local stroke = child:FindFirstChildOfClass("UIStroke")
						if stroke then stroke:Destroy() end
					end
				end
				local sel = Instance.new("UIStroke")
				sel.Color = COLORS.text
				sel.Thickness = 2
				sel.Parent = swatch
			end)
		end
	end

	local function targetRow(toggleKey, colorKey, enabled, onToggle, debounce)
		makeFlowToggle(wrap, L(toggleKey), enabled, onToggle, nextOrder(), debounce, toggleKey)
		makeColorGrid(wrap, colorKey, nextOrder())
	end

	makeSectionTitle(wrap, L("esp_sec_main"), nextOrder(), "esp_sec_main")
	makeFlowToggle(wrap, L("esp_master"), cfg.EspEnabled, function(state)
		setField("EspEnabled", state)
	end, nextOrder(), 0.22, "esp_master")

	targetRow("esp_trees", "trees", cfg.EspTrees, function(state)
		setField("EspTrees", state)
	end, 0.22)
	targetRow("esp_stones", "stones", cfg.EspStones, function(state)
		setField("EspStones", state)
	end, 0.22)
	targetRow("esp_players", "players", cfg.EspPlayers, function(state)
		setField("EspPlayers", state)
	end, nil)
	targetRow("esp_resources", "resources", cfg.EspResources, function(state)
		setField("EspResources", state)
	end, nil)
	targetRow("esp_dragons", "dragons", cfg.EspDragons ~= false, function(state)
		setField("EspDragons", state)
	end, nil)

	makeSectionTitle(wrap, L("esp_sec_style"), nextOrder(), "esp_sec_style")
	makeFlowToggle(wrap, L("esp_tracers"), cfg.EspTracers, function(state)
		setField("EspTracers", state)
	end, nextOrder(), 0.22, "esp_tracers")
	makeColorGrid(wrap, "tracer", nextOrder())
	makeFlowToggle(wrap, L("esp_names"), cfg.EspNames, function(state)
		setField("EspNames", state)
	end, nextOrder(), 0.22, "esp_names")
	if makeFlowSlider then
		makeFlowSlider(wrap, L("esp_text_size"), 10, 20, cfg.EspTextSize or 14, function(v)
			setField("EspTextSize", math.floor(v))
		end, nextOrder(), "esp_text_size")
	end
end

return MaxiHubESP
