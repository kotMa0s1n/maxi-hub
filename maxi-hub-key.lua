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

	local PURCHASE_MESSAGE = config.purchaseMessage
		or "Доступ не оплачен.\nКупить доступ в Telegram:"

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
		return "Доступ не оплачен"
	end

	local function showPurchaseNotice(onContinue)
		if hasAccess() then
			if typeof(onContinue) == "function" then
				task.defer(onContinue)
			end
			return
		end

		if not playerGui then
			if typeof(onContinue) == "function" then
				task.defer(onContinue)
			end
			return
		end

		destroyGate()

		local KEY_COLORS = {
			bg = Color3.fromRGB(14, 16, 18),
			panel = Color3.fromRGB(26, 30, 33),
			accent = Color3.fromRGB(0, 198, 178),
			text = Color3.fromRGB(242, 246, 248),
			muted = Color3.fromRGB(125, 135, 142),
			warning = Color3.fromRGB(255, 184, 77),
		}

		keyGateGui = Instance.new("ScreenGui")
		keyGateGui.Name = "MaxiHubKeyGate"
		keyGateGui.ResetOnSpawn = false
		keyGateGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		keyGateGui.DisplayOrder = 1000
		keyGateGui.IgnoreGuiInset = true
		keyGateGui.Parent = playerGui

		local root = Instance.new("Frame")
		root.Size = UDim2.new(0, 360, 0, 200)
		root.Position = UDim2.new(0.5, -180, 0.5, -100)
		root.BackgroundColor3 = KEY_COLORS.bg
		root.BorderSizePixel = 0
		root.Parent = keyGateGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = root

		local stroke = Instance.new("UIStroke")
		stroke.Color = KEY_COLORS.warning
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
		title.Text = "🔰MAXI HUB"
		title.Parent = root

		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(1, -24, 0, 72)
		hint.Position = UDim2.new(0, 12, 0, 44)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.Gotham
		hint.TextSize = 12
		hint.TextColor3 = KEY_COLORS.warning
		hint.TextWrapped = true
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextYAlignment = Enum.TextYAlignment.Top
		hint.Text = PURCHASE_MESSAGE .. "\n" .. TELEGRAM:gsub("https://", "")
		hint.Parent = root

		local continueBtn = Instance.new("TextButton")
		continueBtn.Size = UDim2.new(1, -24, 0, 38)
		continueBtn.Position = UDim2.new(0, 12, 1, -52)
		continueBtn.BackgroundColor3 = KEY_COLORS.accent
		continueBtn.BorderSizePixel = 0
		continueBtn.Font = Enum.Font.GothamBold
		continueBtn.TextSize = 13
		continueBtn.TextColor3 = KEY_COLORS.bg
		continueBtn.Text = "Продолжить"
		continueBtn.AutoButtonColor = false
		continueBtn.Parent = root

		local cornerBtn = Instance.new("UICorner")
		cornerBtn.CornerRadius = UDim.new(0, 8)
		cornerBtn.Parent = continueBtn

		local continued = false
		local function finish()
			if continued then return end
			continued = true
			destroyGate()
			if typeof(onContinue) == "function" then
				task.defer(onContinue)
			end
		end

		continueBtn.MouseButton1Click:Connect(finish)
		task.delay(8, finish)
	end

	return {
		hasAccess = hasAccess,
		showPurchaseNotice = showPurchaseNotice,
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
