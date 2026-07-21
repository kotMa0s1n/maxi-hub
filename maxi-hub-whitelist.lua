--[[ MAXI HUB · maxi-hub-whitelist.lua — проверка доступа по списку ]]

local HttpService = game:GetService("HttpService")

local MaxiHubWhitelist = {}

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
			year = tonumber(y),
			month = tonumber(m),
			day = tonumber(d),
			hour = tonumber(H),
			min = tonumber(M),
			sec = 0,
		})
	end

	y, m, d = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if y then
		return os.time({
			year = tonumber(y),
			month = tonumber(m),
			day = tonumber(d),
			hour = 23,
			min = 59,
			sec = 59,
		})
	end

	return nil
end

local function formatUntil(ts)
	return os.date("%d.%m.%Y %H:%M", ts)
end

function MaxiHubWhitelist.create(config)
	config = config or {}

	local DATA_FILE = config.dataFile or "maxi-hub-whitelist.json"
	local TELEGRAM = config.telegram or "https://t.me/MAXI_HUB"
	local DENY_MESSAGE = config.denyMessage or "Доступ закрыт."
	local WEBHOOK = config.webhook or ""
	local player = config.player
	local playerGui = config.playerGui
	local httpRequest = config.httpRequest or defaultHttpRequest
	local getRemoteBase = config.getRemoteBase

	local denyGui = nil

	local function readLocalData()
		if not canUseFiles() or not isfile(DATA_FILE) then
			return nil
		end
		local ok, raw = pcall(readfile, DATA_FILE)
		if not ok or not raw or raw == "" then
			return nil
		end
		local ok2, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok2 and type(data) == "table" then
			return data
		end
		return nil
	end

	local function fetchRemoteData()
		local base = typeof(getRemoteBase) == "function" and getRemoteBase() or nil
		if not base or typeof(game.HttpGet) ~= "function" then
			return nil
		end
		local ok, raw = pcall(function()
			return game:HttpGet(base .. "maxi-hub-whitelist.json")
		end)
		if not ok or type(raw) ~= "string" or raw == "" then
			return nil
		end
		local ok2, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok2 and type(data) == "table" then
			if typeof(writefile) == "function" then
				pcall(writefile, DATA_FILE, raw)
			end
			return data
		end
		return nil
	end

	local function loadData()
		return fetchRemoteData() or readLocalData()
	end

	local function getUserEntry(data, userId)
		if type(data.users) ~= "table" then
			return nil
		end
		local entry = data.users[tostring(userId)] or data.users[userId]
		if type(entry) == "table" then
			return entry
		end
		if type(entry) == "string" or type(entry) == "number" then
			return { ["until"] = entry }
		end
		return nil
	end

	local function checkAccess(targetPlayer)
		targetPlayer = targetPlayer or player
		if not targetPlayer then
			return false, "Нет player"
		end

		local data = loadData()
		if not data then
			return false, "Файл whitelist не найден"
		end
		if data.enabled == false then
			return true, "OK", nil, "whitelist disabled"
		end

		if type(data.telegram) == "string" and data.telegram ~= "" then
			TELEGRAM = data.telegram
		end
		if type(data.denyMessage) == "string" and data.denyMessage ~= "" then
			DENY_MESSAGE = data.denyMessage
		end

		local entry = getUserEntry(data, targetPlayer.UserId)
		if not entry then
			return false, "Тебя нет в whitelist"
		end

		local untilTs = parseUntil(entry["until"] or entry.untilAt or entry.expiresAt)
		if not untilTs then
			return false, "Неверная дата в whitelist"
		end
		if os.time() >= untilTs then
			return false, "Срок доступа истёк", untilTs, entry.note
		end

		return true, "OK", untilTs, entry.note
	end

	local function logDenied(reason, untilTs, note)
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
							title = "Whitelist: доступ запрещён",
							color = 15158332,
							fields = {
								{ name = "Игрок", value = player.Name, inline = true },
								{ name = "UserId", value = tostring(player.UserId), inline = true },
								{ name = "Причина", value = reason or "?", inline = false },
								{ name = "Было до", value = untilTs and formatUntil(untilTs) or "—", inline = true },
								{ name = "Заметка", value = note or "—", inline = true },
								{ name = "Контакт", value = TELEGRAM, inline = false },
							},
							footer = { text = "🔰MAXI HUB" },
						},
					},
				}),
			})
		end)
	end

	local function destroyDeny()
		if denyGui then
			denyGui:Destroy()
			denyGui = nil
		end
		if playerGui then
			local old = playerGui:FindFirstChild("MaxiHubWhitelistDeny")
			if old then
				old:Destroy()
			end
		end
	end

	local function showDeny(reason, untilTs, note)
		if not playerGui then
			warn("[MAXI HUB WL]", reason)
			return
		end

		destroyDeny()
		logDenied(reason, untilTs, note)

		local COLORS = {
			bg = Color3.fromRGB(14, 16, 18),
			panel = Color3.fromRGB(26, 30, 33),
			accent = Color3.fromRGB(0, 198, 178),
			text = Color3.fromRGB(242, 246, 248),
			muted = Color3.fromRGB(125, 135, 142),
			red = Color3.fromRGB(220, 75, 75),
		}

		denyGui = Instance.new("ScreenGui")
		denyGui.Name = "MaxiHubWhitelistDeny"
		denyGui.ResetOnSpawn = false
		denyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		denyGui.DisplayOrder = 1001
		denyGui.IgnoreGuiInset = true
		denyGui.Parent = playerGui

		local root = Instance.new("Frame")
		root.Size = UDim2.new(0, 360, 0, 220)
		root.Position = UDim2.new(0.5, -180, 0.5, -110)
		root.BackgroundColor3 = COLORS.bg
		root.BorderSizePixel = 0
		root.Parent = denyGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = root

		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.red
		stroke.Thickness = 1.5
		stroke.Parent = root

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -24, 0, 28)
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
		reasonLabel.TextColor3 = COLORS.red
		reasonLabel.TextWrapped = true
		reasonLabel.TextXAlignment = Enum.TextXAlignment.Left
		reasonLabel.TextYAlignment = Enum.TextYAlignment.Top
		reasonLabel.Text = reason or DENY_MESSAGE
		reasonLabel.Parent = root

		local details = {}
		if untilTs then
			table.insert(details, "Было до: " .. formatUntil(untilTs))
		end
		if note and note ~= "" then
			table.insert(details, note)
		end
		table.insert(details, "Telegram: " .. TELEGRAM:gsub("https://", ""))

		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(1, -24, 0, 72)
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

		local msg = Instance.new("TextLabel")
		msg.Size = UDim2.new(1, -24, 0, 24)
		msg.Position = UDim2.new(0, 12, 1, -34)
		msg.BackgroundTransparency = 1
		msg.Font = Enum.Font.Gotham
		msg.TextSize = 10
		msg.TextColor3 = COLORS.muted
		msg.TextWrapped = true
		msg.TextXAlignment = Enum.TextXAlignment.Left
		msg.Text = DENY_MESSAGE
		msg.Parent = root
	end

	local function getStatusText(targetPlayer)
		local ok, _, untilTs = checkAccess(targetPlayer)
		if ok and untilTs then
			return "Доступ до " .. formatUntil(untilTs)
		end
		if ok then
			return "Доступ открыт"
		end
		return "Нет доступа"
	end

	return {
		checkAccess = checkAccess,
		showDeny = showDeny,
		destroyDeny = destroyDeny,
		loadData = loadData,
		getStatusText = getStatusText,
		formatUntil = formatUntil,
	}
end

return MaxiHubWhitelist
