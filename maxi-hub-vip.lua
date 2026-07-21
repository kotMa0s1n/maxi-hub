--[[ MAXI HUB · maxi-hub-vip.lua — VIP по нику или UserId ]]

local HttpService = game:GetService("HttpService")

local MaxiHubVip = {}

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
	return typeof(readfile) == "function" and typeof(isfile) == "function"
end

local function stripBom(raw)
	if type(raw) ~= "string" then
		return raw
	end
	if raw:sub(1, 3) == "\239\187\191" then
		return raw:sub(4)
	end
	return raw
end

local function normName(value)
	if type(value) ~= "string" then
		return nil
	end
	value = value:gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" then
		return nil
	end
	return value:lower()
end

local function normId(value)
	if value == nil then
		return nil
	end
	if type(value) == "number" then
		return tostring(math.floor(value))
	end
	if type(value) == "string" then
		value = value:gsub("^%s+", ""):gsub("%s+$", "")
		if value:match("^%d+$") then
			return value
		end
	end
	return nil
end

local function parseUntil(value)
	if type(value) == "number" then
		return math.floor(value)
	end
	if type(value) ~= "string" then
		return nil
	end
	local y, m, d, H, M = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d)")
	if y then
		return os.time({
			year = tonumber(y), month = tonumber(m), day = tonumber(d),
			hour = tonumber(H), min = tonumber(M), sec = 0,
		})
	end
	y, m, d = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if y then
		return os.time({
			year = tonumber(y), month = tonumber(m), day = tonumber(d),
			hour = 23, min = 59, sec = 59,
		})
	end
	return nil
end

local function formatUntil(ts)
	return os.date("%d.%m.%Y %H:%M", ts)
end

local function copyText(text)
	if type(text) ~= "string" or text == "" then
		return false
	end
	if typeof(setclipboard) == "function" then
		local ok = pcall(setclipboard, text)
		if ok then return true end
	end
	if typeof(writeclipboard) == "function" then
		local ok = pcall(writeclipboard, text)
		if ok then return true end
	end
	return false
end

