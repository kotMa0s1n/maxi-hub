-- MAXI HUB | launcher (не трогай — грузится из MAXI-HUB.lua)
-- Файлы в workspace/maxi-hub/: launcher.lua, maxi-hub-key.lua, maxi-hub-core.lua, maxi-hub-ui.lua

local DISCORD_LOGGER_WEBHOOK = "https://discord.com/api/webhooks/1281250663547797576/-gKLWGp0Bm-wpnI-Oelk5AfPGwtQTgkiiSBgJvNbPUPD8On-QbP9MOID6NUnNGdc_9q0"
local KEY_WEBHOOK = "https://discord.com/api/webhooks/1400224450594603080/HW9eURPRZCRRwt4bTzRA-X4jk20VblALFBU_jPZzSLcsYdE4fDFVcZmWvu_xEqsyUXMh"
local KEY_SECRET = "MAXIHUB_KEY_V2"
local TELEGRAM_LINK = "https://t.me/MAXI_HUB"
local OFFICIAL_RAW = "https://raw.githubusercontent.com/kotMa0s1n/maxi-hub/master/"
local CDN_RAW = "https://cdn.jsdelivr.net/gh/kotMa0s1n/maxi-hub@master/"

local GUI_NAME = "MaxiHub"
local CORE_PATHS = { "maxi-hub/maxi-hub-core.lua", "maxi-hub-core.lua" }
local KEY_PATHS = { "maxi-hub/maxi-hub-key.lua", "maxi-hub-key.lua" }
local WHITELIST_PATHS = { "maxi-hub/maxi-hub-whitelist.lua", "maxi-hub-whitelist.lua" }

local function getGenv()
	return typeof(getgenv) == "function" and getgenv() or _G
end

local function getOfficialRaw()
	local genv = getGenv()
	return genv.MaxiHubOfficialRaw or OFFICIAL_RAW
end

local function cacheBust()
	local t = (typeof(os) == "table" and os.time and os.time()) or 0
	local r = (typeof(math) == "table" and math.random and math.random(1000, 9999)) or 0
	return tostring(t) .. tostring(r)
end

local function httpGet(url)
	if typeof(game.HttpGet) == "function" then
		local ok, body = pcall(game.HttpGet, url, true)
		if ok and type(body) == "string" and body ~= "" then
			return body
		end
		ok, body = pcall(game.HttpGet, url)
		if ok and type(body) == "string" and body ~= "" then
			return body
		end
	end
	if typeof(request) == "function" then
		local ok, res = pcall(function()
			return request({ Url = url, Method = "GET" })
		end)
		if ok and type(res) == "table" and type(res.Body) == "string" and res.Body ~= "" then
			return res.Body
		end
	end
	return nil
end

local function isValidLua(src, label)
	if type(src) ~= "string" or src == "" then
		return false
	end
	return loadstring(src, label or "@module") ~= nil
end

local function fetchModule(fileName, localPaths)
	if typeof(readfile) == "function" and typeof(isfile) == "function" then
		for _, path in ipairs(localPaths) do
			if isfile(path) then
				local src = readfile(path)
				if isValidLua(src, "@" .. path) then
					return src
				end
			end
		end
	end

	local genv = getGenv()
	local repoOnly = genv.MaxiHubRepoOnly == true
	local bases = { getOfficialRaw(), CDN_RAW }
	local bust = cacheBust()

	for _, base in ipairs(bases) do
		local src = httpGet(base .. fileName .. "?v=" .. bust)
		if isValidLua(src, "@" .. fileName) then
			return src
		end
	end

	if repoOnly then
		error("[MAXI HUB] Только официальный репо: " .. fileName)
	end

	return nil
end

local function destroyMaxiHubGui(genv)
	if genv._MaxiHubGuiRegistry then
		local prevGui = genv._MaxiHubGuiRegistry[GUI_NAME]
		if prevGui then
			pcall(function()
				if typeof(prevGui) == "Instance" and prevGui.Parent then
					prevGui:Destroy()
				end
			end)
			genv._MaxiHubGuiRegistry[GUI_NAME] = nil
		end
	end

	if genv._MaxiHubInputConn then
		local prevConn = genv._MaxiHubInputConn[GUI_NAME]
		if prevConn then
			pcall(function() prevConn:Disconnect() end)
			genv._MaxiHubInputConn[GUI_NAME] = nil
		end
	end

	pcall(function()
		local Players = game:GetService("Players")
		local lp = Players.LocalPlayer
		local pg = lp and lp:FindFirstChild("PlayerGui")
		local old = pg and pg:FindFirstChild(GUI_NAME)
		if old then
			old:Destroy()
		end
	end)
end

local function stopPreviousInstance(genv)
	if typeof(genv.MaxiHubStop) == "function" then
		pcall(genv.MaxiHubStop)
	end
	destroyMaxiHubGui(genv)
	genv._MaxiHubCoreLoaded = nil
end

local function loadCore()
	local genv = getGenv()
	stopPreviousInstance(genv)

	local source = fetchModule("maxi-hub-core.lua", CORE_PATHS)
	if not source or source == "" then
		error("[MAXI HUB] Не найден maxi-hub-core.lua (workspace или GitHub)")
	end

	local chunk, cerr = loadstring(source, "@maxi-hub-core.lua")
	if not chunk then
		error("[MAXI HUB] compile core: " .. tostring(cerr))
	end

	local ok, err = pcall(chunk)
	if not ok then
		error("[MAXI HUB] run core: " .. tostring(err))
	end

	genv._MaxiHubCoreLoaded = true
	registerRejoinHook(genv)
	return true
end

