--[[ MAXI HUB · maxi-hub-auth.lua — проверка через Cloudflare Worker ]]

local HttpService = game:GetService("HttpService")

local MaxiHubAuth = {}

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

local function getHwid()
	local hwid = ""
	pcall(function()
		if typeof(gethwid) == "function" then
			hwid = gethwid() or ""
		elseif typeof(get_hwid) == "function" then
			hwid = get_hwid() or ""
		end
	end)
	return hwid
end

local REASON_TEXT = {
	not_in_whitelist = "Тебя нет в whitelist",
	expired = "Срок доступа истёк",
	hwid_mismatch = "Доступ привязан к другому устройству",
	bad_secret = "Ошибка авторизации Worker",
	whitelist_unavailable = "Сервер доступа недоступен",
}

function MaxiHubAuth.create(config)
	config = config or {}

	local WORKER_URL = config.workerUrl or ""
	local CLIENT_SECRET = config.clientSecret or ""
	local player = config.player
	local playerGui = config.playerGui
	local httpRequest = config.httpRequest or defaultHttpRequest
	local strict = config.strict ~= false
	local onFallback = config.onFallback

	local denyGui = nil

	local function reasonText(code, fallback)
		return REASON_TEXT[code] or fallback or code or "Нет доступа"
	end

	local function remoteCheck(targetPlayer)
		if WORKER_URL == "" then
			return nil, "no_worker_url"
		end

		targetPlayer = targetPlayer or player
		if not targetPlayer then
			return false, "no_player"
		end

		local body = HttpService:JSONEncode({
			userId = targetPlayer.UserId,
			name = targetPlayer.Name,
			displayName = targetPlayer.DisplayName,
			hwid = getHwid(),
			placeId = game.PlaceId,
			jobId = game.JobId,
		})

		local headers = { ["Content-Type"] = "application/json" }
		if CLIENT_SECRET ~= "" then
			headers.Authorization = "Bearer " .. CLIENT_SECRET
		end

		local ok, res = pcall(function()
			return httpRequest({
				Url = WORKER_URL,
				Method = "POST",
				Headers = headers,
				Body = body,
			})
		end)
		if not ok or not res then
			return nil, "request_failed"
		end

		local status = res.StatusCode or res.Status or 0
		local raw = res.Body or ""
		if status < 200 or status >= 300 then
			return nil, "http_" .. tostring(status), raw
		end

		local ok2, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok2 or type(data) ~= "table" then
			return nil, "bad_response"
		end

		if data.ok then
			return true, "OK", data["until"], data.note, data.untilText
		end
		return false, data.reason or "denied", data["until"], data.note, data.untilText
	end

	local function checkAccess(targetPlayer)
		local ok, reason, untilTs, note, untilText = remoteCheck(targetPlayer)
		if ok == true then
			return true, "OK", untilTs, note, untilText
		end
		if ok == false then
			return false, reasonText(reason), untilTs, note, untilText
		end

		if strict then
			return false, reasonText(reason, "Сервер доступа недоступен")
		end
		if typeof(onFallback) == "function" then
			return onFallback(targetPlayer)
		end
		return false, reasonText(reason, "Сервер доступа недоступен")
	end

	local function destroyDeny()
		if denyGui then
			denyGui:Destroy()
			denyGui = nil
		end
		if playerGui then
			local old = playerGui:FindFirstChild("MaxiHubAuthDeny")
			if old then old:Destroy() end
		end
	end

	local function showDeny(reason, untilText)
		if not playerGui then
			warn("[MAXI HUB AUTH]", reason)
			return
		end

		destroyDeny()

		local COLORS = {
			bg = Color3.fromRGB(14, 16, 18),
			accent = Color3.fromRGB(0, 198, 178),
			text = Color3.fromRGB(242, 246, 248),
			muted = Color3.fromRGB(125, 135, 142),
			red = Color3.fromRGB(220, 75, 75),
		}

		denyGui = Instance.new("ScreenGui")
		denyGui.Name = "MaxiHubAuthDeny"
		denyGui.ResetOnSpawn = false
		denyGui.DisplayOrder = 1002
		denyGui.IgnoreGuiInset = true
		denyGui.Parent = playerGui

		local root = Instance.new("Frame")
		root.Size = UDim2.new(0, 360, 0, 180)
		root.Position = UDim2.new(0.5, -180, 0.5, -90)
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
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, -24, 0, 28)
		title.Position = UDim2.new(0, 12, 0, 14)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextColor3 = COLORS.text
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = "🔰MAXI HUB"
		title.Parent = root

		local msg = Instance.new("TextLabel")
		msg.BackgroundTransparency = 1
		msg.Size = UDim2.new(1, -24, 0, 100)
		msg.Position = UDim2.new(0, 12, 0, 48)
		msg.Font = Enum.Font.Gotham
		msg.TextSize = 12
		msg.TextColor3 = COLORS.red
		msg.TextWrapped = true
		msg.TextXAlignment = Enum.TextXAlignment.Left
		msg.TextYAlignment = Enum.TextYAlignment.Top
		msg.Text = reason or "Нет доступа"
		if untilText and untilText ~= "" then
			msg.Text = msg.Text .. "\n\nБыло до: " .. untilText
		end
		msg.Parent = root
	end

	return {
		checkAccess = checkAccess,
		showDeny = showDeny,
		destroyDeny = destroyDeny,
		remoteCheck = remoteCheck,
	}
end

return MaxiHubAuth
