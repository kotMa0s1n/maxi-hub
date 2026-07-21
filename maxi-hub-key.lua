--[[ MAXI HUB · maxi-hub-key.lua — Panda Key System (Pelinda V3 External) ]]

local HttpService = game:GetService("HttpService")

local MaxiHubKey = {}

local PANDA_LIB_URLS = {
	"https://api.pandauth.com/lib/external/panda-v3-external.lua",
	"https://api.pandauth.com/lib/external/v3.lua",
}

local function canUseFiles()
	return typeof(writefile) == "function"
		and typeof(readfile) == "function"
		and typeof(isfile) == "function"
end

local function safeCopy(text)
	if typeof(setclipboard) == "function" and type(text) == "string" and text ~= "" then
		pcall(setclipboard, text)
		return true
	end
	return false
end

function MaxiHubKey.create(config)
	config = config or {}

	local TELEGRAM = config.telegram or "https://t.me/MAXI_HUB"
	local CACHE_FILE = config.cacheFile or "maxi-hub-key-cache.json"
	local SAVE_KEY_PATH = config.saveKeyPath or "MAXI-HUB-key.txt"
	local PANDA_SERVICE = config.pandaService or "maxihub"
	local HUB_NAME = config.hubName or "🔰MAXI HUB"
	local MAX_RETRIES = config.maxRetries or 3
	local GET_KEY_URL = config.getKeyUrl or config.purchaseUrl or TELEGRAM
	local BUY_KEY_URL = config.buyKeyUrl or config.purchaseUrl or GET_KEY_URL
	local SILENT_MODE = config.silentMode == true
	local CACHE_GRACE_SECONDS = config.cacheGraceSeconds or 3600
	local SILENT_MAX_RETRIES = config.silentMaxRetries or 1

	local player = config.player
	local playerGui = config.playerGui
	local canUseConfigFile = config.canUseFiles or canUseFiles

	local keyGateGui = nil
	local Pelinda = nil
	local KEY_COLORS = {
		bg = Color3.fromRGB(14, 16, 18),
		card = Color3.fromRGB(20, 24, 26),
		panel = Color3.fromRGB(26, 30, 33),
		accent = Color3.fromRGB(0, 198, 178),
		accentSoft = Color3.fromRGB(0, 158, 142),
		text = Color3.fromRGB(242, 246, 248),
		muted = Color3.fromRGB(125, 135, 142),
		success = Color3.fromRGB(52, 199, 89),
		error = Color3.fromRGB(248, 113, 113),
		border = Color3.fromRGB(40, 48, 52),
		inputBg = Color3.fromRGB(14, 16, 18),
	}

	local function formatTime(ts)
		if type(ts) ~= "number" then
			return "—"
		end
		return os.date("%d.%m.%Y %H:%M", ts)
	end

	local function parseIsoExpires(iso)
		if type(iso) ~= "string" or iso == "" then
			return nil
		end
		local y, mo, d, h, mi, s = iso:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
		if not y then
			return nil
		end
		return os.time({
			year = tonumber(y),
			month = tonumber(mo),
			day = tonumber(d),
			hour = tonumber(h),
			min = tonumber(mi),
			sec = tonumber(s),
		})
	end

	local function loadPelinda()
		if Pelinda then
			return Pelinda
		end
		if typeof(game.HttpGet) ~= "function" then
			return nil
		end
		for _, url in ipairs(PANDA_LIB_URLS) do
			local ok, src = pcall(game.HttpGet, url)
			if ok and type(src) == "string" and src ~= "" then
				local chunk = loadstring(src, "@panda-v3")
				if chunk then
					local okRun, lib = pcall(chunk)
					if okRun and type(lib) == "table" then
						Pelinda = lib
						return Pelinda
					end
				end
			end
		end
		return nil
	end

	local function readSavedKey()
		if not canUseConfigFile() or not isfile(SAVE_KEY_PATH) then
			return nil
		end
		local ok, raw = pcall(readfile, SAVE_KEY_PATH)
		if not ok or type(raw) ~= "string" then
			return nil
		end
		local key = raw:gsub("%s+", "")
		if key == "" then
			return nil
		end
		return key
	end

	local function writeSavedKey(key)
		if not canUseConfigFile() or type(key) ~= "string" or key == "" then
			return
		end
		pcall(writefile, SAVE_KEY_PATH, key)
	end

	local function readCache()
		if not canUseConfigFile() or not isfile(CACHE_FILE) then
			return nil
		end
		local ok, raw = pcall(readfile, CACHE_FILE)
		if not ok or not raw or raw == "" then
			return nil
		end
		local ok2, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok2 or type(data) ~= "table" then
			return nil
		end
		return data
	end

	local function writeCache(key, expiresAt, isPremium)
		if not canUseConfigFile() or not player then
			return
		end
		pcall(writefile, CACHE_FILE, HttpService:JSONEncode({
			key = key,
			expiresAt = expiresAt,
			isPremium = isPremium == true,
			userId = player.UserId,
			savedAt = os.time(),
			validatedAt = os.time(),
			provider = "panda",
		}))
	end

	local function clearCache()
		if not canUseConfigFile() then
			return
		end
		pcall(writefile, CACHE_FILE, "{}")
	end

	local function isCacheValid(cache)
		if type(cache) ~= "table" or cache.provider ~= "panda" or not cache.key then
			return false
		end
		if cache.expiresAt and os.time() >= cache.expiresAt then
			return false
		end
		if cache.userId and player and cache.userId ~= player.UserId then
			return false
		end
		return true
	end

	local function isCacheFresh(cache)
		if not isCacheValid(cache) then
			return false
		end
		local checkedAt = cache.validatedAt or cache.savedAt or 0
		return (os.time() - checkedAt) < CACHE_GRACE_SECONDS
	end

	local function capturePandaGlobals()
		local expiresAt = nil
		if type(_G.__PELINDA_KEY_EXPIRES_AT__) == "string" then
			expiresAt = parseIsoExpires(_G.__PELINDA_KEY_EXPIRES_AT__)
		end
		local isPremium = _G.__PELINDA_IS_PREMIUM__ == true
		return expiresAt, isPremium
	end

	local function validateWithPanda(key, silent, maxRetries)
		local lib = loadPelinda()
		if not lib or type(lib.Init) ~= "function" then
			return false, "Не удалось подключиться к серверу ключей"
		end
		local trimmed = type(key) == "string" and key:gsub("%s+", "") or ""
		if trimmed == "" then
			return false, "Введи ключ"
		end
		local retries = maxRetries
		if retries == nil then
			retries = silent and SILENT_MAX_RETRIES or MAX_RETRIES
		end
		for attempt = 1, retries do
			local ok, result = pcall(lib.Init, {
				Service = PANDA_SERVICE,
				Key = trimmed,
				SilentMode = true,
			})
			if ok and result == "validated!!" then
				local expiresAt, isPremium = capturePandaGlobals()
				writeCache(trimmed, expiresAt, isPremium)
				writeSavedKey(trimmed)
				return true, "OK", expiresAt, isPremium
			elseif ok and result == "error!!" then
				if attempt < retries then
					task.wait(0.35)
				else
					return false, "Ошибка сервера ключей"
				end
			else
				return false, "Неверный или истёкший ключ"
			end
		end
		return false, "Не удалось проверить ключ"
	end

	local function verifyKey(rawKey)
		return validateWithPanda(rawKey, false)
	end

	local function hasAccess()
		local cache = readCache()
		if isCacheFresh(cache) then
			return true
		end
		return false
	end

	local function tryValidateKeyAsync(key, onDone)
		task.spawn(function()
			local ok, msg, expiresAt, isPremium = validateWithPanda(key, true, SILENT_MAX_RETRIES)
			if typeof(onDone) == "function" then
				onDone(ok, msg, expiresAt, isPremium)
			end
		end)
	end

	local function getKeyLink()
		local lib = loadPelinda()
		if lib and type(lib.GetKeyLink) == "function" then
			local ok, link = pcall(lib.GetKeyLink, { Service = PANDA_SERVICE })
			if ok and type(link) == "string" and link ~= "" then
				return link
			end
		end
		return GET_KEY_URL
	end

	local function destroyGate()
		if keyGateGui then
			keyGateGui:Destroy()
			keyGateGui = nil
		end
		if playerGui then
			local old = playerGui:FindFirstChild("MaxiHubKeyGate")
			if old then
				old:Destroy()
			end
		end
	end

	local function getKeyStatusText()
		local cache = readCache()
		if cache and cache.expiresAt and os.time() < cache.expiresAt then
			local premium = cache.isPremium and " · Premium" or ""
			return "Ключ: до " .. formatTime(cache.expiresAt) .. premium
		end
		if cache and cache.key and not cache.expiresAt then
			local premium = cache.isPremium and " · Premium" or ""
			return "Ключ активен" .. premium
		end
		return "Доступ не оплачен"
	end

	local function buildLoadingGate()
		destroyGate()
		keyGateGui = Instance.new("ScreenGui")
		keyGateGui.Name = "MaxiHubKeyGate"
		keyGateGui.ResetOnSpawn = false
		keyGateGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		keyGateGui.DisplayOrder = 1000
		keyGateGui.IgnoreGuiInset = true
		keyGateGui.Parent = playerGui

		local overlay = Instance.new("Frame")
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = KEY_COLORS.bg
		overlay.BackgroundTransparency = 0.15
		overlay.BorderSizePixel = 0
		overlay.Parent = keyGateGui

		local card = Instance.new("Frame")
		card.Size = UDim2.new(0, 280, 0, 100)
		card.Position = UDim2.new(0.5, -140, 0.5, -50)
		card.BackgroundColor3 = KEY_COLORS.card
		card.BorderSizePixel = 0
		card.Parent = overlay

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -24, 1, 0)
		label.Position = UDim2.new(0, 12, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = "Проверка ключа..."
		label.TextColor3 = KEY_COLORS.muted
		label.TextSize = 13
		label.Parent = card
	end

	local function buildAuthGate(onContinue)
		destroyGate()

		keyGateGui = Instance.new("ScreenGui")
		keyGateGui.Name = "MaxiHubKeyGate"
		keyGateGui.ResetOnSpawn = false
		keyGateGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		keyGateGui.DisplayOrder = 1000
		keyGateGui.IgnoreGuiInset = true
		keyGateGui.Parent = playerGui

		local overlay = Instance.new("Frame")
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = KEY_COLORS.bg
		overlay.BackgroundTransparency = 0.15
		overlay.BorderSizePixel = 0
		overlay.Parent = keyGateGui

		local card = Instance.new("Frame")
		card.Size = UDim2.new(0, 400, 0, 372)
		card.Position = UDim2.new(0.5, -200, 0.5, -186)
		card.BackgroundColor3 = KEY_COLORS.card
		card.BorderSizePixel = 0
		card.Parent = overlay

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 14)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = KEY_COLORS.border
		cardStroke.Thickness = 1
		cardStroke.Parent = card

		local accent = Instance.new("Frame")
		accent.Size = UDim2.new(0, 40, 0, 3)
		accent.Position = UDim2.new(0, 24, 0, 24)
		accent.BackgroundColor3 = KEY_COLORS.accent
		accent.BorderSizePixel = 0
		accent.Parent = card

		local closeBtn = Instance.new("TextButton")
		closeBtn.Position = UDim2.new(1, -36, 0, 12)
		closeBtn.Size = UDim2.new(0, 24, 0, 24)
		closeBtn.BackgroundTransparency = 1
		closeBtn.Font = Enum.Font.Gotham
		closeBtn.Text = "✕"
		closeBtn.TextColor3 = KEY_COLORS.muted
		closeBtn.TextSize = 16
		closeBtn.AutoButtonColor = false
		closeBtn.Parent = card
		closeBtn.MouseButton1Click:Connect(destroyGate)

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 24, 0, 36)
		title.Size = UDim2.new(1, -48, 0, 30)
		title.Font = Enum.Font.GothamBold
		title.Text = HUB_NAME
		title.TextColor3 = KEY_COLORS.text
		title.TextSize = 22
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = card

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.new(0, 24, 0, 68)
		sub.Size = UDim2.new(1, -48, 0, 18)
		sub.Font = Enum.Font.Gotham
		sub.Text = "Введи ключ доступа"
		sub.TextColor3 = KEY_COLORS.muted
		sub.TextSize = 12
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Parent = card

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.new(0, 24, 0, 112)
		lbl.Size = UDim2.new(1, -48, 0, 14)
		lbl.Font = Enum.Font.GothamMedium
		lbl.Text = "КЛЮЧ ДОСТУПА"
		lbl.TextColor3 = KEY_COLORS.muted
		lbl.TextSize = 10
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = card

		local inputBox = Instance.new("TextBox")
		inputBox.Position = UDim2.new(0, 24, 0, 132)
		inputBox.Size = UDim2.new(1, -48, 0, 42)
		inputBox.BackgroundColor3 = KEY_COLORS.inputBg
		inputBox.BorderSizePixel = 0
		inputBox.Font = Enum.Font.Gotham
		inputBox.PlaceholderText = "Вставь свой ключ"
		inputBox.PlaceholderColor3 = KEY_COLORS.muted
		inputBox.Text = readSavedKey() or ""
		inputBox.TextColor3 = KEY_COLORS.text
		inputBox.TextSize = 14
		inputBox.ClearTextOnFocus = false
		inputBox.TextXAlignment = Enum.TextXAlignment.Left
		inputBox.Parent = card

		local inputCorner = Instance.new("UICorner")
		inputCorner.CornerRadius = UDim.new(0, 8)
		inputCorner.Parent = inputBox

		local inputStroke = Instance.new("UIStroke")
		inputStroke.Color = KEY_COLORS.border
		inputStroke.Thickness = 1
		inputStroke.Parent = inputBox

		inputBox.Focused:Connect(function()
			inputStroke.Color = KEY_COLORS.accent
		end)
		inputBox.FocusLost:Connect(function()
			inputStroke.Color = KEY_COLORS.border
		end)

		local verifyBtn = Instance.new("TextButton")
		verifyBtn.Position = UDim2.new(0, 24, 0, 196)
		verifyBtn.Size = UDim2.new(1, -48, 0, 44)
		verifyBtn.BackgroundColor3 = KEY_COLORS.accent
		verifyBtn.BorderSizePixel = 0
		verifyBtn.Font = Enum.Font.GothamBold
		verifyBtn.Text = "Продолжить"
		verifyBtn.TextColor3 = KEY_COLORS.bg
		verifyBtn.TextSize = 14
		verifyBtn.AutoButtonColor = false
		verifyBtn.Parent = card

		local verifyCorner = Instance.new("UICorner")
		verifyCorner.CornerRadius = UDim.new(0, 8)
		verifyCorner.Parent = verifyBtn

		local buyBtn = Instance.new("TextButton")
		buyBtn.Position = UDim2.new(0, 24, 0, 252)
		buyBtn.Size = UDim2.new(1, -48, 0, 40)
		buyBtn.BackgroundColor3 = KEY_COLORS.panel
		buyBtn.BorderSizePixel = 0
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.Text = "Купить ключ"
		buyBtn.TextColor3 = KEY_COLORS.accent
		buyBtn.TextSize = 13
		buyBtn.AutoButtonColor = false
		buyBtn.Parent = card

		local buyCorner = Instance.new("UICorner")
		buyCorner.CornerRadius = UDim.new(0, 8)
		buyCorner.Parent = buyBtn

		local buyStroke = Instance.new("UIStroke")
		buyStroke.Color = KEY_COLORS.accent
		buyStroke.Thickness = 1
		buyStroke.Parent = buyBtn

		local status = Instance.new("TextLabel")
		status.BackgroundTransparency = 1
		status.Position = UDim2.new(0, 24, 1, -36)
		status.Size = UDim2.new(1, -48, 0, 16)
		status.Font = Enum.Font.Gotham
		status.Text = ""
		status.TextColor3 = KEY_COLORS.muted
		status.TextSize = 11
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.Parent = card

		local verifying = false

		buyBtn.MouseButton1Click:Connect(function()
			local link = BUY_KEY_URL
			if not link or link == "" then
				status.Text = "Ссылка не настроена"
				status.TextColor3 = KEY_COLORS.error
				return
			end
			if safeCopy(link) then
				status.Text = "Ссылка на покупку скопирована"
				status.TextColor3 = KEY_COLORS.success
			else
				status.Text = link:gsub("https://", "")
				status.TextColor3 = KEY_COLORS.muted
			end
		end)

		verifyBtn.MouseButton1Click:Connect(function()
			if verifying then
				return
			end
			local key = inputBox.Text:gsub("%s+", "")
			if key == "" then
				status.Text = "Введи ключ"
				status.TextColor3 = KEY_COLORS.error
				return
			end
			verifying = true
			verifyBtn.Text = "Проверка..."
			task.spawn(function()
				local ok, msg, expiresAt, isPremium = validateWithPanda(key, SILENT_MODE)
				verifying = false
				verifyBtn.Text = "Продолжить"
				if ok then
					status.Text = "Ключ принят"
					status.TextColor3 = KEY_COLORS.success
					task.wait(0.45)
					destroyGate()
					if typeof(onContinue) == "function" then
						onContinue()
					end
				else
					status.Text = msg or "Неверный ключ"
					status.TextColor3 = KEY_COLORS.error
				end
			end)
		end)
	end

	local function showAuthGate(onContinue)
		if not playerGui then
			warn("[MAXI HUB] Нет PlayerGui для окна ключа")
			return
		end

		local cache = readCache()
		if isCacheFresh(cache) then
			task.defer(onContinue)
			tryValidateKeyAsync(cache.key)
			return
		end

		if not loadPelinda() then
			warn("[MAXI HUB] auth library не загрузилась")
			return
		end

		local savedKey = readSavedKey() or (isCacheValid(cache) and cache.key)
		if savedKey then
			buildLoadingGate()
			tryValidateKeyAsync(savedKey, function(ok)
				if ok then
					destroyGate()
					if typeof(onContinue) == "function" then
						onContinue()
					end
				else
					buildAuthGate(onContinue)
				end
			end)
			return
		end

		buildAuthGate(onContinue)
	end

	local function showPurchaseNotice(onContinue)
		showAuthGate(onContinue)
	end

	return {
		hasAccess = hasAccess,
		showAuthGate = showAuthGate,
		showPurchaseNotice = showPurchaseNotice,
		destroyGate = destroyGate,
		readCache = readCache,
		writeCache = writeCache,
		clearCache = clearCache,
		verifyKey = verifyKey,
		getKeyLink = getKeyLink,
		formatTime = formatTime,
		getKeyStatusText = getKeyStatusText,
		loadPelinda = loadPelinda,
	}
end

return MaxiHubKey