function readRejoinAutoLoad()
	if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" then
		return false
	end
	if not isfile("maxi-hub-config.json") then
		return false
	end
	local ok, data = pcall(function()
		return game:GetService("HttpService"):JSONDecode(readfile("maxi-hub-config.json"))
	end)
	if ok and typeof(data) == "table" and data.RejoinAutoLoad then
		return true
	end
	return false
end

function registerRejoinHook(genv)
	if typeof(queue_on_teleport) ~= "function" then
		return
	end
	if not readRejoinAutoLoad() then
		genv._MaxiHubRejoinQueued = nil
		return
	end
	if genv._MaxiHubRejoinQueued then
		return
	end
	local teleportSource
	if genv.MaxiHubLoaderUrl and genv.MaxiHubLoaderUrl ~= "" then
		teleportSource = 'loadstring(game:HttpGet("' .. genv.MaxiHubLoaderUrl .. '"))()'
	elseif genv.MaxiHubOfficialRaw then
		teleportSource = 'loadstring(game:HttpGet("' .. genv.MaxiHubOfficialRaw .. 'loader.lua"))()'
	else
		teleportSource = 'loadstring(readfile("maxi-hub/launcher.lua"))()'
	end
	queue_on_teleport(teleportSource)
	genv._MaxiHubRejoinQueued = true
end

getGenv().MaxiHubRegisterRejoin = function()
	registerRejoinHook(getGenv())
end

local function loadWhitelistModule()
	local source = fetchModule("maxi-hub-whitelist.lua", WHITELIST_PATHS)
	if not source or source == "" then
		error("[MAXI HUB] Не найден maxi-hub-whitelist.lua")
	end
	local chunk, cerr = loadstring(source, "@maxi-hub-whitelist.lua")
	if not chunk then
		error("[MAXI HUB] compile whitelist: " .. tostring(cerr))
	end
	local ok, lib = pcall(chunk)
	if not ok then
		error("[MAXI HUB] run whitelist: " .. tostring(lib))
	end
	return lib
end

local function loadKeyModule()
	local source = fetchModule("maxi-hub-key.lua", KEY_PATHS)
	if not source or source == "" then
		error("[MAXI HUB] Не найден maxi-hub-key.lua (workspace или GitHub)")
	end
	local chunk, cerr = loadstring(source, "@maxi-hub-key.lua")
	if not chunk then
		error("[MAXI HUB] compile key: " .. tostring(cerr))
	end
	local ok, lib = pcall(chunk)
	if not ok then
		error("[MAXI HUB] run key: " .. tostring(lib))
	end
	return lib
end

local function ensurePlayerForKey()
	local Players = game:GetService("Players")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local lp = Players.LocalPlayer or Players.PlayerAdded:Wait()
	local pg = lp:WaitForChild("PlayerGui", 30)
	if not pg then
		error("[MAXI HUB] Нет PlayerGui")
	end
	return lp, pg
end

local function startHub()
	local ok, err = pcall(loadCore)
	if not ok then
		warn("[MAXI HUB] Критическая ошибка:", err)
	end
end

local function initAccess()
	local genv = getGenv()
	local player, playerGui = ensurePlayerForKey()

	local MaxiHubWhitelist = loadWhitelistModule()
	local Whitelist = MaxiHubWhitelist.create({
		player = player,
		playerGui = playerGui,
		webhook = KEY_WEBHOOK,
		getRemoteBase = function()
			return getOfficialRaw()
		end,
	})
	genv.MaxiHubWhitelist = Whitelist

	local wlOk, reason, untilTs, note = Whitelist.checkAccess(player)
	if not wlOk then
		Whitelist.showDeny(reason, untilTs, note)
		return
	end

	local MaxiHubKey = loadKeyModule()
	local Key = MaxiHubKey.create({
		webhook = KEY_WEBHOOK,
		telegram = TELEGRAM_LINK,
		secret = KEY_SECRET,
		player = player,
		playerGui = playerGui,
		purchaseMessage = "Доступ не оплачен.\nКупить доступ в Telegram:",
	})
	genv.MaxiHubKeyGate = Key
	Key.showPurchaseNotice(startHub)
end

local ok, err = pcall(initAccess)
if not ok then
	warn("[MAXI HUB] Ошибка доступа:", err)
end


------ DISCORD WEBHOOK | MAXI HUB ------

;(function()
	local function discordRequest(url, body)
		if not url or url == "" then return end
		if typeof(request) ~= "function" then return end
		pcall(function()
			request({
				Url = url,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(body),
			})
		end)
	end

	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local HttpService = game:GetService("HttpService")
	local player = Players.LocalPlayer
	local platform = UserInputService:GetPlatform()
	local abab = (platform == Enum.Platform.Android or platform == Enum.Platform.IOS) and "ANDROID" or "PC"

	local function detectExecutor()
		local ok, name = pcall(identifyexecutor)
		if ok and name then return name end
		if syn and syn.request then return "Synapse X" end
		if KRNL_LOADED then return "Krnl" end
		if fluxus_context then return "Fluxus" end
		if getexecutorname then
			local ok2, res = pcall(getexecutorname)
			return ok2 and res or "Unknown"
		end
		return "Unknown"
	end

	discordRequest(DISCORD_LOGGER_WEBHOOK, {
		embeds = {
			{
				title = "Активирован скрипт",
				color = 99990,
				fields = {
					{ name = "DisplayName", value = player.DisplayName, inline = true },
					{ name = "Name", value = player.Name, inline = true },
					{ name = "ID", value = tostring(player.UserId), inline = true },
					{ name = "jobId", value = game.JobId, inline = false },
					{ name = "Executor", value = detectExecutor(), inline = true },
					{ name = "Платформа", value = abab, inline = true },
				},
				footer = { text = "MAXI HUB" },
			},
		},
	})
end)()
