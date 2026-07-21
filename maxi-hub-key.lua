--[[ MAXI HUB · maxi-hub-key.lua — см. также maxi-hub-key.lua в корне проекта ]]

local HttpService = game:GetService("HttpService")

local MaxiHubKey = {}

local function defaultHttpRequest(opts)
	if typeof(request) == "function" then
		return request(opts)
	end
	if syn and syn.request then
		return syn.request(opts)
	end
	if http and http.request then
		return http.request(opts)
	end
	return nil
end

local function canUseFiles()
	return typeof(writefile) == "function"
		and typeof(readfile) == "function"
		and typeof(isfile) == "function"
end

function MaxiHubKey.create(config)
	config = config or {}

	local WEBHOOK = config.webhook or ""
	local TELEGRAM = config.telegram or "https://t.me/MAXI_HUB"
	local CACHE_FILE = config.cacheFile or "maxi-hub-key-cache.json"
	local SECRET = config.secret or "MAXIHUB_KEY_TEST_V1"
	local CHARSET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	local REQUEST_COOLDOWN = config.requestCooldown or 60

	local player = config.player
	local playerGui = config.playerGui
	local httpRequest = config.httpRequest or defaultHttpRequest
	local canUseConfigFile = config.canUseFiles or canUseFiles
	local onGranted = config.onGranted
	local getActivationExtraFields = config.getActivationExtraFields

	local keyGateGui = nil

	local function formatTime(ts)
		return os.date("%d.%m.%Y %H:%M", ts)
	end

	local function sig2(prefix, expHour)
		local h = 0
		local s = prefix .. tostring(expHour) .. SECRET
		for i = 1, #s do
			h = (h * 31 + string.byte(s, i)) % 1024
		end
		local a = (h % 32) + 1
		local b = (math.floor(h / 32) % 32) + 1
		return CHARSET:sub(a, a) .. CHARSET:sub(b, b)
	end

	local function generateKey()
		local expiresAt = os.time() + 86400
		local expHour = math.floor(expiresAt / 3600)
		local prefix = ""
		for i = 1, 5 do
			local j = math.random(1, #CHARSET)
			prefix = prefix .. CHARSET:sub(j, j)
		end
		return prefix .. sig2(prefix, expHour), expiresAt
	end

	local function verifyKey(rawKey)
		if type(rawKey) ~= "string" then
			return false, "Введи ключ"
		end

		local key = rawKey:upper():gsub("%s+", "")
		if #key ~= 7 then
			return false, "Ключ — 7 символов"
		end

		local prefix = key:sub(1, 5)
		local sign = key:sub(6, 7)

		for ch in key:gmatch(".") do
			if not CHARSET:find(ch, 1, true) then
				return false, "Недопустимые символы"
			end
		end

		local nowH = math.floor(os.time() / 3600)
		for h = nowH - 72, nowH + 72 do
			if sig2(prefix, h) == sign then
				local expiresAt = (h + 1) * 3600
				if os.time() >= expiresAt then
					return false, "Ключ истёк"
				end
				return true, "OK", expiresAt
			end
		end

		return false, "Неверный ключ"
	end

	local function readCache()
		if not canUseConfigFile() or not isfile(CACHE_FILE) then return nil end
		local ok, raw = pcall(readfile, CACHE_FILE)
		if not ok or not raw or raw == "" then return nil end
		local ok2, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok2 or type(data) ~= "table" then return nil end
		return data
	end

	local function writeCache(key, expiresAt)
		if not canUseConfigFile() or not player then return end
		pcall(writefile, CACHE_FILE, HttpService:JSONEncode({
			key = key,
			expiresAt = expiresAt,
			userId = player.UserId,
			savedAt = os.time(),
		}))
	end

	local function clearCache()
		if not canUseConfigFile() then return end
		pcall(writefile, CACHE_FILE, "{}")
	end

	local function hasAccess()
		local cache = readCache()
		if not cache or not cache.key or not cache.expiresAt then
			return false
		end
		if os.time() >= cache.expiresAt then
			clearCache()
			return false
		end
		local ok, _, verifyExpires = verifyKey(cache.key)
		if not ok then
			clearCache()
			return false
		end
		if verifyExpires and os.time() >= verifyExpires then
			clearCache()
			return false
		end
		return true
	end

	local function requestKey()
		if not WEBHOOK or WEBHOOK == "" then
			return nil, "Webhook не настроен"
		end
		if not player then
			return nil, "Нет player"
		end

		math.randomseed(os.time() + player.UserId)
		local key, expiresAt = generateKey()

		local sent = false
		pcall(function()
			httpRequest({
				Url = WEBHOOK,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					embeds = {
						{
							title = "Запрос ключа",
							color = 16755200,
							fields = {
								{ name = "Ключ", value = key, inline = true },
								{ name = "Действует до", value = formatTime(expiresAt), inline = true },
								{ name = "Игрок", value = player.Name, inline = true },
								{ name = "DisplayName", value = player.DisplayName, inline = true },
								{ name = "UserId", value = tostring(player.UserId), inline = true },
								{ name = "JobId", value = game.JobId, inline = false },
								{ name = "Контакт", value = TELEGRAM, inline = false },
							},
							footer = { text = "MAXI HUB · выдай ключ в Telegram" },
							timestamp = DateTime.now():ToIsoDate(),
						},
					},
				}),
			})
			sent = true
		end)

		if sent then
			return key, expiresAt
		end
		return nil, "Не удалось отправить"
	end

	local function logActivation(key, expiresAt)
		if not WEBHOOK or WEBHOOK == "" then return end
		local fields = {
			{ name = "Ключ", value = key, inline = true },
			{ name = "Игрок", value = player.Name, inline = true },
			{ name = "UserId", value = tostring(player.UserId), inline = true },
			{ name = "До", value = formatTime(expiresAt), inline = false },
		}
		if typeof(getActivationExtraFields) == "function" then
			for _, field in ipairs(getActivationExtraFields()) do
				table.insert(fields, field)
			end
		end
		pcall(function()
			httpRequest({
				Url = WEBHOOK,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					embeds = {
						{
							title = "Ключ активирован",
							color = 5763719,
							fields = fields,
							footer = { text = "MAXI HUB" },
							timestamp = DateTime.now():ToIsoDate(),
						},
					},
				}),
			})
		end)
	end

	local function destroyGate()
		if keyGateGui then
			keyGateGui:Destroy()
			keyGateGui = nil
		end
		if playerGui then
			local old = playerGui:FindFirstChild("MaxiHubKeyGate")
			if old then old:Destroy() end
		end
	end

	local function getKeyStatusText()
		local cache = readCache()
		if cache and cache.expiresAt and os.time() < cache.expiresAt then
			return "Ключ: до " .. formatTime(cache.expiresAt)
		end
		return "Ключ: не активирован"
	end

	local function showGate()
		if not playerGui then
			warn("[MAXI HUB KEY] playerGui не задан")
			return
		end

		destroyGate()

		local KEY_COLORS = {
			bg = Color3.fromRGB(14, 16, 18),
			panel = Color3.fromRGB(26, 30, 33),
			accent = Color3.fromRGB(0, 198, 178),
			text = Color3.fromRGB(242, 246, 248),
			muted = Color3.fromRGB(125, 135, 142),
			green = Color3.fromRGB(52, 199, 89),
			red = Color3.fromRGB(220, 75, 75),
		}

		local function corner(parent, r)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, r or 8)
			c.Parent = parent
		end

		keyGateGui = Instance.new("ScreenGui")
		keyGateGui.Name = "MaxiHubKeyGate"
		keyGateGui.ResetOnSpawn = false
		keyGateGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		keyGateGui.DisplayOrder = 1000
		keyGateGui.IgnoreGuiInset = true
		keyGateGui.Parent = playerGui

		local root = Instance.new("Frame")
		root.Size = UDim2.new(0, 360, 0, 300)
		root.Position = UDim2.new(0.5, -180, 0.5, -150)
		root.BackgroundColor3 = KEY_COLORS.bg
		root.BorderSizePixel = 0
		root.Parent = keyGateGui
		corner(root, 12)

		local stroke = Instance.new("UIStroke")
		stroke.Color = KEY_COLORS.accent
		stroke.Thickness = 1.5
		stroke.Parent = root

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -24, 0, 28)
		title.Position = UDim2.new(0, 12, 0, 14)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextColor3 = KEY_COLORS.text
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = "MAXI HUB"
		title.Parent = root

		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(1, -24, 0, 40)
		hint.Position = UDim2.new(0, 12, 0, 42)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.Gotham
		hint.TextSize = 11
		hint.TextColor3 = KEY_COLORS.muted
		hint.TextWrapped = true
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.Text = "Нужен ключ доступа.\nПолучить: Telegram " .. TELEGRAM:gsub("https://", "")
		hint.Parent = root

		local keyBox = Instance.new("TextBox")
		keyBox.Size = UDim2.new(1, -24, 0, 38)
		keyBox.Position = UDim2.new(0, 12, 0, 92)
		keyBox.BackgroundColor3 = KEY_COLORS.panel
		keyBox.BorderSizePixel = 0
		keyBox.ClearTextOnFocus = false
		keyBox.Font = Enum.Font.GothamBold
		keyBox.TextSize = 18
		keyBox.TextColor3 = KEY_COLORS.text
		keyBox.PlaceholderText = "XXXXXXX"
		keyBox.PlaceholderColor3 = KEY_COLORS.muted
		keyBox.Parent = root
		corner(keyBox, 8)

		local requestBtn = Instance.new("TextButton")
		requestBtn.Size = UDim2.new(1, -24, 0, 34)
		requestBtn.Position = UDim2.new(0, 12, 0, 138)
		requestBtn.BackgroundColor3 = KEY_COLORS.panel
		requestBtn.BorderSizePixel = 0
		requestBtn.Font = Enum.Font.GothamBold
		requestBtn.TextSize = 12
		requestBtn.TextColor3 = KEY_COLORS.accent
		requestBtn.Text = "Запросить ключ"
		requestBtn.AutoButtonColor = false
		requestBtn.Parent = root
		corner(requestBtn, 8)

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Size = UDim2.new(1, -24, 0, 36)
		statusLabel.Position = UDim2.new(0, 12, 1, -44)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.Gotham
		statusLabel.TextSize = 11
		statusLabel.TextColor3 = KEY_COLORS.muted
		statusLabel.TextWrapped = true
		statusLabel.TextXAlignment = Enum.TextXAlignment.Left
		statusLabel.TextYAlignment = Enum.TextYAlignment.Top
		statusLabel.Text = ""
		statusLabel.Parent = root

		local activateBtn = Instance.new("TextButton")
		activateBtn.Size = UDim2.new(1, -24, 0, 38)
		activateBtn.Position = UDim2.new(0, 12, 0, 182)
		activateBtn.BackgroundColor3 = KEY_COLORS.accent
		activateBtn.BorderSizePixel = 0
		activateBtn.Font = Enum.Font.GothamBold
		activateBtn.TextSize = 13
		activateBtn.TextColor3 = KEY_COLORS.bg
		activateBtn.Text = "Активировать"
		activateBtn.AutoButtonColor = false
		activateBtn.Parent = root
		corner(activateBtn, 8)

		local activating = false
		local requestBusy = false
		local requestCooldownLeft = 0
		local cooldownRunId = 0

		local function updateRequestBtn()
			if requestCooldownLeft > 0 then
				requestBtn.Text = string.format("Запросить ключ (%dс)", math.ceil(requestCooldownLeft))
				requestBtn.TextColor3 = KEY_COLORS.muted
			else
				requestBtn.Text = "Запросить ключ"
				requestBtn.TextColor3 = KEY_COLORS.accent
			end
		end

		local function startRequestCooldown()
			requestCooldownLeft = REQUEST_COOLDOWN
			updateRequestBtn()
			cooldownRunId += 1
			local myRun = cooldownRunId
			task.spawn(function()
				while myRun == cooldownRunId and requestCooldownLeft > 0 and keyGateGui and keyGateGui.Parent do
					task.wait(1)
					if myRun ~= cooldownRunId then return end
					requestCooldownLeft -= 1
					updateRequestBtn()
				end
				if myRun == cooldownRunId then
					requestCooldownLeft = 0
					updateRequestBtn()
				end
			end)
		end

		requestBtn.MouseButton1Click:Connect(function()
			if requestBusy or requestCooldownLeft > 0 then return end
			requestBusy = true
			statusLabel.Text = "Генерация и отправка..."
			statusLabel.TextColor3 = KEY_COLORS.muted
			task.spawn(function()
				local key, errOrExpires = requestKey()
				requestBusy = false
				if not key then
					statusLabel.Text = errOrExpires or "Не удалось отправить"
					statusLabel.TextColor3 = KEY_COLORS.red
					return
				end
				statusLabel.Text = "Запрос отправлен. Жди ключ в Telegram."
				statusLabel.TextColor3 = KEY_COLORS.green
				startRequestCooldown()
			end)
		end)

		local function tryActivate()
			if activating then return end
			local key = keyBox.Text
			if key == "" then
				statusLabel.Text = "Введи ключ"
				statusLabel.TextColor3 = KEY_COLORS.red
				return
			end

			activating = true
			statusLabel.Text = "Проверка..."
			statusLabel.TextColor3 = KEY_COLORS.muted

			local ok, msg, expiresAt = verifyKey(key)
			if not ok then
				statusLabel.Text = msg
				statusLabel.TextColor3 = KEY_COLORS.red
				activating = false
				return
			end

			local normalized = key:upper():gsub("%s+", "")
			writeCache(normalized, expiresAt)
			logActivation(normalized, expiresAt)
			activating = false
			destroyGate()

			if typeof(onGranted) == "function" then
				task.defer(function()
					local grantedOk, err = pcall(onGranted)
					if not grantedOk then
						warn("[MAXI HUB KEY] onGranted:", err)
					end
				end)
			end
		end

		activateBtn.MouseButton1Click:Connect(tryActivate)
		keyBox.FocusLost:Connect(function(enter)
			if enter then tryActivate() end
		end)
	end

	return {
		hasAccess = hasAccess,
		showGate = showGate,
		destroyGate = destroyGate,
		readCache = readCache,
		writeCache = writeCache,
		clearCache = clearCache,
		verifyKey = verifyKey,
		generateKey = generateKey,
		requestKey = requestKey,
		formatTime = formatTime,
		getKeyStatusText = getKeyStatusText,
	}
end

return MaxiHubKey