function MaxiHubVip.create(config)
	config = config or {}

	local DATA_FILE = config.dataFile or "maxi-hub-vip.json"
	local TELEGRAM = config.telegram or "https://t.me/MAXI_HUB"
	local BUY_MESSAGE = config.buyMessage or "VIP доступ не активирован.\nКупи VIP в Telegram:"
	local WEBHOOK = config.webhook or ""
	local player = config.player
	local playerGui = config.playerGui
	local httpRequest = config.httpRequest or defaultHttpRequest
	local getRemoteBase = config.getRemoteBase

	local buyGui = nil

	local function decodeJson(raw)
		raw = stripBom(raw)
		if type(raw) ~= "string" or raw == "" then
			return nil
		end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(data) == "table" then
			return data
		end
		return nil
	end

	local function readLocalData()
		if not canUseFiles() or not isfile(DATA_FILE) then
			return nil
		end
		local ok, raw = pcall(readfile, DATA_FILE)
		if not ok or not raw or raw == "" then
			return nil
		end
		return decodeJson(raw)
	end

	local function fetchRemoteData()
		local base = typeof(getRemoteBase) == "function" and getRemoteBase() or nil
		if not base or typeof(game.HttpGet) ~= "function" then
			return nil
		end
		local bust = tostring(os.time()) .. tostring(math.random(1000, 9999))
		local urls = {
			base .. "maxi-hub-vip.json?v=" .. bust,
			"https://cdn.jsdelivr.net/gh/kotMa0s1n/maxi-hub@master/maxi-hub-vip.json?v=" .. bust,
		}
		for _, url in ipairs(urls) do
			local ok, raw = pcall(function()
				return game:HttpGet(url, true)
			end)
			if not ok or type(raw) ~= "string" or raw == "" then
				ok, raw = pcall(function()
					return game:HttpGet(url)
				end)
			end
			if ok and type(raw) == "string" and raw ~= "" then
				local data = decodeJson(raw)
				if data then
					if typeof(writefile) == "function" then
						pcall(writefile, DATA_FILE, stripBom(raw))
					end
					return data
				end
			end
		end
		return nil
	end

	local function mergeData(remoteData, localData)
		if not remoteData then
			return localData
		end
		if not localData then
			return remoteData
		end
		local merged = {
			enabled = localData.enabled ~= nil and localData.enabled or remoteData.enabled,
			telegram = localData.telegram or remoteData.telegram,
			buyMessage = localData.buyMessage or remoteData.buyMessage,
			vip = {},
		}
		if type(remoteData.vip) == "table" then
			for key, entry in pairs(remoteData.vip) do
				merged.vip[tostring(key)] = entry
			end
		end
		if type(localData.vip) == "table" then
			for key, entry in pairs(localData.vip) do
				merged.vip[tostring(key)] = entry
			end
		end
		return merged
	end

	local function loadData()
		return mergeData(fetchRemoteData(), readLocalData())
	end

	local function entryMatchesPlayer(entry, key, targetPlayer)
		local playerName = normName(targetPlayer.Name)
		local playerId = normId(targetPlayer.UserId)
		local keyName = normName(key)
		local keyId = normId(key)

		if keyName and playerName and keyName == playerName then
			return true, "ник"
		end
		if keyId and playerId and keyId == playerId then
			return true, "UserId"
		end
		if type(entry) == "table" then
			local entryName = normName(entry.name or entry.nick or entry.username)
			local entryId = normId(entry.userId or entry.id)
			if entryName and playerName and entryName == playerName then
				return true, "ник"
			end
			if entryId and playerId and entryId == playerId then
				return true, "UserId"
			end
		end
		return false
	end

	local function checkAccess(targetPlayer)
		targetPlayer = targetPlayer or player
		if not targetPlayer then
			return false, "Нет player"
		end

		local data = loadData()
		if not data then
			return false, "Файл VIP не найден"
		end
		if data.enabled == false then
			return false, "VIP отключён"
		end
		if type(data.telegram) == "string" and data.telegram ~= "" then
			TELEGRAM = data.telegram
		end
		if type(data.buyMessage) == "string" and data.buyMessage ~= "" then
			BUY_MESSAGE = data.buyMessage
		end
		if type(data.vip) ~= "table" then
			return false, "Нет списка VIP"
		end

		for key, entry in pairs(data.vip) do
			local matched, matchBy = entryMatchesPlayer(entry, key, targetPlayer)
			if matched then
				local untilTs = parseUntil(type(entry) == "table" and (entry["until"] or entry.untilAt or entry.expiresAt) or entry)
				if not untilTs then
					return false, "Неверная дата VIP"
				end
				if os.time() >= untilTs then
					return false, "VIP истёк", untilTs, entry.note
				end
				return true, "OK", untilTs, entry.note, matchBy
			end
		end

		return false, "Нет VIP доступа"
	end

	local function logDenied(reason, untilTs)
		if not WEBHOOK or WEBHOOK == "" or not player then
			return
		end
		pcall(function()
			httpRequest({
				Url = WEBHOOK,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					embeds = {
						{
							title = "VIP: доступ закрыт",
							color = 15158332,
							fields = {
								{ name = "Игрок", value = player.Name, inline = true },
								{ name = "UserId", value = tostring(player.UserId), inline = true },
								{ name = "Причина", value = reason or "?", inline = false },
								{ name = "Было до", value = untilTs and formatUntil(untilTs) or "—", inline = true },
								{ name = "Контакт", value = TELEGRAM, inline = false },
							},
							footer = { text = "🔰MAXI HUB" },
						},
					},
				}),
			})
		end)
	end

	local function destroyBuy()
		if buyGui then
			buyGui:Destroy()
			buyGui = nil
		end
		if playerGui then
			local old = playerGui:FindFirstChild("MaxiHubVipBuy")
			if old then
				old:Destroy()
			end
		end
	end

	local function showBuy(reason, untilTs)
		if not playerGui then
			warn("[MAXI HUB VIP]", reason)
			return
		end

		destroyBuy()
		logDenied(reason, untilTs)

		local COLORS = {
			bg = Color3.fromRGB(14, 16, 18),
			panel = Color3.fromRGB(26, 30, 33),
			accent = Color3.fromRGB(0, 198, 178),
			text = Color3.fromRGB(242, 246, 248),
			muted = Color3.fromRGB(125, 135, 142),
			gold = Color3.fromRGB(255, 200, 87),
			red = Color3.fromRGB(220, 75, 75),
		}

		local contact = TELEGRAM:gsub("https://", "")

		buyGui = Instance.new("ScreenGui")
		buyGui.Name = "MaxiHubVipBuy"
		buyGui.ResetOnSpawn = false
		buyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		buyGui.DisplayOrder = 1001
		buyGui.IgnoreGuiInset = true
		buyGui.Parent = playerGui

		local root = Instance.new("Frame")
		root.Size = UDim2.new(0, 380, 0, 260)
		root.Position = UDim2.new(0.5, -190, 0.5, -130)
		root.BackgroundColor3 = COLORS.bg
		root.BorderSizePixel = 0
		root.Parent = buyGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = root

		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.gold
		stroke.Thickness = 1.5
		stroke.Parent = root

		local closeBtn = Instance.new("TextButton")
		closeBtn.Size = UDim2.new(0, 28, 0, 28)
		closeBtn.Position = UDim2.new(1, -36, 0, 8)
		closeBtn.BackgroundColor3 = COLORS.panel
		closeBtn.BorderSizePixel = 0
		closeBtn.Font = Enum.Font.GothamBold
		closeBtn.TextSize = 14
		closeBtn.TextColor3 = COLORS.muted
		closeBtn.Text = "×"
		closeBtn.AutoButtonColor = false
		closeBtn.Parent = root

		local closeCorner = Instance.new("UICorner")
		closeCorner.CornerRadius = UDim.new(0, 6)
		closeCorner.Parent = closeBtn

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -56, 0, 28)
		title.Position = UDim2.new(0, 12, 0, 14)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextColor3 = COLORS.text
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = "🔰MAXI HUB"
		title.Parent = root

		local reasonLabel = Instance.new("TextLabel")
		reasonLabel.Size = UDim2.new(1, -24, 0, 56)
		reasonLabel.Position = UDim2.new(0, 12, 0, 48)
		reasonLabel.BackgroundTransparency = 1
		reasonLabel.Font = Enum.Font.GothamBold
		reasonLabel.TextSize = 13
		reasonLabel.TextColor3 = COLORS.gold
		reasonLabel.TextWrapped = true
		reasonLabel.TextXAlignment = Enum.TextXAlignment.Left
		reasonLabel.TextYAlignment = Enum.TextYAlignment.Top
		reasonLabel.Text = reason or "Нет VIP доступа"
		reasonLabel.Parent = root

		local details = {
			BUY_MESSAGE,
			"",
			"Ник: " .. (player and player.Name or "?"),
			"UserId: " .. (player and tostring(player.UserId) or "?"),
		}
		if untilTs then
			table.insert(details, "Было до: " .. formatUntil(untilTs))
		end

		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(1, -24, 0, 88)
		hint.Position = UDim2.new(0, 12, 0, 108)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.Gotham
		hint.TextSize = 11
		hint.TextColor3 = COLORS.muted
		hint.TextWrapped = true
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextYAlignment = Enum.TextYAlignment.Top
		hint.Text = table.concat(details, "\n")
		hint.Parent = root

		local copyBtn = Instance.new("TextButton")
		copyBtn.Size = UDim2.new(1, -24, 0, 40)
		copyBtn.Position = UDim2.new(0, 12, 1, -52)
		copyBtn.BackgroundColor3 = COLORS.accent
		copyBtn.BorderSizePixel = 0
		copyBtn.Font = Enum.Font.GothamBold
		copyBtn.TextSize = 13
		copyBtn.TextColor3 = COLORS.bg
		copyBtn.Text = "Скопировать контакт"
		copyBtn.AutoButtonColor = false
		copyBtn.Parent = root

		local copyCorner = Instance.new("UICorner")
		copyCorner.CornerRadius = UDim.new(0, 8)
		copyCorner.Parent = copyBtn

		local status = Instance.new("TextLabel")
		status.Size = UDim2.new(1, -24, 0, 18)
		status.Position = UDim2.new(0, 12, 1, -18)
		status.BackgroundTransparency = 1
		status.Font = Enum.Font.Gotham
		status.TextSize = 10
		status.TextColor3 = COLORS.muted
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.Text = contact
		status.Parent = root

		closeBtn.MouseButton1Click:Connect(destroyBuy)

		copyBtn.MouseButton1Click:Connect(function()
			local copied = copyText(TELEGRAM) or copyText(contact)
			if copied then
				status.Text = "Скопировано: " .. contact
				status.TextColor3 = COLORS.accent
			else
				status.Text = contact .. " (скопируй вручную)"
				status.TextColor3 = COLORS.red
			end
		end)
	end

	return {
		checkAccess = checkAccess,
		showBuy = showBuy,
		destroyBuy = destroyBuy,
		loadData = loadData,
		formatUntil = formatUntil,
	}
end

return MaxiHubVip
