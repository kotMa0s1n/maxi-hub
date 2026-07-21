--[[
  MAXI HUB UI Library (maxi-hub-ui.lua)
  ====================================

  ⛔ НЕ РЕДАКТИРОВАТЬ в папках игр (maxi-hub-scr, maxi-hub-<game>, …).
  Копируй файл из Z:\Desktop\i.s.m\Script\maxi-hub\ как есть.
  Правки UI-стиля — только в этом каноническом файле в maxi-hub\.

  Габариты вкладок и панелей: maxi-hub\.cursor\rules\ui-layout.mdc

  Загрузка:
    local MaxiHubUI = loadstring(readfile("maxi-hub-ui.lua"))()
    local Window = MaxiHubUI.CreateLib("MAXI HUB", { guiName = "UniqueName" })
    Window:Finalize()
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local MaxiHubUI = {}
MaxiHubUI.VERSION = "1.0.0"

function MaxiHubUI.create(config)
	config = config or {}

	local player = config.player or Players.LocalPlayer
	local playerGui = config.playerGui or player:WaitForChild("PlayerGui")
	local genv = config.genv or (typeof(getgenv) == "function" and getgenv() or _G)

	local WINDOW_W = config.windowWidth or 580
	local WINDOW_H = config.windowHeight or 540
	local SIDEBAR_W = config.sidebarWidth or 136
	local DEFAULT_POS = config.defaultPosition or UDim2.new(0, 16, 0.5, -270)
	local savedPos = config.savedPosition
	local guiName = config.guiName or "MaxiHub"
	local titleText = config.title or "MAXI HUB"
	local titleHintText = config.titleHint or "RightCtrl — скрыть"
	local tabs = config.tabs
	if tabs == nil then
		tabs = {
			{ name = "Главная", title = "Главная", subtitle = "" },
		}
	end
	local onSavePosition = config.onSavePosition
	local onDestroy = config.onDestroy
	local onCameraStart = config.onCameraStart
	local keyStatusText = config.keyStatusText
	local displayOrder = config.displayOrder or 999
	local currentLanguage = config.language or "ru"
	local onLanguageChange = config.onLanguageChange
	local registerLocale = config.registerLocale
	local hideHintMessage = config.hideHintText or "RightCtrl — open menu"
	local activeTabId = 1

	local COLORS = config.colors or {
		bg = Color3.fromRGB(14, 16, 18),
		sidebar = Color3.fromRGB(20, 24, 26),
		panel = Color3.fromRGB(26, 30, 33),
		accent = Color3.fromRGB(0, 198, 178),
		accentSoft = Color3.fromRGB(0, 158, 142),
		tabIdle = Color3.fromRGB(24, 30, 32),
		text = Color3.fromRGB(242, 246, 248),
		muted = Color3.fromRGB(125, 135, 142),
		green = Color3.fromRGB(52, 199, 89),
		red = Color3.fromRGB(220, 75, 75),
		line = Color3.fromRGB(40, 48, 52),
		status = Color3.fromRGB(120, 235, 215),
		toggleOff = Color3.fromRGB(42, 48, 54),
		card = Color3.fromRGB(22, 26, 29),
	}

	local contentPages = {}
	local tabButtons = {}
	local tabMeta = {}
	local pageTitle
	local pageSubtitle
	local screenGui
	local uiRoot
	local uiBody
	local titleBar
	local titleFix
	local title
	local titleHint
	local hideBtn
	local extraInputHandler

	local function addCorner(parent, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 8)
		c.Parent = parent
	end

	local function makeDraggable(frame, handle)
		local dragging = false
		local dragStart
		local startPos

		handle.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end)

		local moveConn = UserInputService.InputChanged:Connect(function(input)
			if not dragging then return end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local d = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end)

		local endConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
				if typeof(onSavePosition) == "function" then
					onSavePosition()
				end
			end
		end)

		frame.Destroying:Connect(function()
			moveConn:Disconnect()
			endConn:Disconnect()
		end)
	end

	local function switchTab(id)
		activeTabId = id
		for i, page in ipairs(contentPages) do
			page.Visible = i == id
			tabButtons[i].BackgroundColor3 = i == id and COLORS.accent or COLORS.tabIdle
			tabButtons[i].TextColor3 = i == id and COLORS.bg or COLORS.muted
		end
		if pageTitle then
			pageTitle.Text = tabMeta[id] and tabMeta[id].title or titleText
		end
		if pageSubtitle then
			pageSubtitle.Text = tabMeta[id] and tabMeta[id].subtitle or ""
		end
	end

	local function makeSectionTitle(parent, text, order, localeKey)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 20)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Parent = parent

		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 3, 0, 12)
		bar.Position = UDim2.new(0, 0, 0.5, -6)
		bar.BackgroundColor3 = COLORS.accent
		bar.BorderSizePixel = 0
		bar.Parent = row
		addCorner(bar, 2)

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -10, 1, 0)
		lbl.Position = UDim2.new(0, 10, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 11
		lbl.TextColor3 = COLORS.muted
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = string.upper(text)
		lbl.Parent = row
		if registerLocale and localeKey then
			registerLocale(lbl, localeKey)
		end
		return lbl
	end

	local function makeToggle(parent, y, label, initial, onChange, debounce, localeKey)
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 38)
		row.Position = UDim2.new(0, 0, 0, y)
		row.BackgroundColor3 = COLORS.panel
		row.BorderSizePixel = 0
		row.Text = ""
		row.AutoButtonColor = false
		row.Parent = parent
		addCorner(row, 8)

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -56, 1, 0)
		name.Position = UDim2.new(0, 12, 0, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Gotham
		name.TextSize = 13
		name.TextColor3 = COLORS.text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = label
		name.Parent = row
		if registerLocale and localeKey then
			registerLocale(name, localeKey)
		end

		local track = Instance.new("Frame")
		track.Size = UDim2.new(0, 40, 0, 20)
		track.Position = UDim2.new(1, -48, 0.5, -10)
		track.BackgroundColor3 = initial and COLORS.accent or COLORS.toggleOff
		track.BorderSizePixel = 0
		track.Parent = row
		addCorner(track, 10)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 16, 0, 16)
		knob.Position = initial and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
		knob.BackgroundColor3 = COLORS.text
		knob.BorderSizePixel = 0
		knob.Parent = track
		addCorner(knob, 8)

		local state = initial
		local lastClick = 0

		local function paint()
			track.BackgroundColor3 = state and COLORS.accent or COLORS.toggleOff
			TweenService:Create(knob, TweenInfo.new(0.12), {
				Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
			}):Play()
		end

		local function setState(value, silent)
			state = value
			paint()
			if not silent and onChange then
				onChange(state)
			end
		end

		row.MouseButton1Click:Connect(function()
			if debounce and tick() - lastClick < debounce then return end
			lastClick = tick()
			setState(not state)
		end)

		paint()
		return setState, function() return state end
	end

	local function makeSlider(parent, y, label, min, max, initial, onChange, localeKey)
		local box = Instance.new("Frame")
		box.Size = UDim2.new(1, 0, 0, 52)
		box.Position = UDim2.new(0, 0, 0, y)
		box.BackgroundColor3 = COLORS.panel
		box.BorderSizePixel = 0
		box.Parent = parent
		addCorner(box, 8)

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.65, 0, 0, 20)
		name.Position = UDim2.new(0, 12, 0, 6)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Gotham
		name.TextSize = 12
		name.TextColor3 = COLORS.text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = label
		name.Parent = box
		if registerLocale and localeKey then
			registerLocale(name, localeKey)
		end

		local valueLbl = Instance.new("TextLabel")
		valueLbl.Size = UDim2.new(0.35, -12, 0, 20)
		valueLbl.Position = UDim2.new(0.65, 0, 0, 6)
		valueLbl.BackgroundTransparency = 1
		valueLbl.Font = Enum.Font.GothamBold
		valueLbl.TextSize = 12
		valueLbl.TextColor3 = COLORS.accent
		valueLbl.TextXAlignment = Enum.TextXAlignment.Right
		valueLbl.Parent = box

		local track = Instance.new("TextButton")
		track.Size = UDim2.new(1, -24, 0, 8)
		track.Position = UDim2.new(0, 12, 1, -18)
		track.BackgroundColor3 = COLORS.line
		track.BorderSizePixel = 0
		track.Text = ""
		track.AutoButtonColor = false
		track.Parent = box
		addCorner(track, 4)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = COLORS.accent
		fill.BorderSizePixel = 0
		fill.Parent = track
		addCorner(fill, 4)

		local val = initial
		local function paint()
			local alpha = (val - min) / math.max(max - min, 0.001)
			alpha = math.clamp(alpha, 0, 1)
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			local decimals = (max - min) <= 3 and 1 or 0
			valueLbl.Text = decimals == 0 and tostring(math.floor(val)) or string.format("%.1f", val)
		end

		local function setFromX(x)
			local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			val = min + (max - min) * rel
			val = math.floor(val * 10 + 0.5) / 10
			paint()
			onChange(val)
		end

		track.MouseButton1Down:Connect(function(x)
			setFromX(x)
			local conn
			conn = UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					setFromX(input.Position.X)
				end
			end)
			local endConn
			endConn = UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					conn:Disconnect()
					endConn:Disconnect()
				end
			end)
		end)

		paint()
		return function(v) val = v; paint() end
	end

	local function makeScrollPage(parent)
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.new(1, 0, 1, 0)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 4
		scroll.ScrollBarImageColor3 = COLORS.accent
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.Parent = parent

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = scroll

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 12)
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = scroll

		return scroll
	end

	local function makeListWrap(scroll)
		local wrap = Instance.new("Frame")
		wrap.Size = UDim2.new(1, 0, 0, 0)
		wrap.AutomaticSize = Enum.AutomaticSize.Y
		wrap.BackgroundTransparency = 1
		wrap.Parent = scroll
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.Parent = wrap
		return wrap
	end

	local function makeFlowPanel(parent, title, width, height, posX, posY, bodyOffsetY, localeKey)
		local panel = Instance.new("Frame")
		panel.Size = UDim2.new(0, width, 0, height)
		panel.Position = UDim2.new(0, posX or 0, 0, posY or 0)
		panel.BackgroundColor3 = COLORS.card
		panel.BorderSizePixel = 0
		panel.Parent = parent
		addCorner(panel, 10)

		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.line
		stroke.Thickness = 1
		stroke.Transparency = 0.35
		stroke.Parent = panel

		local head = Instance.new("TextLabel")
		head.Size = UDim2.new(1, -20, 0, 22)
		head.Position = UDim2.new(0, 10, 0, 10)
		head.BackgroundTransparency = 1
		head.Font = Enum.Font.GothamBold
		head.TextSize = 12
		head.TextColor3 = COLORS.text
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.Text = title
		head.Parent = panel
		if registerLocale and localeKey then
			registerLocale(head, localeKey)
		end

		local bodyY = bodyOffsetY or 36
		local body = Instance.new("Frame")
		body.Size = UDim2.new(1, -16, 1, -bodyY - 8)
		body.Position = UDim2.new(0, 8, 0, bodyY)
		body.BackgroundTransparency = 1
		body.Parent = panel

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = body

		return body
	end

	local function makeStatRow(parent, label, layoutOrder, localeKey)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder = layoutOrder or 0
		row.Parent = parent

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.55, 0, 1, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Gotham
		name.TextSize = 11
		name.TextColor3 = COLORS.muted
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = label
		name.Parent = row
		if registerLocale and localeKey then
			registerLocale(name, localeKey)
		end

		local value = Instance.new("TextLabel")
		value.Size = UDim2.new(0.45, -4, 1, 0)
		value.Position = UDim2.new(0.55, 0, 0, 0)
		value.BackgroundTransparency = 1
		value.Font = Enum.Font.GothamBold
		value.TextSize = 11
		value.TextColor3 = COLORS.text
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Text = "—"
		value.Parent = row

		return value
	end

	local function makeFlowToggle(parent, label, initial, onChange, layoutOrder, debounce, localeKey)
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Text = ""
		row.AutoButtonColor = false
		row.LayoutOrder = layoutOrder or 0
		row.Parent = parent

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -54, 1, 0)
		name.Position = UDim2.new(0, 4, 0, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Gotham
		name.TextSize = 12
		name.TextColor3 = COLORS.text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = label
		name.Parent = row
		if registerLocale and localeKey then
			registerLocale(name, localeKey)
		end

		local track = Instance.new("Frame")
		track.Size = UDim2.new(0, 44, 0, 22)
		track.Position = UDim2.new(1, -48, 0.5, -11)
		track.BackgroundColor3 = initial and COLORS.accent or COLORS.toggleOff
		track.BorderSizePixel = 0
		track.Parent = row
		addCorner(track, 11)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 18, 0, 18)
		knob.Position = initial and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
		knob.BackgroundColor3 = COLORS.text
		knob.BorderSizePixel = 0
		knob.Parent = track
		addCorner(knob, 9)

		local state = initial
		local lastClick = 0

		local function paint()
			track.BackgroundColor3 = state and COLORS.accent or COLORS.toggleOff
			TweenService:Create(knob, TweenInfo.new(0.12), {
				Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
			}):Play()
		end

		local function setState(value, silent)
			state = value
			paint()
			if not silent and onChange then
				onChange(state)
			end
		end

		row.MouseButton1Click:Connect(function()
			if debounce and tick() - lastClick < debounce then return end
			lastClick = tick()
			setState(not state)
		end)

		paint()
		return setState, function() return state end
	end

	-- ===== СБОРКА ОБОЛОЧКИ (окно + сайдбар + вкладки) =====
	genv._MaxiHubGuiRegistry = genv._MaxiHubGuiRegistry or {}
	genv._MaxiHubInputConn = genv._MaxiHubInputConn or {}

	local prevGui = genv._MaxiHubGuiRegistry[guiName]
	if prevGui then
		pcall(function()
			if typeof(prevGui) == "Instance" and prevGui.Parent then
				prevGui:Destroy()
			end
		end)
		genv._MaxiHubGuiRegistry[guiName] = nil
	end

	local prevInput = genv._MaxiHubInputConn[guiName]
	if prevInput then
		pcall(function() prevInput:Disconnect() end)
		genv._MaxiHubInputConn[guiName] = nil
	end

	local oldGui = playerGui:FindFirstChild(guiName)
	if oldGui then oldGui:Destroy() end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = guiName
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = displayOrder
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui
	genv._MaxiHubGuiRegistry[guiName] = screenGui

	if typeof(onCameraStart) == "function" then
		pcall(onCameraStart)
	end

	screenGui.Destroying:Connect(function()
		genv._MaxiHubGuiRegistry[guiName] = nil
		local conn = genv._MaxiHubInputConn[guiName]
		if conn then
			pcall(function() conn:Disconnect() end)
			genv._MaxiHubInputConn[guiName] = nil
		end
		if typeof(onDestroy) == "function" then
			pcall(onDestroy)
		end
	end)

	uiRoot = Instance.new("Frame")
	uiRoot.Size = UDim2.new(0, WINDOW_W, 0, WINDOW_H)
	uiRoot.BackgroundColor3 = COLORS.bg
	uiRoot.BorderSizePixel = 0
	uiRoot.Active = true
	uiRoot.Parent = screenGui
	uiRoot.Position = savedPos or DEFAULT_POS
	uiRoot.ClipsDescendants = true
	addCorner(uiRoot, 12)

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = COLORS.accent
	rootStroke.Thickness = 1.5
	rootStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rootStroke.Parent = uiRoot

	titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 42)
	titleBar.BackgroundColor3 = COLORS.panel
	titleBar.BorderSizePixel = 0
	titleBar.Active = true
	titleBar.Parent = uiRoot
	addCorner(titleBar, 12)

	titleFix = Instance.new("Frame")
	titleFix.Size = UDim2.new(1, 0, 0, 10)
	titleFix.Position = UDim2.new(0, 0, 1, -10)
	titleFix.BackgroundColor3 = COLORS.panel
	titleFix.BorderSizePixel = 0
	titleFix.Parent = titleBar

	title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -140, 0, 22)
	title.Position = UDim2.new(0, 14, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = COLORS.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = titleText
	title.Parent = titleBar

	titleHint = Instance.new("TextLabel")
	titleHint.Size = UDim2.new(1, -140, 0, 12)
	titleHint.Position = UDim2.new(0, 14, 1, -14)
	titleHint.BackgroundTransparency = 1
	titleHint.Font = Enum.Font.Gotham
	titleHint.TextSize = 9
	titleHint.TextColor3 = COLORS.muted
	titleHint.TextXAlignment = Enum.TextXAlignment.Left
	titleHint.Text = titleHintText
	titleHint.Parent = titleBar

	local langRu = Instance.new("TextButton")
	langRu.Size = UDim2.new(0, 28, 0, 28)
	langRu.Position = UDim2.new(1, -100, 0.5, -14)
	langRu.BackgroundColor3 = COLORS.tabIdle
	langRu.BorderSizePixel = 0
	langRu.Font = Enum.Font.GothamBold
	langRu.TextSize = 14
	langRu.Text = "🇷🇺"
	langRu.AutoButtonColor = false
	langRu.Parent = titleBar
	addCorner(langRu, 6)

	local langEn = Instance.new("TextButton")
	langEn.Size = UDim2.new(0, 28, 0, 28)
	langEn.Position = UDim2.new(1, -68, 0.5, -14)
	langEn.BackgroundColor3 = COLORS.tabIdle
	langEn.BorderSizePixel = 0
	langEn.Font = Enum.Font.GothamBold
	langEn.TextSize = 14
	langEn.Text = "🇬🇧"
	langEn.AutoButtonColor = false
	langEn.Parent = titleBar
	addCorner(langEn, 6)

	local function paintLanguageButtons()
		local ruActive = currentLanguage == "ru"
		langRu.BackgroundColor3 = ruActive and COLORS.accent or COLORS.tabIdle
		langRu.TextColor3 = ruActive and COLORS.bg or COLORS.text
		langEn.BackgroundColor3 = (not ruActive) and COLORS.accent or COLORS.tabIdle
		langEn.TextColor3 = (not ruActive) and COLORS.bg or COLORS.text
	end
	paintLanguageButtons()

	langRu.MouseButton1Click:Connect(function()
		if currentLanguage == "ru" then return end
		currentLanguage = "ru"
		paintLanguageButtons()
		if typeof(onLanguageChange) == "function" then
			onLanguageChange("ru")
		end
	end)

	langEn.MouseButton1Click:Connect(function()
		if currentLanguage == "en" then return end
		currentLanguage = "en"
		paintLanguageButtons()
		if typeof(onLanguageChange) == "function" then
			onLanguageChange("en")
		end
	end)

	hideBtn = Instance.new("TextButton")
	hideBtn.Size = UDim2.new(0, 28, 0, 28)
	hideBtn.Position = UDim2.new(1, -36, 0.5, -14)
	hideBtn.BackgroundColor3 = COLORS.tabIdle
	hideBtn.BorderSizePixel = 0
	hideBtn.Font = Enum.Font.GothamBold
	hideBtn.TextSize = 16
	hideBtn.TextColor3 = COLORS.text
	hideBtn.Text = "—"
	hideBtn.AutoButtonColor = false
	hideBtn.Parent = titleBar
	addCorner(hideBtn, 6)

	uiBody = Instance.new("Frame")
	uiBody.Size = UDim2.new(1, -16, 1, -50)
	uiBody.Position = UDim2.new(0, 8, 0, 46)
	uiBody.BackgroundTransparency = 1
	uiBody.Parent = uiRoot

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
	sidebar.BackgroundColor3 = COLORS.sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Parent = uiBody
	addCorner(sidebar, 10)

	local sideTop = Instance.new("Frame")
	sideTop.Size = UDim2.new(1, 0, 1, -92)
	sideTop.BackgroundTransparency = 1
	sideTop.Parent = sidebar

	local sideLayout = Instance.new("UIListLayout")
	sideLayout.Padding = UDim.new(0, 6)
	sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sideLayout.Parent = sideTop

	local sidePad = Instance.new("UIPadding")
	sidePad.PaddingTop = UDim.new(0, 8)
	sidePad.Parent = sideTop

	local userCard = Instance.new("Frame")
	userCard.Size = UDim2.new(1, -12, 0, 80)
	userCard.Position = UDim2.new(0, 6, 1, -86)
	userCard.BackgroundColor3 = COLORS.card
	userCard.BorderSizePixel = 0
	userCard.Parent = sidebar
	addCorner(userCard, 10)

	local userStroke = Instance.new("UIStroke")
	userStroke.Color = COLORS.line
	userStroke.Thickness = 1
	userStroke.Transparency = 0.4
	userStroke.Parent = userCard

	local userAvatar = Instance.new("ImageLabel")
	userAvatar.Size = UDim2.new(0, 36, 0, 36)
	userAvatar.Position = UDim2.new(0, 8, 0.5, -18)
	userAvatar.BackgroundColor3 = COLORS.panel
	userAvatar.BorderSizePixel = 0
	userAvatar.Parent = userCard
	addCorner(userAvatar, 18)

	local userName = Instance.new("TextLabel")
	userName.Size = UDim2.new(1, -54, 0, 18)
	userName.Position = UDim2.new(0, 50, 0, 16)
	userName.BackgroundTransparency = 1
	userName.Font = Enum.Font.GothamBold
	userName.TextSize = 11
	userName.TextColor3 = COLORS.text
	userName.TextXAlignment = Enum.TextXAlignment.Left
	userName.TextTruncate = Enum.TextTruncate.AtEnd
	userName.Text = player.DisplayName
	userName.Parent = userCard

	local userKey = Instance.new("TextLabel")
	userKey.Size = UDim2.new(1, -54, 0, 28)
	userKey.Position = UDim2.new(0, 50, 0, 34)
	userKey.BackgroundTransparency = 1
	userKey.Font = Enum.Font.Gotham
	userKey.TextSize = 9
	userKey.TextColor3 = COLORS.muted
	userKey.TextXAlignment = Enum.TextXAlignment.Left
	userKey.TextYAlignment = Enum.TextYAlignment.Top
	userKey.TextWrapped = true
	if typeof(keyStatusText) == "function" then
		userKey.Text = keyStatusText() or "Доступ не оплачен"
	else
		userKey.Visible = false
		userName.Position = UDim2.new(0, 50, 0.5, -9)
	end
	userKey.Parent = userCard

	task.spawn(function()
		local ok, thumb = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and thumb then
			userAvatar.Image = thumb
		end
		if typeof(keyStatusText) == "function" then
			userKey.Text = keyStatusText() or "Доступ не оплачен"
		end
	end)

	local contentOffset = SIDEBAR_W + 10
	local contentHost = Instance.new("Frame")
	contentHost.Size = UDim2.new(1, -(contentOffset + 2), 1, 0)
	contentHost.Position = UDim2.new(0, contentOffset, 0, 0)
	contentHost.BackgroundTransparency = 1
	contentHost.ClipsDescendants = true
	contentHost.Parent = uiBody

	local contentHeader = Instance.new("Frame")
	contentHeader.Size = UDim2.new(1, 0, 0, 48)
	contentHeader.BackgroundTransparency = 1
	contentHeader.Parent = contentHost

	pageTitle = Instance.new("TextLabel")
	pageTitle.Size = UDim2.new(1, -8, 0, 22)
	pageTitle.BackgroundTransparency = 1
	pageTitle.Font = Enum.Font.GothamBold
	pageTitle.TextSize = 16
	pageTitle.TextColor3 = COLORS.text
	pageTitle.TextXAlignment = Enum.TextXAlignment.Left
	pageTitle.Text = tabs[1] and tabs[1].title or "Главная"
	pageTitle.Parent = contentHeader

	pageSubtitle = Instance.new("TextLabel")
	pageSubtitle.Size = UDim2.new(1, -8, 0, 16)
	pageSubtitle.Position = UDim2.new(0, 0, 0, 24)
	pageSubtitle.BackgroundTransparency = 1
	pageSubtitle.Font = Enum.Font.Gotham
	pageSubtitle.TextSize = 10
	pageSubtitle.TextColor3 = COLORS.muted
	pageSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	pageSubtitle.Text = tabs[1] and tabs[1].subtitle or ""
	pageSubtitle.Parent = contentHeader

	local pagesHost = Instance.new("Frame")
	pagesHost.Size = UDim2.new(1, 0, 1, -52)
	pagesHost.Position = UDim2.new(0, 0, 0, 52)
	pagesHost.BackgroundTransparency = 1
	pagesHost.ClipsDescendants = true
	pagesHost.Parent = contentHost

	local function registerTab(def)
		local i = #tabButtons + 1
		local tabDef = {
			name = def.name or ("Tab " .. i),
			title = def.title or def.name or ("Tab " .. i),
			subtitle = def.subtitle or "",
		}
		tabMeta[i] = tabDef

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -16, 0, 34)
		btn.BackgroundColor3 = i == 1 and COLORS.accent or COLORS.tabIdle
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 11
		btn.TextColor3 = i == 1 and COLORS.bg or COLORS.muted
		btn.Text = tabDef.name
		btn.AutoButtonColor = false
		btn.LayoutOrder = i
		btn.Parent = sideTop
		addCorner(btn, 8)
		tabButtons[i] = btn

		local page = Instance.new("Frame")
		page.Size = UDim2.new(1, 0, 1, 0)
		page.BackgroundTransparency = 1
		page.Visible = (i == 1)
		page.Parent = pagesHost
		contentPages[i] = page

		btn.MouseButton1Click:Connect(function()
			switchTab(i)
		end)

		return { Page = page, Index = i }
	end

	for _, def in ipairs(tabs) do
		registerTab(def)
	end

	local ui = {
		COLORS = COLORS,
		screenGui = screenGui,
		uiRoot = uiRoot,
		uiBody = uiBody,
		contentPages = contentPages,
		tabButtons = tabButtons,
		pageTitle = pageTitle,
		pageSubtitle = pageSubtitle,
		userKey = userKey,
		addCorner = addCorner,
		switchTab = switchTab,
		makeSectionTitle = makeSectionTitle,
		makeToggle = makeToggle,
		makeSlider = makeSlider,
		makeScrollPage = makeScrollPage,
		makeListWrap = makeListWrap,
		makeFlowPanel = makeFlowPanel,
		makeStatRow = makeStatRow,
		makeFlowToggle = makeFlowToggle,
		makeDraggable = makeDraggable,
	}

	function ui.NewFlowPanel(_, parent, title, width, height, posX, posY, bodyOffsetY)
		return makeFlowPanel(parent, title, width, height, posX, posY, bodyOffsetY)
	end

	function ui.NewFlowToggle(_, parent, label, initial, onChange, layoutOrder, debounce)
		return makeFlowToggle(parent, label, initial, onChange, layoutOrder, debounce)
	end

	function ui.NewToggle(_, parent, y, label, initial, onChange, debounce)
		return makeToggle(parent, y, label, initial, onChange, debounce)
	end

	function ui.NewSlider(_, parent, y, label, min, max, initial, onChange)
		return makeSlider(parent, y, label, min, max, initial, onChange)
	end

	function ui.NewScrollPage(_, parent)
		return makeScrollPage(parent)
	end

	function ui.NewListWrap(_, scroll)
		return makeListWrap(scroll)
	end

	function ui.NewSectionTitle(_, parent, text, order)
		return makeSectionTitle(parent, text, order)
	end

	function ui.NewStatRow(_, parent, label, layoutOrder)
		return makeStatRow(parent, label, layoutOrder)
	end

	function ui.NewTab(name, subtitleOrDef)
		local def
		if typeof(name) == "table" then
			def = name
		elseif typeof(subtitleOrDef) == "table" then
			def = subtitleOrDef
			def.name = def.name or name
		else
			def = {
				name = name,
				title = name,
				subtitle = subtitleOrDef or "",
			}
		end
		return registerTab(def)
	end

	function ui.ToggleUI()
		if uiRoot then
			uiRoot.Visible = not uiRoot.Visible
		end
	end

	function ui.Destroy()
		if screenGui and screenGui.Parent then
			screenGui:Destroy()
		end
		genv._MaxiHubGuiRegistry[guiName] = nil
		local conn = genv._MaxiHubInputConn[guiName]
		if conn then
			pcall(function() conn:Disconnect() end)
			genv._MaxiHubInputConn[guiName] = nil
		end
	end

	local function showHideHintOnce()
		local hideHintKey = "MaxiHubHideHint_" .. guiName
		if genv[hideHintKey] then return end
		genv[hideHintKey] = true

		local toast = Instance.new("TextLabel")
		toast.Name = "HideHint"
		toast.AnchorPoint = Vector2.new(0.5, 0)
		toast.Size = UDim2.new(0, 240, 0, 22)
		toast.Position = UDim2.new(0.5, 0, 0, 50)
		toast.BackgroundTransparency = 1
		toast.BorderSizePixel = 0
		toast.Font = Enum.Font.Gotham
		toast.TextSize = 11
		toast.TextColor3 = COLORS.muted
		toast.Text = hideHintMessage
		toast.TextTransparency = 1
		toast.ZIndex = 20
		toast.Parent = screenGui

		TweenService:Create(toast, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0.35,
		}):Play()

		task.delay(3, function()
			if not toast.Parent then return end
			local fade = TweenService:Create(toast, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
			})
			fade:Play()
			fade.Completed:Connect(function()
				toast:Destroy()
			end)
		end)
	end

	function ui.finalize()
		makeDraggable(uiRoot, titleBar)

		local titleBarExpandedSize = UDim2.new(1, 0, 0, 42)
		local titleBarExpandedPos = UDim2.new(0, 0, 0, 0)
		local uiBodyExpandedSize = UDim2.new(1, -16, 1, -50)
		local uiBodyExpandedPos = UDim2.new(0, 8, 0, 46)

		local minimized = false
		local savedSize = uiRoot.Size
		hideBtn.MouseButton1Click:Connect(function()
			minimized = not minimized
			if minimized then
				savedSize = uiRoot.Size
				uiRoot.Size = UDim2.new(0, WINDOW_W, 0, 40)
				uiBody.Visible = false
				titleFix.Visible = false
				titleBar.Size = UDim2.new(1, 0, 1, 0)
				titleBar.Position = UDim2.new(0, 0, 0, 0)
				title.Size = UDim2.new(1, -140, 1, 0)
				title.Position = UDim2.new(0, 14, 0, 0)
				title.TextYAlignment = Enum.TextYAlignment.Center
				titleHint.Visible = false
				hideBtn.Text = "+"
				showHideHintOnce()
			else
				uiRoot.Size = savedSize
				uiBody.Visible = true
				titleFix.Visible = true
				titleBar.Size = titleBarExpandedSize
				titleBar.Position = titleBarExpandedPos
				title.Size = UDim2.new(1, -140, 0, 22)
				title.Position = UDim2.new(0, 14, 0, 6)
				title.TextYAlignment = Enum.TextYAlignment.Center
				titleHint.Visible = true
				uiBody.Size = uiBodyExpandedSize
				uiBody.Position = uiBodyExpandedPos
				hideBtn.Text = "—"
			end
		end)

		genv._MaxiHubInputConn[guiName] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then return end

			if input.KeyCode == Enum.KeyCode.RightControl then
				local willHide = uiRoot.Visible
				uiRoot.Visible = not uiRoot.Visible
				if willHide then
					showHideHintOnce()
				end
				return
			end

			if typeof(extraInputHandler) == "function" then
				extraInputHandler(input, gameProcessed)
			end
		end)

		switchTab(1)
	end

	function ui.onInputBegan(handler)
		extraInputHandler = handler
	end

	ui.OnInputBegan = ui.onInputBegan
	ui.Finalize = ui.finalize

	function ui.setLanguage(lang)
		currentLanguage = (type(lang) == "string" and lang:lower() == "en") and "en" or "ru"
		paintLanguageButtons()
	end

	function ui.setTitleHint(text)
		if titleHint then
			titleHint.Text = text or ""
		end
	end

	function ui.setHideHintText(text)
		hideHintMessage = text or hideHintMessage
	end

	function ui.refreshTabLabels(defs)
		if type(defs) ~= "table" then return end
		for i, def in ipairs(defs) do
			if tabMeta[i] and tabButtons[i] then
				tabMeta[i].name = def.name or tabMeta[i].name
				tabMeta[i].title = def.title or def.name or tabMeta[i].title
				tabMeta[i].subtitle = def.subtitle or ""
				tabButtons[i].Text = tabMeta[i].name
			end
		end
		switchTab(activeTabId)
	end

	return ui
end

function MaxiHubUI.CreateLib(title, options)
	options = options or {}
	if typeof(title) == "string" then
		options.title = options.title or title
	end
	return MaxiHubUI.create(options)
end

MaxiHubUI.CreateWindow = MaxiHubUI.CreateLib

return MaxiHubUI
