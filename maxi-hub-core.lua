-- MAXI HUB core (auto-loaded by launcher.lua)
SCRIPT_TITLE = "🔰MAXI HUB"
SCRIPT_VERSION = "v2.2"
GUI_NAME = "MaxiHub"
TELEGRAM_LINK = "https://t.me/MAXI_HUB"

Players = game:GetService("Players")
RunService = game:GetService("RunService")
UserInputService = game:GetService("UserInputService")
GuiService = game:GetService("GuiService")
HttpService = game:GetService("HttpService")
TweenService = game:GetService("TweenService")
ReplicatedStorage = game:GetService("ReplicatedStorage")

CONFIG_FILE = "maxi-hub-config.json"
CONFIG_VERSION = 2
SELL_STATE_FILE = "maxi-hub-sell-state.json"
UiLanguage = "ru"
LocaleLib = nil
localeBindings = {}
creditsAboutLabel = nil
creditsTgButton = nil
KEY_WEBHOOK = "https://discord.com/api/webhooks/1400224450594603080/HW9eURPRZCRRwt4bTzRA-X4jk20VblALFBU_jPZzSLcsYdE4fDFVcZmWvu_xEqsyUXMh"
DISCORD_CONFIG_FILE = "maxi-hub-discord.json"

UserDiscordWebhook = ""
DiscordReportsEnabled = true
DiscordReportMinutes = 10
DiscordLogOnSell = true
DiscordLogOnStop = true

player = nil
playerGui = nil
genv = nil
if typeof(getgenv) == "function" then
	genv = getgenv()
else
	genv = _G
end

function ensurePlayer()
	if player and playerGui and playerGui.Parent then
		return true
	end

	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		localPlayer = Players.PlayerAdded:Wait()
	end

	player = localPlayer
	playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		playerGui = player:WaitForChild("PlayerGui", 30)
	end
	if not playerGui then
		return false
	end

	local oldKeyGate = playerGui:FindFirstChild("MaxiHubKeyGate")
	if oldKeyGate then oldKeyGate:Destroy() end

	if genv.MaxiHubCameraOriginal == nil then
		pcall(function()
			genv.MaxiHubCameraOriginal = player.DevCameraOcclusionMode
		end)
	end

	return true
end

FarmEnabled = false
farmThread = nil
farmRunId = 0
farmTimeTotal = 0
farmTimeStarted = 0
teleportConnection = nil
currentTargetPart = nil
activeNode = nil
activeTargetKind = "tree"
farmPhase = "idle"
cachedTreeCount = 0
cachedStoneCount = 0
HOTKEY = Enum.KeyCode.End

pendingPrevStop = nil
if typeof(genv.MaxiHubStop) == "function" then
	pendingPrevStop = genv.MaxiHubStop
end

farmCheckPause = false

function shouldFarmContinue(runId)
	return FarmEnabled and runId == farmRunId and not farmCheckPause
end

function isCancelError(err)
	if typeof(err) ~= "string" then return false end
	local lower = string.lower(err)
	return string.find(lower, "cancel", 1, true) ~= nil
		or string.find(lower, "cancell", 1, true) ~= nil
end

cameraConnection = nil

function applyInvisicam()
	pcall(function()
		player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
	end)
end

function stopCameraLoop()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
end

function restoreCamera()
	stopCameraLoop()
	pcall(function()
		player.DevCameraOcclusionMode = genv.MaxiHubCameraOriginal
			or Enum.DevCameraOcclusionMode.Zoom
	end)
end

function startCameraLoop()
	stopCameraLoop()
	applyInvisicam()
	cameraConnection = RunService.Heartbeat:Connect(applyInvisicam)
end

COLLECT_RADIUS = 60
TeleportHeight = 2
StoneTeleportHeight = 3.5
ignoredDrops = {}
cachedDropCount = 0
VK_F = 0x46

UseFKey = true
UseClick = true
LegitMouseCapture = false
OrbitEnabled = false
AimAtTarget = true
BlockUiDuringFarm = false
BlockTrades = true
Render3dDisabled = false
AutoRender3dOnFarm = true
BlackScreenOverlay = true
render3dBeforeFarm = nil
render3dFarmActive = false
render3dFarmNeedsRestore = false
blackScreenGui = nil
setRender3dToggle = nil
render3dToggleSilent = false
HubWaitEnabled = true
AutoStartFarm = false
RejoinAutoLoad = false
BlockedZonesEnabled = false
BlockedZoneSize = 50
BlockedZoneCenter = nil
blockedZoneVisualPart = nil
BLOCKED_ZONE_FOLDER = "MaxiHubZones"
AutoSellEnabled = true
SellCheckInterval = 20
SellBatchAmount = 15000
SellCoconutThreshold = 8999
SELL_WORLD_ID = 3475397644
FARM_WORLD_ID = 4869039553
SELL_WAIT_AFTER_TP = 5
SELL_ITEMS = { "Avacado", "Coconut", "CacaoBean", "Apple", "Corn", "Lemon" }
sessionStoneDrops = 0
sessionTreesMined = 0
sessionStonesMined = 0
farmWarnings = {}
lastWarningAt = {}
sessionTreeDrops = 0
OrbitDiameter = 14
OrbitSpeed = 1.1
FarmTreesEnabled = true
FarmStonesEnabled = true
TargetPickMode = "nearest"
TeleportMode = "instant"
TeleportStepSize = 12
TeleportStepDelay = 0.06
AttackDelay = 0.15
DEFAULT_ZONE_SIZE = 50
BlockedZonesList = {}
EspEnabled = false
EspTrees = true
EspStones = true
EspPlayers = false
EspResources = true
EspDragons = true
EspTracers = true
EspNames = true
EspTextSize = 14
EspColors = {
	trees = { 0, 198, 178 },
	stones = { 140, 180, 255 },
	players = { 255, 220, 80 },
	resources = { 160, 160, 255 },
	dragons = { 255, 140, 60 },
	tracer = { 0, 198, 178 },
}
lastAttackAt = 0
MaxiHubESPLib = nil
zoneListLabel = nil
zonesListContainer = nil
DEFAULT_UI_POS = UDim2.new(0, 16, 0.5, -270)
savedUiPos = nil
screenGuiRef = nil
hiddenGuis = {}
safeModeConnections = {}

TRADE_HINTS = {
	"trade", "trading", "tradeoffer", "traderequest", "exchange", "swap",
}
orbitAngle = 0
mouseHeld = false
holdMouseX, holdMouseY = 0, 0

function ensureBlackScreenGui()
	if blackScreenGui and blackScreenGui.Parent then return end
	if not playerGui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MaxiHubBlackScreen"
	gui:SetAttribute("MaxiHubBlackScreen", true)
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 999998
	gui.Enabled = false
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Overlay"
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromScale(0, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	frame.Parent = gui

	blackScreenGui = gui
end

function updateBlackScreenOverlay()
	local shouldShow = Render3dDisabled and BlackScreenOverlay
	if shouldShow then
		ensureBlackScreenGui()
		if blackScreenGui then
			blackScreenGui.Enabled = true
		end
	else
		if blackScreenGui then
			blackScreenGui.Enabled = false
		end
		for _, child in ipairs(playerGui and playerGui:GetChildren() or {}) do
			if child:IsA("ScreenGui") and child:GetAttribute("MaxiHubBlackScreen") == true then
				child.Enabled = false
			end
		end
	end
end

function applyRender3dState(disabled, opts)
	opts = opts or {}
	Render3dDisabled = disabled == true
	_G.rndr_dis = Render3dDisabled
	genv.rndr_dis = Render3dDisabled

	pcall(function()
		RunService:Set3dRenderingEnabled(not Render3dDisabled)
	end)
	updateBlackScreenOverlay()

	if setRender3dToggle then
		render3dToggleSilent = true
		setRender3dToggle(Render3dDisabled, true)
		render3dToggleSilent = false
	end

	if not opts.skipSave then
		scheduleSaveConfig()
	end
end

function toggleRender3d()
	applyRender3dState(not Render3dDisabled)
end

function onFarmRender3dStart()
	if not AutoRender3dOnFarm or render3dFarmActive then return end

	render3dFarmActive = true
	render3dFarmNeedsRestore = not Render3dDisabled
	applyRender3dState(true, { silent = true, skipSave = true })
end

function onFarmRender3dStop()
	if not render3dFarmActive then return end

	render3dFarmActive = false
	local needsRestore = render3dFarmNeedsRestore
	render3dFarmNeedsRestore = false
	render3dBeforeFarm = nil

	if needsRestore then
		applyRender3dState(false, { silent = true, skipSave = true })
	else
		pcall(function()
			RunService:Set3dRenderingEnabled(false)
		end)
		Render3dDisabled = true
		_G.rndr_dis = true
		genv.rndr_dis = true
		updateBlackScreenOverlay()
		if setRender3dToggle then
			render3dToggleSilent = true
			setRender3dToggle(true, true)
			render3dToggleSilent = false
		end
	end
end

function cleanupRender3d()
	render3dBeforeFarm = nil
	render3dFarmActive = false
	render3dFarmNeedsRestore = false
	pcall(function()
		RunService:Set3dRenderingEnabled(true)
	end)
	_G.rndr_dis = false
	genv.rndr_dis = false
	if blackScreenGui then
		pcall(function() blackScreenGui:Destroy() end)
		blackScreenGui = nil
	end
end

function canUseConfigFile()
	return typeof(writefile) == "function"
		and typeof(readfile) == "function"
		and typeof(isfile) == "function"
end

saveConfigScheduled = false
saveConfigToken = 0
mainFrameRef = nil

function readConfigTable()
	if not canUseConfigFile() or not isfile(CONFIG_FILE) then
		return {}
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if ok and typeof(data) == "table" then
		return data
	end
	return {}
end

function writeConfigTable(data)
	if not canUseConfigFile() or typeof(data) ~= "table" then
		return false
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if not ok then
		warn("[MAXI HUB] Ошибка JSON:", json)
		return false
	end
	local wrote = false
	pcall(function()
		writefile(CONFIG_FILE, json)
		wrote = true
	end)
	return wrote
end

function serializeEspColors(colors)
	if type(colors) ~= "table" then return nil end
	local out = {}
	for key, rgb in pairs(colors) do
		if type(key) == "string" and type(rgb) == "table" and #rgb >= 3 then
			out[key] = {
				math.clamp(math.floor(rgb[1] or 0), 0, 255),
				math.clamp(math.floor(rgb[2] or 0), 0, 255),
				math.clamp(math.floor(rgb[3] or 0), 0, 255),
			}
		end
	end
	return out
end

function serializeBlockedZonesList()
	local out = {}
	if type(BlockedZonesList) ~= "table" then return out end
	for i, zone in ipairs(BlockedZonesList) do
		if type(zone) == "table" and type(zone.center) == "table" and #zone.center >= 3 then
			table.insert(out, {
				name = type(zone.name) == "string" and zone.name or (L("zone_default_name") .. " " .. i),
				center = {
					tonumber(zone.center[1]) or 0,
					tonumber(zone.center[2]) or 0,
					tonumber(zone.center[3]) or 0,
				},
				size = math.clamp(math.floor(zone.size or DEFAULT_ZONE_SIZE), 20, 120),
				enabled = zone.enabled ~= false,
			})
		end
	end
	return out
end

function deserializeBlockedZonesList(raw)
	local out = {}
	if type(raw) ~= "table" then return out end
	for i, zone in ipairs(raw) do
		if type(zone) == "table" and type(zone.center) == "table" and #zone.center >= 3 then
			table.insert(out, {
				name = type(zone.name) == "string" and zone.name or "",
				center = {
					tonumber(zone.center[1]) or 0,
					tonumber(zone.center[2]) or 0,
					tonumber(zone.center[3]) or 0,
				},
				size = math.clamp(math.floor(zone.size or DEFAULT_ZONE_SIZE), 20, 120),
				enabled = zone.enabled ~= false,
			})
		end
	end
	return out
end

function buildConfigPayload()
	local payload = {
		ConfigVersion = CONFIG_VERSION,
		TeleportHeight = TeleportHeight,
		StoneTeleportHeight = StoneTeleportHeight,
		UseFKey = UseFKey,
		UseClick = UseClick,
		LegitMouseCapture = LegitMouseCapture,
		OrbitEnabled = OrbitEnabled,
		AimAtTarget = AimAtTarget,
		OrbitSpeed = OrbitSpeed,
		OrbitDiameter = OrbitDiameter,
		FarmTreesEnabled = FarmTreesEnabled,
		FarmStonesEnabled = FarmStonesEnabled,
		TargetPickMode = TargetPickMode,
		TeleportMode = TeleportMode,
		TeleportStepSize = TeleportStepSize,
		TeleportStepDelay = TeleportStepDelay,
		AttackDelay = AttackDelay,
		BlockedZonesList = serializeBlockedZonesList(),
		EspEnabled = EspEnabled,
		EspTrees = EspTrees,
		EspStones = EspStones,
		EspPlayers = EspPlayers,
		EspResources = EspResources,
		EspDragons = EspDragons,
		EspTracers = EspTracers,
		EspNames = EspNames,
		EspTextSize = EspTextSize,
		EspColors = serializeEspColors(EspColors),
		BlockUiDuringFarm = BlockUiDuringFarm,
		BlockTrades = BlockTrades,
		Render3dDisabled = Render3dDisabled,
		AutoRender3dOnFarm = AutoRender3dOnFarm,
		BlackScreenOverlay = BlackScreenOverlay,
		HubWaitEnabled = HubWaitEnabled,
		AutoStartFarm = AutoStartFarm,
		RejoinAutoLoad = RejoinAutoLoad,
		BlockedZonesEnabled = BlockedZonesEnabled,
		BlockedZoneSize = BlockedZoneSize,
		AutoSellEnabled = AutoSellEnabled,
		SellCheckInterval = SellCheckInterval,
		UserDiscordWebhook = UserDiscordWebhook,
		DiscordReportsEnabled = DiscordReportsEnabled,
		DiscordReportMinutes = DiscordReportMinutes,
		DiscordLogOnSell = DiscordLogOnSell,
		DiscordLogOnStop = DiscordLogOnStop,
		UiLanguage = UiLanguage,
	}
	if mainFrameRef and mainFrameRef.Parent then
		local p = mainFrameRef.Position
		payload.UiXScale = p.X.Scale
		payload.UiXOffset = p.X.Offset
		payload.UiYScale = p.Y.Scale
		payload.UiYOffset = p.Y.Offset
	end
	return payload
end

function saveConfig()
	if not canUseConfigFile() then return end
	local payload = buildConfigPayload()
	local merged = readConfigTable()
	for key, value in pairs(payload) do
		merged[key] = value
	end
	writeConfigTable(merged)
end

function patchConfigTable(patch)
	if not canUseConfigFile() or typeof(patch) ~= "table" then return end
	local merged = readConfigTable()
	for key, value in pairs(patch) do
		merged[key] = value
	end
	writeConfigTable(merged)
end

function scheduleSaveConfig()
	saveConfigToken += 1
	local token = saveConfigToken
	if saveConfigScheduled then return end
	saveConfigScheduled = true
	task.delay(0.25, function()
		if token ~= saveConfigToken then
			saveConfigScheduled = false
			scheduleSaveConfig()
			return
		end
		saveConfigScheduled = false
		saveConfig()
	end)
end

function flushSaveConfig()
	saveConfigToken += 1
	saveConfigScheduled = false
	saveConfig()
end

function loadSellState()
	if not canUseConfigFile() or not isfile(SELL_STATE_FILE) then return nil end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(SELL_STATE_FILE))
	end)
	if ok and typeof(data) == "table" and data.pendingSell then
		return data
	end
	return nil
end

function hasPendingSellState()
	return loadSellState() ~= nil
end

function saveSellState(phase, opts)
	opts = opts or {}
	if not canUseConfigFile() then return end
	local payload = {
		pendingSell = true,
		phase = phase,
		manual = opts.manual == true,
		resumeFarm = opts.resumeFarm == true,
		savedAt = tick(),
	}
	pcall(function()
		writefile(SELL_STATE_FILE, HttpService:JSONEncode(payload))
	end)
end

function clearSellState()
	if not canUseConfigFile() then return end
	pcall(function()
		if isfile(SELL_STATE_FILE) then
			writefile(SELL_STATE_FILE, HttpService:JSONEncode({ pendingSell = false }))
		end
	end)
end

function sendSellDiscordLog(opts)
	opts = opts or {}
	pcall(function()
		if opts.force then
			if DiscordReportsEnabled and getFarmDiscordWebhook() ~= "" then
				logFarmSessionDiscord("Продажа завершена", 15844367)
			end
		elseif DiscordLogOnSell then
			logFarmSessionDiscord("Продажа завершена", 15844367)
		end
	end)
end

function finalizeSellResume(opts, soldAny)
	clearSellState()
	sendSellDiscordLog(opts)
	if opts.resumeFarm then
		task.defer(function()
			if not FarmEnabled then
				farmToggleSilent = true
				if setFarmToggle then
					setFarmToggle(true, true)
				end
				farmToggleSilent = false
				startFarm()
			end
		end)
	end
	return soldAny
end

function executeSellItems(waitStep, sellLoopContinue)
	local soldAny = false
	for i, itemName in ipairs(SELL_ITEMS) do
		if sellLoopContinue and not sellLoopContinue() then break end
		if sellResourceItem(itemName) then
			soldAny = true
		end
		if i < #SELL_ITEMS and waitStep then
			if not waitStep(0.1) then break end
		elseif i < #SELL_ITEMS then
			task.wait(0.1)
		end
	end
	return soldAny
end

function resumePendingSellAfterBootstrap()
	local state = loadSellState()
	if not state then return false end

	task.spawn(function()
		if sellInProgress then return end
		sellInProgress = true
		farmPhase = "sell"

		local opts = {
			force = state.manual == true,
			resumeFarm = state.resumeFarm == true,
			onStatus = function(statusMsg)
				if sellStatus and sellStatus.Parent then
					sellStatus.Text = statusMsg
				end
			end,
		}

		local function setStatus(msg)
			if opts.onStatus then
				pcall(opts.onStatus, msg)
			end
		end

		if state.phase == "sell" then
			setStatus("Возобновляем продажу...")
			waitForCharacterHrp(12)
			task.wait(SELL_WAIT_AFTER_TP)
			setStatus("Продаём ресурсы...")
			local soldAny = executeSellItems(function(sec)
				task.wait(sec)
				return true
			end, function()
				return sellInProgress
			end)
			saveSellState("return", state)
			setStatus("Возврат на фарм...")
			worldTeleport(FARM_WORLD_ID)
			waitForCharacterHrp(12)
			task.wait(2)
			local st2 = loadSellState()
			if st2 and st2.phase == "return" then
				finalizeSellResume(opts, soldAny)
			end
		elseif state.phase == "return" then
			setStatus("Завершаем продажу...")
			waitForCharacterHrp(12)
			task.wait(1)
			finalizeSellResume(opts, true)
		else
			clearSellState()
		end

		sellInProgress = false
		farmPhase = "idle"
	end)

	return true
end

function loadConfig()
	if not canUseConfigFile() or not isfile(CONFIG_FILE) then return end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if not ok or typeof(data) ~= "table" then return end

	if data.FarmTrees ~= nil or data.FarmStones ~= nil then
		-- старый конфиг — игнорируем
	end
	if typeof(data.TeleportHeight) == "number" then TeleportHeight = data.TeleportHeight end
	if typeof(data.StoneTeleportHeight) == "number" then StoneTeleportHeight = data.StoneTeleportHeight end
	if data.UseFKey ~= nil then UseFKey = data.UseFKey end
	if data.UseClick ~= nil then UseClick = data.UseClick end
	if data.LegitMouseCapture ~= nil then LegitMouseCapture = data.LegitMouseCapture end
	if data.OrbitEnabled ~= nil then OrbitEnabled = data.OrbitEnabled end
	if data.AimAtTarget ~= nil then AimAtTarget = data.AimAtTarget end
	if typeof(data.OrbitSpeed) == "number" then OrbitSpeed = data.OrbitSpeed end
	if typeof(data.OrbitDiameter) == "number" then OrbitDiameter = data.OrbitDiameter end
	if data.FarmTreesEnabled ~= nil then FarmTreesEnabled = data.FarmTreesEnabled end
	if data.FarmStonesEnabled ~= nil then FarmStonesEnabled = data.FarmStonesEnabled end
	if data.TargetPickMode == "random" or data.TargetPickMode == "nearest" then TargetPickMode = data.TargetPickMode end
	if data.TeleportMode == "smooth" or data.TeleportMode == "instant" then TeleportMode = data.TeleportMode end
	if typeof(data.TeleportStepSize) == "number" then
		TeleportStepSize = math.clamp(math.floor(data.TeleportStepSize), 2, 40)
	end
	if typeof(data.TeleportStepDelay) == "number" then
		TeleportStepDelay = math.clamp(data.TeleportStepDelay, 0.02, 0.5)
	elseif typeof(data.TeleportSmoothSpeed) == "number" then
		TeleportStepDelay = math.clamp(0.15 / data.TeleportSmoothSpeed, 0.02, 0.5)
	end
	if typeof(data.AttackDelay) == "number" then AttackDelay = data.AttackDelay end
	if typeof(data.BlockedZonesList) == "table" then
		BlockedZonesList = deserializeBlockedZonesList(data.BlockedZonesList)
	end
	normalizeBlockedZonesList()
	if typeof(data.EspColors) == "table" then
		EspColors = serializeEspColors(data.EspColors) or EspColors
	end
	if data.EspEnabled ~= nil then EspEnabled = data.EspEnabled end
	if data.EspTrees ~= nil then EspTrees = data.EspTrees end
	if data.EspStones ~= nil then EspStones = data.EspStones end
	if data.EspPlayers ~= nil then EspPlayers = data.EspPlayers end
	if data.EspResources ~= nil then EspResources = data.EspResources end
	if data.EspDragons ~= nil then EspDragons = data.EspDragons end
	if data.EspTracers ~= nil then EspTracers = data.EspTracers end
	if data.EspNames ~= nil then EspNames = data.EspNames end
	if typeof(data.EspTextSize) == "number" then EspTextSize = data.EspTextSize end
	if data.BlockUiDuringFarm ~= nil then BlockUiDuringFarm = data.BlockUiDuringFarm end
	if data.BlockTrades ~= nil then BlockTrades = data.BlockTrades end
	if data.Render3dDisabled ~= nil then
		Render3dDisabled = data.Render3dDisabled
	elseif _G.rndr_dis ~= nil then
		Render3dDisabled = _G.rndr_dis == true
	end
	if data.AutoRender3dOnFarm ~= nil then AutoRender3dOnFarm = data.AutoRender3dOnFarm end
	if data.BlackScreenOverlay ~= nil then BlackScreenOverlay = data.BlackScreenOverlay end
	if data.HubWaitEnabled ~= nil then HubWaitEnabled = data.HubWaitEnabled end
	if data.AutoStartFarm ~= nil then AutoStartFarm = data.AutoStartFarm end
	if data.RejoinAutoLoad ~= nil then RejoinAutoLoad = data.RejoinAutoLoad end
	if data.BlockedZonesEnabled ~= nil then BlockedZonesEnabled = data.BlockedZonesEnabled end
	if typeof(data.BlockedZoneSize) == "number" then
		BlockedZoneSize = math.clamp(math.floor(data.BlockedZoneSize), 20, 120)
	end
	if typeof(data.BlockedZoneCenter) == "table" and #data.BlockedZoneCenter >= 3 then
		if type(BlockedZonesList) ~= "table" or #BlockedZonesList == 0 then
			BlockedZonesList = {
				{
					center = {
						data.BlockedZoneCenter[1],
						data.BlockedZoneCenter[2],
						data.BlockedZoneCenter[3],
					},
					size = BlockedZoneSize or DEFAULT_ZONE_SIZE,
					enabled = true,
					name = L("zone_default_name") .. " 1",
				},
			}
		end
		BlockedZoneCenter = Vector3.new(
			data.BlockedZoneCenter[1],
			data.BlockedZoneCenter[2],
			data.BlockedZoneCenter[3]
		)
	end
	if data.AutoSellEnabled ~= nil then AutoSellEnabled = data.AutoSellEnabled end
	if typeof(data.SellCheckInterval) == "number" then SellCheckInterval = data.SellCheckInterval end
	if typeof(data.UserDiscordWebhook) == "string" then UserDiscordWebhook = data.UserDiscordWebhook end
	if data.DiscordReportsEnabled ~= nil then DiscordReportsEnabled = data.DiscordReportsEnabled end
	if typeof(data.DiscordReportMinutes) == "number" then
		DiscordReportMinutes = math.clamp(math.floor(data.DiscordReportMinutes), 1, 120)
		FARM_REPORT_INTERVAL = DiscordReportMinutes * 60
	end
	if data.DiscordLogOnSell ~= nil then DiscordLogOnSell = data.DiscordLogOnSell end
	if data.DiscordLogOnStop ~= nil then DiscordLogOnStop = data.DiscordLogOnStop end
	if typeof(data.UiLanguage) == "string" then
		UiLanguage = data.UiLanguage:lower() == "en" and "en" or "ru"
	end
	if typeof(data.UiXScale) == "number"
		or typeof(data.UiXOffset) == "number"
		or typeof(data.UiYScale) == "number"
		or typeof(data.UiYOffset) == "number" then
		savedUiPos = UDim2.new(
			typeof(data.UiXScale) == "number" and data.UiXScale or 0,
			typeof(data.UiXOffset) == "number" and data.UiXOffset or 16,
			typeof(data.UiYScale) == "number" and data.UiYScale or 0.5,
			typeof(data.UiYOffset) == "number" and data.UiYOffset or -270
		)
	end
end

-- loadConfig() вызывается в bootstrapMaxiHub()

function pushFarmWarning(key, msg)
	local now = tick()
	if lastWarningAt[key] and now - lastWarningAt[key] < 45 then
		return
	end
	lastWarningAt[key] = now
	farmWarnings[key] = msg
end

function clearFarmWarning(key)
	farmWarnings[key] = nil
end

function getFarmWarningsText()
	local lines = {}
	for _, msg in pairs(farmWarnings) do
		table.insert(lines, "• " .. msg)
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

function getTeleportHeightForKind(kind)
	if kind == "stone" then
		return StoneTeleportHeight
	end
	return TeleportHeight
end

function getFarmModeText()
	if not FarmTreesEnabled and not FarmStonesEnabled then
		return L("mode_search")
	end
	if cachedTreeCount > 0 and not cachedStoneCount then
		return L("mode_trees")
	end
	if cachedStoneCount > 0 and not cachedTreeCount then
		return L("mode_stones")
	end
	if cachedTreeCount > 0 then
		return L("mode_trees")
	end
	if cachedStoneCount > 0 then
		return L("mode_stones")
	end
	return L("mode_search")
end

STUCK_F_SECONDS = 4
autoFActive = false
stuckLastHealth = nil
stuckSince = 0

searchAngle = 0
searchRadius = 80
patrolPoints = {}
patrolIndex = 1
hubPosition = nil
HUB_WAIT_MIN = 3
HUB_WAIT_MAX = 8
HUB_NEAR_RADIUS = 15
lastSellCheckAt = 0
sellInProgress = false
manualSellToken = 0
lastFarmReportAt = 0
FARM_REPORT_INTERVAL = DiscordReportMinutes * 60

function getFarmDiscordWebhook()
	if UserDiscordWebhook and UserDiscordWebhook ~= "" then
		return UserDiscordWebhook
	end
	return KEY_WEBHOOK
end

function saveDiscordConfig()
	if not canUseConfigFile() then return end
	scheduleSaveConfig()
end

PHASE_TEXT = {
	idle = "ожидание",
	search = "поиск",
	mine = "добыча",
	wait = "ждём дропы",
	collect = "сбор",
	sell = "продажа",
	hub = "центр",
	travel = "путь к ноде",
}

function getWorkspaceModulePaths(fileName)
	local paths = {}
	local genv = typeof(getgenv) == "function" and getgenv() or _G
	if type(genv.MaxiHubLocalRoot) == "string" and genv.MaxiHubLocalRoot ~= "" then
		table.insert(paths, genv.MaxiHubLocalRoot .. "/" .. fileName)
	end
	table.insert(paths, "maxi-hub/" .. fileName)
	table.insert(paths, fileName)
	return paths
end

function loadEspLib()
	if MaxiHubESPLib then
		return MaxiHubESPLib
	end
	local paths = getWorkspaceModulePaths("maxi-hub-esp.lua")
	if typeof(readfile) == "function" and typeof(isfile) == "function" then
		for _, path in ipairs(paths) do
			if isfile(path) then
				local chunk = loadstring(readfile(path), "@maxi-hub-esp.lua")
				if chunk then
					local ok, lib = pcall(chunk)
					if ok and type(lib) == "table" then
						MaxiHubESPLib = lib
						return MaxiHubESPLib
					end
				end
			end
		end
	end
	return nil
end

MaxiHubChangelog = nil

function loadChangelogLib()
	if MaxiHubChangelog then
		return MaxiHubChangelog
	end
	local paths = getWorkspaceModulePaths("maxi-hub-changelog.lua")
	if typeof(readfile) == "function" and typeof(isfile) == "function" then
		for _, path in ipairs(paths) do
			if isfile(path) then
				local chunk = loadstring(readfile(path), "@maxi-hub-changelog.lua")
				if chunk then
					local ok, lib = pcall(chunk)
					if ok and type(lib) == "table" then
						MaxiHubChangelog = lib
						return MaxiHubChangelog
					end
				end
			end
		end
	end
	return nil
end

function refreshEsp()
	loadEspLib()
	if MaxiHubESPLib and typeof(MaxiHubESPLib.refresh) == "function" then
		MaxiHubESPLib.refresh({
			enabled = EspEnabled,
			EspTrees = EspTrees,
			EspStones = EspStones,
			EspPlayers = EspPlayers,
			EspResources = EspResources,
			EspDragons = EspDragons,
			EspTracers = EspTracers,
			EspNames = EspNames,
			EspTextSize = EspTextSize,
			EspColors = EspColors,
		})
	end
end

function loadLocaleLib()
	if LocaleLib then
		return LocaleLib
	end
	local paths = getWorkspaceModulePaths("maxi-hub-locale.lua")
	if typeof(readfile) == "function" and typeof(isfile) == "function" then
		for _, path in ipairs(paths) do
			if isfile(path) then
				local chunk = loadstring(readfile(path), "@maxi-hub-locale.lua")
				if chunk then
					local ok, lib = pcall(chunk)
					if ok and type(lib) == "table" then
						LocaleLib = lib
						return LocaleLib
					end
				end
			end
		end
	end
	return nil
end

function L(key)
	if LocaleLib and typeof(LocaleLib.t) == "function" then
		return LocaleLib.t(UiLanguage, key)
	end
	return key
end

function registerLocale(element, key)
	if element and key then
		table.insert(localeBindings, { element = element, key = key })
	end
end

function getTabDefs()
	return {
		{ name = L("tab_home"), title = L("tab_home"), subtitle = L("tab_home_sub") },
		{ name = L("tab_settings"), title = L("tab_settings"), subtitle = L("tab_settings_sub") },
		{ name = L("tab_discord"), title = L("tab_discord"), subtitle = L("tab_discord_sub") },
		{ name = L("tab_esp"), title = L("tab_esp"), subtitle = L("tab_esp_sub") },
		{ name = L("tab_changelog"), title = L("tab_changelog"), subtitle = L("tab_changelog_sub") },
		{ name = L("tab_credits"), title = L("tab_credits"), subtitle = L("tab_credits_sub") },
	}
end

function refreshPhaseText()
	PHASE_TEXT = {
		idle = L("phase_idle"),
		search = L("phase_search"),
		mine = L("phase_mine"),
		wait = L("phase_wait"),
		collect = L("phase_collect"),
		sell = L("phase_sell"),
		hub = L("phase_hub"),
		travel = L("phase_travel"),
	}
end

function updateDiscordStatusText()
	if not discordStatus then return end
	discordStatus.Text = canUseConfigFile() and L("webhook_saved_ok") or L("webhook_saved_bad")
end

function updateCreditsAboutText(scriptLine)
	if not creditsAboutLabel then return end
	creditsAboutLabel.Text = SCRIPT_TITLE .. "\n" .. (scriptLine or L("script_line")) .. "\n" .. L("credits_thanks")
end

function applyMaxiHubLocale()
	for _, item in ipairs(localeBindings) do
		if item.element and item.element.Parent then
			item.element.Text = L(item.key)
		end
	end
	refreshPhaseText()
	updateDiscordStatusText()
	updateCreditsAboutText()
	if manualSellBtn and manualSellBtn.Text ~= L("btn_selling") then
		manualSellBtn.Text = L("btn_sell_now")
	end
	if creditsTgButton and creditsTgButton.Text ~= L("tg_copied") then
		creditsTgButton.Text = L("tg_button")
	end
	if zonePlaceBtn and zonePlaceBtn.Text ~= L("btn_cube_placed") and zonePlaceBtn.Text ~= L("btn_no_character") then
		zonePlaceBtn.Text = L("btn_place_cube")
	end
	if ui then
		if typeof(ui.setTitleHint) == "function" then
			ui.setTitleHint(L("title_hint"))
		end
		if typeof(ui.setHideHintText) == "function" then
			ui.setHideHintText(L("hide_hint"))
		end
		if typeof(ui.refreshTabLabels) == "function" then
			ui.refreshTabLabels(getTabDefs())
		end
		if typeof(ui.setLanguage) == "function" then
			ui.setLanguage(UiLanguage)
		end
		if typeof(ui.refreshKeyStatus) == "function" then
			ui.refreshKeyStatus()
		end
	end
	local keyGate = genv.MaxiHubKeyGate
	if keyGate and typeof(keyGate.setLanguage) == "function" then
		keyGate.setLanguage(UiLanguage)
	end
end

function setUiLanguage(lang)
	UiLanguage = (type(lang) == "string" and lang:lower() == "en") and "en" or "ru"
	applyMaxiHubLocale()
	scheduleSaveConfig()
end

function getTeleportSpawnPart()
	local interactions = workspace:FindFirstChild("Interactions")
	if not interactions then return nil end
	local teleports = interactions:FindFirstChild("WorldTeleports")
	if not teleports then return nil end
	local pad = teleports:FindFirstChild("TeleportPad")
	if not pad then return nil end
	local model = pad:FindFirstChild("TeleportModel")
	if not model then return nil end
	if model:IsA("BasePart") then
		return model
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

VirtualInputManager = nil
pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)

function releaseFKey()
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
		end)
	end
end

function releaseMouseHold()
	if not mouseHeld then return end
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(holdMouseX, holdMouseY, 0, false, game, 0)
		end)
	end
	pcall(function()
		if typeof(mouse1release) == "function" then
			mouse1release()
		end
	end)
	mouseHeld = false
end

function stopCharacterMotion()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

function getBlockedZoneHalfSize()
	return BlockedZoneSize / 2
end

function getBlockedZoneMinMax()
	if not BlockedZoneCenter then return nil, nil end
	local h = getBlockedZoneHalfSize()
	return BlockedZoneCenter - Vector3.new(h, h, h), BlockedZoneCenter + Vector3.new(h, h, h)
end

function normalizeBlockedZone(zone, index)
	if type(zone) ~= "table" then return nil end
	zone.size = math.clamp(math.floor(zone.size or DEFAULT_ZONE_SIZE), 20, 120)
	if zone.enabled == nil then zone.enabled = true end
	if type(zone.name) ~= "string" or zone.name == "" then
		zone.name = L("zone_default_name") .. " " .. tostring(index)
	end
	return zone
end

function normalizeBlockedZonesList()
	BlockedZonesList = BlockedZonesList or {}
	for i, zone in ipairs(BlockedZonesList) do
		normalizeBlockedZone(zone, i)
	end
end

function isPosInBlockedZone(pos)
	if not BlockedZonesEnabled or not pos then return false end
	if type(BlockedZonesList) == "table" and #BlockedZonesList > 0 then
		for _, zone in ipairs(BlockedZonesList) do
			if zone.enabled == false then continue end
			local center = zone.center
			local size = zone.size or DEFAULT_ZONE_SIZE
			if type(center) == "table" and #center >= 3 then
				local half = size / 2
				local c = Vector3.new(center[1], center[2], center[3])
				local mn = c - Vector3.new(half, half, half)
				local mx = c + Vector3.new(half, half, half)
				if pos.X >= mn.X and pos.X <= mx.X
					and pos.Y >= mn.Y and pos.Y <= mx.Y
					and pos.Z >= mn.Z and pos.Z <= mx.Z then
					return true
				end
			end
		end
		return false
	end
	if not BlockedZoneCenter then return false end
	local mn, mx = getBlockedZoneMinMax()
	if not mn or not mx then return false end
	return pos.X >= mn.X and pos.X <= mx.X
		and pos.Y >= mn.Y and pos.Y <= mx.Y
		and pos.Z >= mn.Z and pos.Z <= mx.Z
end

function removeBlockedZone(index)
	if not BlockedZonesList[index] then return end
	table.remove(BlockedZonesList, index)
	if #BlockedZonesList == 0 then
		BlockedZoneCenter = nil
	end
	updateBlockedZoneVisual()
	rebuildZonesListUI()
	scheduleSaveConfig()
end

function addBlockedZoneAtPlayer()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	BlockedZonesList = BlockedZonesList or {}
	local idx = #BlockedZonesList + 1
	table.insert(BlockedZonesList, {
		center = { hrp.Position.X, hrp.Position.Y, hrp.Position.Z },
		size = DEFAULT_ZONE_SIZE,
		enabled = true,
		name = L("zone_default_name") .. " " .. tostring(idx),
	})
	BlockedZoneCenter = hrp.Position
	updateBlockedZoneVisual()
	rebuildZonesListUI()
	scheduleSaveConfig()
	return true
end

function clearBlockedZones()
	BlockedZonesList = {}
	BlockedZoneCenter = nil
	updateBlockedZoneVisual()
	rebuildZonesListUI()
	scheduleSaveConfig()
end

function createZoneCard(parent, index, zone)
	local card = Instance.new("Frame")
	card.Name = "ZoneCard_" .. index
	card.Size = UDim2.new(1, 0, 0, 96)
	card.BackgroundColor3 = COLORS.panel
	card.BorderSizePixel = 0
	card.LayoutOrder = index
	card.Parent = parent
	addCorner(card, 8)

	local nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(1, -118, 0, 26)
	nameBox.Position = UDim2.new(0, 10, 0, 8)
	nameBox.BackgroundColor3 = COLORS.card
	nameBox.BorderSizePixel = 0
	nameBox.ClearTextOnFocus = false
	nameBox.Font = Enum.Font.GothamBold
	nameBox.TextSize = 11
	nameBox.TextColor3 = COLORS.text
	nameBox.PlaceholderText = L("zone_name_placeholder")
	nameBox.Text = zone.name or ""
	nameBox.TextXAlignment = Enum.TextXAlignment.Left
	nameBox.Parent = card
	addCorner(nameBox, 6)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = nameBox

	local enabledTrack = Instance.new("TextButton")
	enabledTrack.Size = UDim2.new(0, 40, 0, 22)
	enabledTrack.Position = UDim2.new(1, -96, 0, 10)
	enabledTrack.BackgroundColor3 = zone.enabled ~= false and COLORS.accent or COLORS.toggleOff
	enabledTrack.BorderSizePixel = 0
	enabledTrack.Text = ""
	enabledTrack.AutoButtonColor = false
	enabledTrack.Parent = card
	addCorner(enabledTrack, 11)

	local enabledKnob = Instance.new("Frame")
	enabledKnob.Size = UDim2.new(0, 16, 0, 16)
	enabledKnob.Position = zone.enabled ~= false and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
	enabledKnob.BackgroundColor3 = COLORS.text
	enabledKnob.BorderSizePixel = 0
	enabledKnob.Parent = enabledTrack
	addCorner(enabledKnob, 8)

	local function paintEnabled()
		local on = zone.enabled ~= false
		enabledTrack.BackgroundColor3 = on and COLORS.accent or COLORS.toggleOff
		TweenService:Create(enabledKnob, TweenInfo.new(0.12), {
			Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
		}):Play()
	end

	enabledTrack.MouseButton1Click:Connect(function()
		zone.enabled = zone.enabled == false
		paintEnabled()
		updateBlockedZoneVisual()
		scheduleSaveConfig()
	end)

	local deleteBtn = Instance.new("TextButton")
	deleteBtn.Size = UDim2.new(0, 40, 0, 26)
	deleteBtn.Position = UDim2.new(1, -48, 0, 8)
	deleteBtn.BackgroundColor3 = COLORS.card
	deleteBtn.BorderSizePixel = 0
	deleteBtn.Font = Enum.Font.GothamBold
	deleteBtn.TextSize = 14
	deleteBtn.TextColor3 = COLORS.red
	deleteBtn.Text = "×"
	deleteBtn.AutoButtonColor = false
	deleteBtn.Parent = card
	addCorner(deleteBtn, 6)
	deleteBtn.MouseButton1Click:Connect(function()
		removeBlockedZone(index)
	end)

	nameBox.FocusLost:Connect(function()
		local text = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		zone.name = text ~= "" and text or (L("zone_default_name") .. " " .. tostring(index))
		nameBox.Text = zone.name
		scheduleSaveConfig()
	end)

	local sizeWrap = Instance.new("Frame")
	sizeWrap.Size = UDim2.new(1, -20, 0, 52)
	sizeWrap.Position = UDim2.new(0, 10, 0, 40)
	sizeWrap.BackgroundTransparency = 1
	sizeWrap.Parent = card
	makeSlider(sizeWrap, 0, L("slider_cube_size"), 20, 120, zone.size or DEFAULT_ZONE_SIZE, function(v)
		zone.size = math.floor(v)
		updateBlockedZoneVisual()
		scheduleSaveConfig()
	end, "slider_cube_size")
end

function rebuildZonesListUI()
	if not zonesListContainer then return end
	for _, child in ipairs(zonesListContainer:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	normalizeBlockedZonesList()
	for i, zone in ipairs(BlockedZonesList) do
		createZoneCard(zonesListContainer, i, zone)
	end
end

function isNodeInBlockedZone(node)
	local center = getNodeCenter(node)
	return center and isPosInBlockedZone(center)
end

function ensureBlockedZoneFolder()
	local folder = workspace:FindFirstChild(BLOCKED_ZONE_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = BLOCKED_ZONE_FOLDER
		folder.Parent = workspace
	end
	return folder
end

function destroyBlockedZoneVisual()
	if blockedZoneVisualPart then
		pcall(function() blockedZoneVisualPart:Destroy() end)
		blockedZoneVisualPart = nil
	end
	pcall(function()
		local folder = workspace:FindFirstChild(BLOCKED_ZONE_FOLDER)
		if folder then folder:Destroy() end
	end)
end

function updateBlockedZoneVisual()
	if not BlockedZonesEnabled then
		destroyBlockedZoneVisual()
		return
	end

	local folder = ensureBlockedZoneFolder()
	destroyBlockedZoneVisual()
	folder = ensureBlockedZoneFolder()

	if type(BlockedZonesList) == "table" and #BlockedZonesList > 0 then
		for i, zone in ipairs(BlockedZonesList) do
			local center = zone.center
			local size = zone.size or DEFAULT_ZONE_SIZE
			local enabled = zone.enabled ~= false
			if type(center) == "table" and #center >= 3 then
				local part = Instance.new("Part")
				part.Name = "AntiTPZone_" .. i
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Material = Enum.Material.ForceField
				part.Color = enabled and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(130, 130, 130)
				part.Transparency = enabled and 0.72 or 0.88
				part.Size = Vector3.new(size, size, size)
				part.CFrame = CFrame.new(center[1], center[2], center[3])
				part.Parent = folder
			end
		end
		return
	end

	if not BlockedZoneCenter then
		return
	end

	blockedZoneVisualPart = Instance.new("Part")
	blockedZoneVisualPart.Name = "AntiTPZone"
	blockedZoneVisualPart.Anchored = true
	blockedZoneVisualPart.CanCollide = false
	blockedZoneVisualPart.CanQuery = false
	blockedZoneVisualPart.CanTouch = false
	blockedZoneVisualPart.CastShadow = false
	blockedZoneVisualPart.Material = Enum.Material.ForceField
	blockedZoneVisualPart.Color = Color3.fromRGB(255, 70, 70)
	blockedZoneVisualPart.Transparency = 0.72
	blockedZoneVisualPart.Size = Vector3.new(BlockedZoneSize, BlockedZoneSize, BlockedZoneSize)
	blockedZoneVisualPart.CFrame = CFrame.new(BlockedZoneCenter)
	blockedZoneVisualPart.Parent = folder
end

function setBlockedZoneAtPlayer()
	return addBlockedZoneAtPlayer()
end

function applyHrpCFrameInstant(hrp, goalCFrame)
	hrp.CFrame = goalCFrame
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

function teleportHrpToInstant(pos, lookAt)
	if isPosInBlockedZone(pos) then return false end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not pos then return false end
	local cf = lookAt and CFrame.new(pos, lookAt) or CFrame.new(pos)
	applyHrpCFrameInstant(hrp, cf)
	return true
end

function teleportHrpToSteps(pos, runId)
	if isPosInBlockedZone(pos) then return false end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not pos then return false end
	if TeleportMode ~= "smooth" then
		return teleportHrpToInstant(pos)
	end

	local start = hrp.Position
	local goal = pos
	local offset = goal - start
	local dist = offset.Magnitude
	if dist < 0.4 then
		applyHrpCFrameInstant(hrp, CFrame.new(goal))
		return true
	end

	local dir = offset.Unit
	local traveled = 0
	while traveled < dist - 0.1 do
		if runId and not shouldFarmContinue(runId) then return false end
		local step = math.min(TeleportStepSize, dist - traveled)
		traveled += step
		applyHrpCFrameInstant(hrp, CFrame.new(start + dir * traveled))
		if not interruptibleWait(TeleportStepDelay, runId) then return false end
	end

	applyHrpCFrameInstant(hrp, CFrame.new(goal))
	return true
end

function teleportHrpTo(pos, opts)
	opts = opts or {}
	if opts.smooth then
		return teleportHrpToSteps(pos, opts.runId)
	end
	return teleportHrpToInstant(pos, opts.lookAt)
end

function interruptibleWait(seconds, runId)
	local deadline = tick() + seconds
	while tick() < deadline do
		if runId and not shouldFarmContinue(runId) then
			return false
		end
		task.wait(math.max(0.01, math.min(0.1, deadline - tick())))
	end
	return runId == nil or shouldFarmContinue(runId)
end

function interruptibleWaitForSell(seconds)
	local token = manualSellToken
	local deadline = tick() + seconds
	while tick() < deadline do
		if token ~= manualSellToken or not sellInProgress then
			return false
		end
		task.wait(math.max(0.01, math.min(0.1, deadline - tick())))
	end
	return token == manualSellToken and sellInProgress
end

function captureHubPosition()
	local spawnPart = getTeleportSpawnPart()
	if spawnPart then
		hubPosition = spawnPart.Position + Vector3.new(0, 3, 0)
		return hubPosition
	end

	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hubPosition = hrp.Position
		return hubPosition
	end
end

function getHubPosition()
	if hubPosition then
		return hubPosition
	end

	local spawnPart = getTeleportSpawnPart()
	if spawnPart then
		hubPosition = spawnPart.Position + Vector3.new(0, 3, 0)
		return hubPosition
	end

	for _, name in ipairs({ "Spawn", "SpawnLocation", "Hub" }) do
		local inst = workspace:FindFirstChild(name)
		if inst then
			local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
			if part then
				hubPosition = part.Position + Vector3.new(0, 3, 0)
				return hubPosition
			end
		end
	end

	return captureHubPosition() or Vector3.new(0, 5, 0)
end

function isNearHub()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local hub = getHubPosition()
	if not hrp or not hub then return false end
	local here = Vector3.new(hrp.Position.X, hub.Y, hrp.Position.Z)
	local there = Vector3.new(hub.X, hub.Y, hub.Z)
	return (here - there).Magnitude <= HUB_NEAR_RADIUS
end

function teleportToHub(runId)
	if isNearHub() then return true end

	local hubPos
	local spawnPart = getTeleportSpawnPart()
	if spawnPart then
		hubPosition = spawnPart.Position + Vector3.new(0, 3, 0)
		hubPos = hubPosition
	else
		hubPos = getHubPosition()
	end
	local useSmooth = TeleportMode == "smooth"
	return teleportHrpTo(hubPos, { smooth = useSmooth, runId = runId })
end

function hubRestWait(runId, doTeleport)
	if doTeleport == nil then doTeleport = true end
	if not HubWaitEnabled then
		return true
	end

	farmPhase = "hub"
	releaseMouseHold()
	releaseFKey()
	stopCharacterMotion()
	currentTargetPart = nil
	if doTeleport then
		if not teleportToHub(runId) then return false end
	end
	local waitTime = HUB_WAIT_MIN + math.random() * (HUB_WAIT_MAX - HUB_WAIT_MIN)
	return interruptibleWait(waitTime, runId)
end

function returnToHubAfterNode(runId)
	if not hubRestWait(runId) then
		return false
	end
	farmPhase = "idle"
	return true
end

function shouldPressF()
	return UseFKey or autoFActive
end

function pressF()
	if not shouldPressF() then return end

	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
			task.wait(0.03)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
		end)
	end
	pcall(function() keytap(VK_F) end)
end

function moveMouseToScreen(x, y)
	if not LegitMouseCapture or not x or not y then return end
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendMouseMoveEvent(x, y, game)
		end)
	end
	if typeof(mousemoveabs) == "function" then
		pcall(function() mousemoveabs(x, y) end)
	end
end

function holdMouseAt(x, y)
	x, y = x or 0, y or 0
	moveMouseToScreen(x, y)
	if mouseHeld and math.abs(holdMouseX - x) < 2 and math.abs(holdMouseY - y) < 2 then
		return
	end
	releaseMouseHold()
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
		end)
	elseif LegitMouseCapture then
		pcall(function()
			if typeof(mouse1press) == "function" then
				mouse1press()
			end
		end)
	end
	mouseHeld = true
	holdMouseX, holdMouseY = x, y
end

function clickAt(x, y)
	moveMouseToScreen(x, y)
	releaseMouseHold()
	if VirtualInputManager and x and y then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
			local releaseDelay = AttackDelay > 0 and 0.05 or 0.01
			if releaseDelay > 0 then
				task.wait(releaseDelay)
			end
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
		end)
	elseif LegitMouseCapture then
		pcall(function()
			if typeof(mouse1click) == "function" then
				mouse1click()
			end
		end)
	end
end

function getScreenPos(worldPos)
	if not worldPos then return nil end
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local pos = cam:WorldToViewportPoint(worldPos)
	local inset = GuiService:GetGuiInset()
	return pos.X, pos.Y + inset.Y
end

function getFallbackScreenPos()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local inset = GuiService:GetGuiInset()
	local vs = cam.ViewportSize
	return vs.X * 0.5, vs.Y * 0.5 + inset.Y
end

function getPartPosition(part)
	if not part then return nil end
	if part:IsA("BasePart") then
		return part.Position
	end
	local bp = part:FindFirstChildWhichIsA("BasePart", true)
	if bp then return bp.Position end
end

function getAimScreenPos(part)
	local aimPos
	if AimAtTarget then
		if activeNode then
			aimPos = getTargetCenter(activeNode, activeTargetKind)
		end
		if not aimPos and currentTargetPart and currentTargetPart.Parent then
			aimPos = getPartPosition(currentTargetPart)
		end
	end
	aimPos = aimPos or getPartPosition(part)
	local x, y = getScreenPos(aimPos)
	if not x then
		x, y = getFallbackScreenPos()
	end
	return x, y
end

function isTargetAlive(node, kind)
	return isNodeAlive(node)
end

function getTargetHitboxes(node, kind)
	return getHitboxes(node)
end

function getTargetCenter(node, kind)
	return getNodeCenter(node)
end

function getTargetHealth(node, kind)
	return getNodeHealth(node)
end

function isNodeAlive(node)
	local billboardPart = node:FindFirstChild("BillboardPart")
	if not billboardPart then return false end
	local dead = billboardPart:FindFirstChild("Dead")
	if dead and dead.Value == true then return false end
	local health = billboardPart:FindFirstChild("Health")
	if health and health.Value <= 0 then return false end
	return true
end

function getNodeHealth(node)
	local billboard = node and node:FindFirstChild("BillboardPart")
	local health = billboard and billboard:FindFirstChild("Health")
	if health then return health.Value end
end

function resetAutoF()
	autoFActive = false
	stuckLastHealth = nil
	stuckSince = 0
end

function updateAutoF(node, kind)
	if UseFKey then
		autoFActive = false
		return
	end

	local health = getTargetHealth(node, kind)
	if not health then return end

	local now = tick()
	if stuckLastHealth == nil or health < stuckLastHealth then
		stuckLastHealth = health
		stuckSince = now
		autoFActive = false
	elseif now - stuckSince >= STUCK_F_SECONDS then
		autoFActive = true
	end
end

function getHitboxes(node)
	local hitboxes = {}
	for _, child in ipairs(node:GetChildren()) do
		if child.Name == "Hitbox" and child:IsA("BasePart") then
			table.insert(hitboxes, child)
		end
	end
	return hitboxes
end

function getCollectPart(obj)
	if obj:IsA("BasePart") then return obj end
	return obj:FindFirstChildWhichIsA("BasePart", true)
end

function getNodeCenter(node)
	local billboard = node:FindFirstChild("BillboardPart")
	if billboard then return billboard.Position end
	local hitboxes = getHitboxes(node)
	if #hitboxes > 0 then return hitboxes[1].Position end
end

function getValidTargets()
	local trees = {}
	local stones = {}
	pcall(function()
		local container = workspace:FindFirstChild("Interactions")
		if not container then
			pushFarmWarning("no_interactions", "Нет Interactions в workspace")
			return
		end
		clearFarmWarning("no_interactions")

		local nodesFolder = container:FindFirstChild("Nodes")
		if not nodesFolder then
			pushFarmWarning("no_nodes", "Нет папки Nodes")
			return
		end
		clearFarmWarning("no_nodes")

		if FarmTreesEnabled then
			local treeFolder = nodesFolder:FindFirstChild("Food")
			if treeFolder then
				for _, node in ipairs(treeFolder:GetChildren()) do
					if isNodeAlive(node) and not isNodeInBlockedZone(node) then
						table.insert(trees, { node = node, kind = "tree" })
					end
				end
			end
		end

		if FarmStonesEnabled then
			local stoneFolder = nodesFolder:FindFirstChild("Resources")
			if stoneFolder then
				for _, node in ipairs(stoneFolder:GetChildren()) do
					if isNodeAlive(node) and not isNodeInBlockedZone(node) then
						table.insert(stones, { node = node, kind = "stone" })
					end
				end
			end
		end

	end)

	local targets = {}
	for _, list in ipairs({ trees, stones }) do
		for _, item in ipairs(list) do
			table.insert(targets, item)
		end
	end

	if not FarmTreesEnabled and not FarmStonesEnabled then
		pushFarmWarning("no_mode", "Выключены все типы целей")
	elseif #targets == 0 then
		pushFarmWarning("no_targets", "Нет целей для добычи")
	else
		clearFarmWarning("no_targets")
		clearFarmWarning("no_mode")
	end

	return targets
end

function refreshTargetCounts()
	local trees, stones = 0, 0
	pcall(function()
		local container = workspace:FindFirstChild("Interactions")
		if not container then return end
		local nodesFolder = container:FindFirstChild("Nodes")
		if not nodesFolder then return end
		local treeFolder = nodesFolder:FindFirstChild("Food")
		if treeFolder then
			for _, node in ipairs(treeFolder:GetChildren()) do
				if isNodeAlive(node) then trees += 1 end
			end
		end
		local stoneFolder = nodesFolder:FindFirstChild("Resources")
		if stoneFolder then
			for _, node in ipairs(stoneFolder:GetChildren()) do
				if isNodeAlive(node) then stones += 1 end
			end
		end
	end)
	cachedTreeCount = trees
	cachedStoneCount = stones
	return trees, stones
end

function pickBestTarget(targets)
	if #targets == 0 then return nil end
	if TargetPickMode == "random" then
		return targets[math.random(1, #targets)]
	end
	local refPos = getHubPosition()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp and not refPos then
		refPos = hrp.Position
	end
	if not refPos then
		return targets[1]
	end

	local best, bestDist = nil, nil
	for _, target in ipairs(targets) do
		local center = getTargetCenter(target.node, target.kind)
		if center then
			local dist = (center - refPos).Magnitude
			if not bestDist or dist < bestDist then
				best = target
				bestDist = dist
			end
		end
	end
	return best or targets[1]
end

function rebuildPatrolPoints()
	patrolPoints = {}
	pcall(function()
		for _, target in ipairs(getValidTargets()) do
			local center = getTargetCenter(target.node, target.kind)
			if center then
				table.insert(patrolPoints, center)
			end
		end
	end)
	patrolIndex = 1
end

function teleportSearch()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local pos
	if #patrolPoints > 0 then
		local point = patrolPoints[patrolIndex]
		if point then
			pos = point + Vector3.new(0, getTeleportHeightForKind(activeTargetKind), 0)
		end
		patrolIndex += 1
		if patrolIndex > #patrolPoints then
			patrolIndex = 1
		end
	end

	if not pos then
		searchAngle += 0.35
		if searchRadius > 400 then
			searchRadius = 80
		else
			searchRadius += 15
		end
		local origin = hrp.Position
		pos = origin + Vector3.new(
			math.cos(searchAngle) * searchRadius,
			getTeleportHeightForKind(activeTargetKind),
			math.sin(searchAngle) * searchRadius
		)
	end

	hrp.CFrame = CFrame.new(pos)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

DROP_MODEL_HINTS = {
	"FoodModel",
	"WoodResourcesModel",
	"CopperResourcesModel",
	"LeafResourcesModel",
	"ResourcesModel",
}

function isResourceDropModel(obj)
	if not obj:IsA("Model") then return false end
	for _, hint in ipairs(DROP_MODEL_HINTS) do
		if obj.Name:find(hint) then
			return true
		end
	end
	return false
end

function getDropKindFromModel(model)
	if not model then return activeTargetKind end
	local name = model.Name
	if name:find("CopperResources") or name:find("LeafResources") then
		return "stone"
	end
	if name:find("FoodModel") or name:find("WoodResources") then
		return "tree"
	end
	return activeTargetKind
end

function isDropIgnored(part)
	if ignoredDrops[part] then return true end
	if part.Parent and ignoredDrops[part.Parent] then return true end
	return false
end

function markDropCollected(part)
	ignoredDrops[part] = true
	local kind = activeTargetKind
	if part.Parent and part.Parent:IsA("Model") then
		kind = getDropKindFromModel(part.Parent)
		ignoredDrops[part.Parent] = true
	end
	if kind == "stone" then
		sessionStoneDrops += 1
	else
		sessionTreeDrops += 1
	end
end

function isValidCollectDrop(part, nodeCenter)
	if not part or not part.Parent then return false end
	if isDropIgnored(part) then return false end
	if isPosInBlockedZone(part.Position) then return false end
	if nodeCenter and part.Position.Y - nodeCenter.Y > 10 then return false end
	return true
end

function findCameraResourceDrops(nodeCenter)
	local drops = {}
	if not nodeCenter then return drops end

	local cameraRoot = workspace:FindFirstChild("Camera")
	if not cameraRoot then
		pushFarmWarning("no_camera", "Нет Camera — лут не найден")
		return drops
	end
	clearFarmWarning("no_camera")

	for _, child in ipairs(cameraRoot:GetChildren()) do
		if isResourceDropModel(child) and child.Parent then
			local part = getCollectPart(child)
			if part and isValidCollectDrop(part, nodeCenter) then
				local dist = (Vector3.new(part.Position.X, nodeCenter.Y, part.Position.Z) - nodeCenter).Magnitude
				if dist <= COLLECT_RADIUS then
					table.insert(drops, part)
				end
			end
		end
	end

	table.sort(drops, function(a, b)
		local da = (Vector3.new(a.Position.X, nodeCenter.Y, a.Position.Z) - nodeCenter).Magnitude
		local db = (Vector3.new(b.Position.X, nodeCenter.Y, b.Position.Z) - nodeCenter).Magnitude
		return da < db
	end)

	return drops
end

function findDropsNear(node)
	local center = getNodeCenter(node)
	if not center then return {} end
	return findCameraResourceDrops(center)
end

function collectPart(part)
	if not part then return end
	markDropCollected(part)

	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt and part.Parent then
		prompt = part.Parent:FindFirstChildWhichIsA("ProximityPrompt", true)
	end
	if prompt then
		pcall(function() fireproximityprompt(prompt) end)
	end

	if shouldPressF() then
		pressF()
	end
end

function collectAllDrops(node, runId)
	farmPhase = "collect"
	orbitAngle = 0
	releaseMouseHold()
	currentTargetPart = nil
	local center = getNodeCenter(node)
	ignoredDrops = {}

	for _ = 1, 20 do
		if not shouldFarmContinue(runId) then break end
		local drops = findDropsNear(node)
		if #drops == 0 then break end

		for _, drop in ipairs(drops) do
			if not shouldFarmContinue(runId) then break end
			if not isValidCollectDrop(drop, center) then continue end

			local dropPos = drop.Position
			teleportHrpTo(dropPos)
			currentTargetPart = drop
			if not interruptibleWait(0.08, runId) then break end
			teleportHrpTo(dropPos)
			collectPart(drop)
			if not interruptibleWait(0.05, runId) then break end
			currentTargetPart = nil
		end

		if not interruptibleWait(0.1, runId) then break end
	end

	currentTargetPart = nil
	stopCharacterMotion()
end

function attackPart(part)
	if not part then return end
	if AttackDelay > 0 and (tick() - lastAttackAt) < AttackDelay then
		return
	end
	lastAttackAt = tick()
	pressF()
	local x, y = getAimScreenPos(part)
	if not x or not y then return end
	if UseClick then
		clickAt(x, y)
	elseif LegitMouseCapture then
		holdMouseAt(x, y)
	end
end

function dropsAreSettled(drops)
	for _, drop in ipairs(drops) do
		if drop.AssemblyLinearVelocity.Magnitude > 1.5 then
			return false
		end
	end
	return true
end

function waitAndScanDrops(node, runId)
	farmPhase = "wait"
	orbitAngle = 0
	releaseMouseHold()
	currentTargetPart = nil
	if not interruptibleWait(0.25, runId) then return {} end

	local deadline = tick() + 3
	while shouldFarmContinue(runId) and tick() < deadline do
		local drops = findDropsNear(node)
		if #drops > 0 then
			if dropsAreSettled(drops) then return drops end
		elseif tick() > deadline - 1 then
			return {}
		end
		if not interruptibleWait(0.1, runId) then return {} end
	end

	return findDropsNear(node)
end

function getMineAnchorPos(node, kind, hitboxPos)
	if kind == "stone" and node then
		local center = getNodeCenter(node)
		if center then
			return center
		end
	end
	return hitboxPos
end

function teleportToTarget()
	if farmPhase ~= "mine" then return end
	if not currentTargetPart or not currentTargetPart.Parent then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local partPos = getPartPosition(currentTargetPart)
	if not partPos then return end

	local anchor = getMineAnchorPos(activeNode, activeTargetKind, partPos)
	local height = getTeleportHeightForKind(activeTargetKind)
	local baseY = anchor.Y + height
	local pos

	if OrbitEnabled then
		orbitAngle += OrbitSpeed * (1 / 60)
		local radius = OrbitDiameter / 2
		pos = Vector3.new(
			anchor.X + math.cos(orbitAngle) * radius,
			baseY,
			anchor.Z + math.sin(orbitAngle) * radius
		)
	else
		pos = Vector3.new(anchor.X, baseY, anchor.Z)
	end

	if AimAtTarget and partPos then
		applyHrpCFrameInstant(hrp, CFrame.new(pos, partPos))
	else
		applyHrpCFrameInstant(hrp, CFrame.new(pos))
	end

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	if LegitMouseCapture and currentTargetPart then
		local x, y = getAimScreenPos(currentTargetPart)
		if x and y then
			if not UseClick then
				holdMouseAt(x, y)
			elseif AimAtTarget then
				moveMouseToScreen(x, y)
			end
		end
	end
end

function isOurGui(gui)
	if not gui then return false end
	if gui:GetAttribute("MaxiHubBlackScreen") == true then return true end
	if blackScreenGui and gui == blackScreenGui then return true end
	return screenGuiRef and (gui == screenGuiRef or gui:IsDescendantOf(screenGuiRef))
end

function looksLikeTrade(inst)
	local name = string.lower(inst.Name)
	for _, hint in ipairs(TRADE_HINTS) do
		if string.find(name, hint, 1, true) then
			return true
		end
	end
	return false
end

function hideTradeObject(inst)
	if isOurGui(inst) then return end
	if inst:IsA("ScreenGui") then
		inst.Enabled = false
	elseif inst:IsA("GuiObject") then
		inst.Visible = false
		inst.Active = false
	end
end

function scanTrades(root)
	if not BlockTrades or not root then return end
	if looksLikeTrade(root) then
		hideTradeObject(root)
	end
	for _, obj in ipairs(root:GetDescendants()) do
		if looksLikeTrade(obj) then
			hideTradeObject(obj)
		end
	end
end

function hideOtherGuis()
	if not BlockUiDuringFarm then return end
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and not isOurGui(child) and child.Enabled then
			hiddenGuis[child] = true
			child.Enabled = false
		end
	end
end

function clearTable(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

function stopSafeMode()
	for _, conn in pairs(safeModeConnections) do
		if conn then
			pcall(function() conn:Disconnect() end)
		end
	end
	clearTable(safeModeConnections)

	local toRestore = {}
	for gui, wasEnabled in pairs(hiddenGuis) do
		if gui.Parent and wasEnabled then
			toRestore[gui] = true
		end
	end
	clearTable(hiddenGuis)

	if next(toRestore) then
		task.defer(function()
			for gui in pairs(toRestore) do
				if gui.Parent then
					gui.Enabled = true
				end
			end
		end)
	end
end

function startSafeMode()
	stopSafeMode()
	hideOtherGuis()
	task.defer(function()
		if FarmEnabled then
			scanTrades(playerGui)
		end
	end)

	safeModeConnections.child = playerGui.ChildAdded:Connect(function(child)
		if not FarmEnabled then return end
		task.defer(function()
			if BlockUiDuringFarm and child:IsA("ScreenGui") and not isOurGui(child) then
				hiddenGuis[child] = true
				child.Enabled = false
			end
			scanTrades(child)
		end)
	end)

	safeModeConnections.desc = playerGui.DescendantAdded:Connect(function(inst)
		if not FarmEnabled or not BlockTrades then return end
		if looksLikeTrade(inst) then
			task.defer(function()
				hideTradeObject(inst)
			end)
		end
	end)
end

function getResourcesFolder()
	local data = player:FindFirstChild("Data")
	if not data then return nil end
	return data:FindFirstChild("Resources")
end

function getResourceAmount(itemName)
	local resources = getResourcesFolder()
	if not resources then return 0 end
	local item = resources:FindFirstChild(itemName)
	if item and (item:IsA("IntValue") or item:IsA("NumberValue")) then
		return item.Value
	end
	return 0
end

function getSellTriggerAmount()
	local maxAmount = 0
	local maxName = "Coconut"
	for _, itemName in ipairs(SELL_ITEMS) do
		local amount = getResourceAmount(itemName)
		if amount > maxAmount then
			maxAmount = amount
			maxName = itemName
		end
	end
	return maxAmount, maxName
end

function needsAutoSell()
	if not AutoSellEnabled then return false end
	for _, itemName in ipairs(SELL_ITEMS) do
		if getResourceAmount(itemName) > SellCoconutThreshold then
			return true
		end
	end
	return false
end

function getFarmSeconds()
	local total = farmTimeTotal
	if FarmEnabled and farmTimeStarted > 0 then
		total += tick() - farmTimeStarted
	end
	return math.floor(total)
end

function httpRequest(opts)
	local function tryCall(fn)
		local ok, res = pcall(fn)
		if ok then
			return res
		end
		return nil
	end

	if typeof(request) == "function" then
		local res = tryCall(function()
			return request(opts)
		end)
		if res then return res end
	end
	if syn and syn.request then
		local res = tryCall(function()
			return syn.request(opts)
		end)
		if res then return res end
	end
	if http and http.request then
		local res = tryCall(function()
			return http.request(opts)
		end)
		if res then return res end
	end
	if HttpService and HttpService.RequestAsync then
		local res = tryCall(function()
			return HttpService:RequestAsync({
				Url = opts.Url,
				Method = opts.Method or "POST",
				Headers = opts.Headers,
				Body = opts.Body,
			})
		end)
		if res then return res end
	end
	return nil
end

function postDiscordWebhook(webhook, body)
	webhook = webhook:gsub("^%s+", ""):gsub("%s+$", "")
	if webhook == "" then
		return false, "Webhook пустой"
	end

	local res = httpRequest({
		Url = webhook,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = body,
	})

	if res then
		local code = res.StatusCode or res.status or res.Status
		if code and tonumber(code) then
			local n = tonumber(code)
			if n >= 200 and n < 300 then
				return true, "Отправлено"
			end
			return false, "HTTP " .. tostring(code)
		end
		if res.Success == true then
			return true, "Отправлено"
		end
		if res.Success == false then
			return false, "HTTP ошибка"
		end
		return true, "Отправлено"
	end

	local ok, err = pcall(function()
		HttpService:PostAsync(webhook, body, Enum.HttpContentType.ApplicationJson, false)
	end)
	if ok then
		return true, "Отправлено"
	end

	return false, tostring(err or "Ошибка отправки"):sub(1, 96)
end

function sendDiscordEmbed(webhook, title, color, extraFields)
	if not webhook or webhook == "" then return false, "Webhook пустой" end
	local fields = {
		{ name = "Игрок", value = player.Name .. " (`" .. tostring(player.UserId) .. "`)", inline = false },
	}
	if extraFields then
		for _, field in ipairs(extraFields) do
			table.insert(fields, field)
		end
	end
	local body = HttpService:JSONEncode({
		embeds = {
			{
				title = title,
				color = color or 3447003,
				fields = fields,
				footer = { text = "MAXI HUB" },
				timestamp = DateTime.now():ToIsoDate(),
			},
		},
	})
	return postDiscordWebhook(webhook, body)
end

function getResourcesOverOneText()
	local resources = getResourcesFolder()
	if not resources then return "—" end

	local items = {}
	for _, child in ipairs(resources:GetChildren()) do
		if (child:IsA("IntValue") or child:IsA("NumberValue")) and child.Value > 1 then
			table.insert(items, { name = child.Name, val = child.Value })
		end
	end

	table.sort(items, function(a, b)
		return a.val > b.val
	end)

	local lines = {}
	for _, item in ipairs(items) do
		table.insert(lines, item.name .. ": " .. tostring(item.val))
	end

	local text = table.concat(lines, "\n")
	if #text > 1000 then
		text = string.sub(text, 1, 997) .. "..."
	end
	return #lines > 0 and text or "—"
end

function getSessionStatsFields()
	local secs = getFarmSeconds()
	local mins = math.floor(secs / 60)
	local secRem = secs % 60
	local timeStr
	if mins > 0 then
		timeStr = string.format("%dм %dс", mins, secRem)
	else
		timeStr = secs .. "с"
	end
	return {
		{ name = "Срубил деревьев", value = tostring(sessionTreesMined), inline = true },
		{ name = "Срубил камней", value = tostring(sessionStonesMined), inline = true },
		{ name = "Собрал лут (дер.)", value = tostring(sessionTreeDrops), inline = true },
		{ name = "Собрал лут (кам.)", value = tostring(sessionStoneDrops), inline = true },
		{ name = "Время фарма", value = timeStr, inline = true },
		{ name = "Режим", value = getFarmModeText(), inline = true },
		{ name = "Resources (>1)", value = getResourcesOverOneText(), inline = false },
	}
end

function logFarmSessionDiscord(title, color)
	if not DiscordReportsEnabled then return end
	local webhook = getFarmDiscordWebhook()
	if not webhook or webhook == "" then return end
	local fields = {}
	for _, field in ipairs(getSessionStatsFields()) do
		table.insert(fields, field)
	end
	sendDiscordEmbed(webhook, title, color, fields)
end

function waitForCharacterHrp(timeout)
	local deadline = tick() + (timeout or 12)
	while tick() < deadline do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			return hrp
		end
		task.wait(0.1)
	end
	return nil
end

function sellWait(seconds, opts)
	if opts and opts.force then
		task.wait(seconds)
		return true
	end
	return interruptibleWait(seconds, opts and opts.runId)
end

function getSellRemote()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then return nil end
	return remotes:WaitForChild("SellItemRemote", 15)
end

function getWorldTeleportRemote()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then return nil end
	return remotes:WaitForChild("WorldTeleportRemote", 15)
end

function worldTeleport(worldId)
	local remote = getWorldTeleportRemote()
	if not remote then return false end
	local ok = pcall(function()
		local args = {
			[1] = worldId,
			[2] = {},
		}
		remote:InvokeServer(table.unpack(args))
	end)
	return ok
end

function sellResourceItem(itemName)
	local remote = getSellRemote()
	if not remote then return false end
	local ok = pcall(function()
		local args = {
			[1] = {
				["ItemName"] = itemName,
				["Amount"] = SellBatchAmount,
			},
		}
		remote:FireServer(table.unpack(args))
	end)
	return ok
end

function runSellCycle(runId, opts)
	opts = opts or {}
	if sellInProgress then
		return false, "Уже идёт продажа"
	end
	if not opts.force then
		if not AutoSellEnabled then return false end
		if not needsAutoSell() then return false end
	end

	local function setStatus(msg)
		if opts.onStatus then
			pcall(opts.onStatus, msg)
		end
	end

	local function waitStep(sec)
		return sellWait(sec, { force = opts.force, runId = runId })
	end

	local function sellLoopContinue()
		if opts.force then
			return sellInProgress
		end
		return shouldFarmContinue(runId)
	end

	sellInProgress = true
	farmPhase = "sell"
	releaseMouseHold()
	releaseFKey()
	stopCharacterMotion()
	clearFarmWarning("sell_fail")

	saveSellState("sell", {
		manual = opts.force == true,
		resumeFarm = opts.resumeFarm == true,
	})

	setStatus("ТП на продажу...")
	if not worldTeleport(SELL_WORLD_ID) then
		clearSellState()
		pushFarmWarning("sell_fail", "Не удалось телепорт на продажу")
		sellInProgress = false
		farmPhase = "idle"
		return false, "Телепорт на продажу не удался"
	end

	setStatus("Ждём загрузку мира...")
	waitForCharacterHrp(12)
	if not waitStep(SELL_WAIT_AFTER_TP) then
		clearSellState()
		sellInProgress = false
		farmPhase = "idle"
		return false, "Продажа прервана"
	end

	local currentState = loadSellState()
	if not currentState or currentState.phase ~= "sell" then
		sellInProgress = false
		farmPhase = "idle"
		return true, "Продажа продолжится после перезагрузки"
	end

	setStatus("Продаём ресурсы...")
	local soldAny = executeSellItems(waitStep, sellLoopContinue)

	if not soldAny then
		pushFarmWarning("sell_fail", "SellItemRemote недоступен")
	end

	if not waitStep(1) then
		clearSellState()
		sellInProgress = false
		farmPhase = "idle"
		return false, "Продажа прервана"
	end

	saveSellState("return", {
		manual = opts.force == true,
		resumeFarm = opts.resumeFarm == true,
	})

	setStatus("Возврат на фарм...")
	if not worldTeleport(FARM_WORLD_ID) then
		pushFarmWarning("sell_fail", "Не удалось вернуться на фарм")
	end

	waitForCharacterHrp(12)
	waitStep(2)

	local returnState = loadSellState()
	if returnState and returnState.phase == "return" then
		finalizeSellResume(opts, soldAny)
	end

	sellInProgress = false
	farmPhase = "idle"
	clearFarmWarning("sell_fail")

	if not soldAny then
		return false, "Не удалось продать (нет remote)"
	end

	return true, "Продажа завершена"
end

function runAutoSell(runId)
	runSellCycle(runId, { force = false, resumeFarm = true })
end

function runManualSell(doneCb)
	if sellInProgress then
		if doneCb then doneCb(false, "Уже идёт продажа") end
		return
	end

	task.spawn(function()
		local wasFarming = FarmEnabled
		if wasFarming then
			farmRunId = farmRunId + 1
		end
		farmCheckPause = true
		pcall(releaseMouseHold)
		pcall(releaseFKey)
		pcall(stopCharacterMotion)

		local ok, msg = runSellCycle(nil, {
			force = true,
			resumeFarm = wasFarming,
			onStatus = function(statusMsg)
				if sellStatus and sellStatus.Parent then
					sellStatus.Text = statusMsg
				end
			end,
		})

		farmCheckPause = false
		if wasFarming and FarmEnabled and not hasPendingSellState() then
			startFarm()
		end
		if doneCb then doneCb(ok, msg) end
	end)
end

function maybeRunAutoSell(runId)
	if not AutoSellEnabled or sellInProgress then return end
	local now = tick()
	if now - lastSellCheckAt < SellCheckInterval then return end
	lastSellCheckAt = now
	if needsAutoSell() then
		runAutoSell(runId)
	end
end

function maybeRunFarmReport()
	if not FarmEnabled then return end
	local now = tick()
	if now - lastFarmReportAt < FARM_REPORT_INTERVAL then return end
	lastFarmReportAt = now
	logFarmSessionDiscord("Отчёт фарма", 3447003)
end

function runSearchPhase(runId)
	farmPhase = "search"
	releaseMouseHold()
	currentTargetPart = nil

	local hubPlaced = false
	while shouldFarmContinue(runId) do
		refreshTargetCounts()
		local targets = getValidTargets()
		if #targets > 0 then
			farmPhase = "idle"
			return targets
		end
		if not shouldFarmContinue(runId) then break end
		if HubWaitEnabled then
			if not hubRestWait(runId, not hubPlaced) then break end
			hubPlaced = true
		end
		task.wait(0.3)
	end

	farmPhase = "idle"
	return {}
end

function killFarmLoops(opts)
	opts = opts or {}
	if FarmEnabled and farmTimeStarted > 0 then
		farmTimeTotal += tick() - farmTimeStarted
		farmTimeStarted = 0
	end

	FarmEnabled = false
	farmPhase = "idle"
	farmRunId += 1
	currentTargetPart = nil
	activeNode = nil
	activeTargetKind = "tree"
	pcall(releaseMouseHold)
	pcall(releaseFKey)
	pcall(stopCharacterMotion)
	pcall(resetAutoF)
	ignoredDrops = {}

	if teleportConnection then
		pcall(function() teleportConnection:Disconnect() end)
		teleportConnection = nil
	end

	manualSellToken = manualSellToken + 1
	sellInProgress = false

	farmThread = nil
	if not opts.keepRender3d then
		pcall(onFarmRender3dStop)
	end
	pcall(stopSafeMode)
end

function stopFarm()
	killFarmLoops()
end

function softCleanup()
	flushSaveConfig()
	stopFarm()
	stopSafeMode()
	stopCameraLoop()
	destroyBlockedZoneVisual()
	cleanupRender3d()
	if screenGuiRef and screenGuiRef.Parent then
		pcall(function() screenGuiRef:Destroy() end)
	elseif screenGui and screenGui.Parent then
		pcall(function() screenGui:Destroy() end)
	end
end

function fullUnload()
	softCleanup()
	restoreCamera()
end

genv.MaxiHubToggleRender3d = toggleRender3d
genv.MaxiHubStop = softCleanup
genv.MaxiHubPatchConfig = patchConfigTable
genv.MaxiHubFlushConfig = flushSaveConfig

if pendingPrevStop and pendingPrevStop ~= softCleanup then
	pcall(pendingPrevStop)
end
pendingPrevStop = nil

function startFarm()
	killFarmLoops({ keepRender3d = true })
	FarmEnabled = true
	farmTimeStarted = tick()
	lastFarmReportAt = tick()
	local myRunId = farmRunId
	onFarmRender3dStart()
	task.defer(startSafeMode)

	teleportConnection = RunService.Heartbeat:Connect(function()
		if not shouldFarmContinue(myRunId) then return end
		if farmPhase == "collect" or farmPhase == "wait" or farmPhase == "sell" or farmPhase == "hub" or farmPhase == "search" or farmPhase == "travel" then return end
		if farmPhase == "mine" and currentTargetPart then
			pcall(teleportToTarget)
		end
	end)

	farmThread = task.spawn(function()
		local hubPrimed = false
		while shouldFarmContinue(myRunId) do
			local ok, err = pcall(function()
			maybeRunAutoSell(myRunId)
			if not shouldFarmContinue(myRunId) then return end
			maybeRunFarmReport()
			if not shouldFarmContinue(myRunId) then return end

			if not hubPrimed then
				hubPrimed = true
				captureHubPosition()
				if HubWaitEnabled and not hubRestWait(myRunId) then return end
			end

			local targets = getValidTargets()
			refreshTargetCounts()

			if #targets == 0 then
				targets = runSearchPhase(myRunId)
				if not shouldFarmContinue(myRunId) or #targets == 0 then
					task.wait(0.2)
					return
				end
				refreshTargetCounts()
			end

			local picked = pickBestTarget(targets)
			if not picked then
				task.wait(0.2)
				return
			end

			activeNode = picked.node
			activeTargetKind = picked.kind
			orbitAngle = 0
			resetAutoF()

			local hitboxes = getTargetHitboxes(activeNode, activeTargetKind)
			if #hitboxes == 0 then
				pushFarmWarning("no_hitbox", "У цели нет Hitbox")
				task.wait(0.5)
				return
			end
			clearFarmWarning("no_hitbox")

			currentTargetPart = hitboxes[1]
			local partPos = getPartPosition(currentTargetPart)
			if partPos then
				local anchor = getMineAnchorPos(activeNode, activeTargetKind, partPos)
				local height = getTeleportHeightForKind(activeTargetKind)
				local approachPos = Vector3.new(anchor.X, anchor.Y + height, anchor.Z)
				farmPhase = "travel"
				local useSmooth = TeleportMode == "smooth"
				if not teleportHrpTo(approachPos, { smooth = useSmooth, runId = myRunId }) then return end
			end

			farmPhase = "mine"
			local mineDeadline = tick() + 60

			while shouldFarmContinue(myRunId)
				and tick() < mineDeadline
				and isTargetAlive(activeNode, activeTargetKind) do
				updateAutoF(activeNode, activeTargetKind)
				if autoFActive then
					pushFarmWarning("stuck_mining", "Долго не ломается — жму F")
				else
					clearFarmWarning("stuck_mining")
				end
				attackPart(currentTargetPart)
				if AttackDelay > 0 then
					task.wait(AttackDelay)
				end
			end

			if not shouldFarmContinue(myRunId) then return end

			orbitAngle = 0
			releaseMouseHold()
			currentTargetPart = nil

			if activeTargetKind == "stone" then
				sessionStonesMined += 1
			else
				sessionTreesMined += 1
			end

			waitAndScanDrops(activeNode, myRunId)
			if not shouldFarmContinue(myRunId) then return end
			collectAllDrops(activeNode, myRunId)

			activeNode = nil
			activeTargetKind = "tree"
			currentTargetPart = nil
			stopCharacterMotion()
			if not returnToHubAfterNode(myRunId) then return end
			end)

			if not ok then
				if isCancelError(err) then break end
				warn("[MAXI HUB] farm:", err)
				if not shouldFarmContinue(myRunId) then break end
				task.wait(0.5)
			end
		end

		if myRunId == farmRunId then
			currentTargetPart = nil
			if not sellInProgress then
				farmPhase = "idle"
			end
		end
	end)
end

genv.MaxiHubGetStats = function()
	return {
		enabled = FarmEnabled,
		farmSeconds = getFarmSeconds(),
		phase = farmPhase,
		trees = cachedTreeCount,
		stones = cachedStoneCount,
		drops = cachedDropCount,
		treeDrops = sessionTreeDrops,
		stoneDrops = sessionStoneDrops,
		treesMined = sessionTreesMined,
		stonesMined = sessionStonesMined,
	}
end

genv.MaxiHubPauseForInventory = function()
	farmCheckPause = true
	releaseMouseHold()
	releaseFKey()
	stopCharacterMotion()
	if BlockUiDuringFarm and FarmEnabled then
		genv.MaxiHubInvUnblockedUi = true
		stopSafeMode()
	end
end

genv.MaxiHubResumeAfterInventory = function()
	farmCheckPause = false
	if genv.MaxiHubInvUnblockedUi and FarmEnabled and BlockUiDuringFarm then
		genv.MaxiHubInvUnblockedUi = nil
		startSafeMode()
	end
end


-- ===== UI (maxi-hub-ui.lua — отдельный файл, loadstring = свой scope) =====
do
	local genvUi = typeof(getgenv) == "function" and getgenv() or _G
	local preferLocal = type(genvUi.MaxiHubLocalRoot) == "string" and genvUi.MaxiHubLocalRoot ~= ""
	if preferLocal then
		genvUi._MaxiHubUILibrary = nil
	end
	if not genvUi._MaxiHubUILibrary then
		local source
		local base = genvUi.MaxiHubOfficialRaw or genvUi.MaxiHubRemoteBase
		local repoOnly = genvUi.MaxiHubRepoOnly == true
		if preferLocal and typeof(readfile) == "function" and typeof(isfile) == "function" then
			for _, p in ipairs(getWorkspaceModulePaths("maxi-hub-ui.lua")) do
				if isfile(p) then
					source = readfile(p)
					break
				end
			end
		end
		if not source and base and typeof(game.HttpGet) == "function" then
			local function isErrorPage(src)
				if type(src) ~= "string" or src == "" or src:sub(1, 1) ~= "<" then
					return false
				end
				local head = src:sub(1, 400):lower()
				return head:find("<!doctype", 1, true) ~= nil
					or head:find("<html", 1, true) ~= nil
			end
			local ok, remote = pcall(function()
				return game:HttpGet(base .. "maxi-hub-ui.lua?v=" .. tostring(os.time()), true)
			end)
			if ok and type(remote) == "string" and remote ~= "" then
				if not isErrorPage(remote) then
					source = remote
				elseif repoOnly then
					error("[MAXI HUB] UI только с официального репо")
				end
			end
		end
		if not source and not repoOnly and typeof(readfile) == "function" and typeof(isfile) == "function" then
			for _, p in ipairs(getWorkspaceModulePaths("maxi-hub-ui.lua")) do
				if isfile(p) then
					source = readfile(p)
					break
				end
			end
		end
		if not source then
			error("[MAXI HUB] Нужен maxi-hub-ui.lua (официальный репо или workspace)")
		end
		local chunk, cerr = loadstring(source, "@maxi-hub-ui.lua")
		if not chunk then error("[MAXI HUB] UI compile: " .. tostring(cerr)) end
		local ok, lib = pcall(chunk)
		if not ok then error("[MAXI HUB] UI run: " .. tostring(lib)) end
		genvUi._MaxiHubUILibrary = lib
	end
end
MaxiHubUILib = (typeof(getgenv) == "function" and getgenv() or _G)._MaxiHubUILibrary

-- Габариты UI (см. .cursor/rules/ui-layout.mdc — не выдумывать, менять осознанно)
UI_LAYOUT = {
	PANEL_W = 200,
	PANEL_H = 200,
	PANEL_COL2_X = 216,
	ROW3_Y = 224,
	FULL_W = 420,
	SLIDER_PANEL_H = 160,
	SESSION_BODY_Y = 35,
	SLIDER_BODY_Y = 40,
	MINE_BOX_H = 174,
	SLIDERS_BOX_H = 112,
	SAFE_BOX_H = 88,
	TOGGLE_Y_STEP = 44,
	SLIDER_Y_STEP = 60,
}

-- Вкладка «Обновления»
function buildMaxiHubChangelogTab(page, uiKit)
	local changelog = loadChangelogLib()
	local scroll = uiKit.makeScrollPage(page)
	local wrap = uiKit.makeListWrap(scroll)

	local buildTag = (genv.MaxiHubVersion and tostring(genv.MaxiHubVersion))
		or SCRIPT_VERSION
		or (changelog and changelog.current)
		or "—"

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = uiKit.COLORS.panel
	header.BorderSizePixel = 0
	header.Font = Enum.Font.GothamBold
	header.TextSize = 12
	header.TextColor3 = uiKit.COLORS.accent
	header.Text = L("changelog_current") .. ": " .. buildTag
	header.LayoutOrder = 1
	header.Parent = wrap
	uiKit.addCorner(header, 8)

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 12)
	headerPad.PaddingRight = UDim.new(0, 12)
	headerPad.Parent = header

	local layoutOrder = 2
	local entries = changelog and changelog.entries
	if type(entries) == "table" and #entries > 0 then
		for _, entry in ipairs(entries) do
			if type(entry) == "table" and type(entry.changes) == "table" and #entry.changes > 0 then
				local card = Instance.new("Frame")
				card.Size = UDim2.new(1, 0, 0, 0)
				card.AutomaticSize = Enum.AutomaticSize.Y
				card.BackgroundColor3 = uiKit.COLORS.panel
				card.BorderSizePixel = 0
				card.LayoutOrder = layoutOrder
				layoutOrder += 1
				card.Parent = wrap
				uiKit.addCorner(card, 8)

				local cardPad = Instance.new("UIPadding")
				cardPad.PaddingTop = UDim.new(0, 10)
				cardPad.PaddingBottom = UDim.new(0, 10)
				cardPad.PaddingLeft = UDim.new(0, 12)
				cardPad.PaddingRight = UDim.new(0, 12)
				cardPad.Parent = card

				local cardList = Instance.new("UIListLayout")
				cardList.SortOrder = Enum.SortOrder.LayoutOrder
				cardList.Padding = UDim.new(0, 6)
				cardList.Parent = card

				local versionText = type(entry.version) == "string" and entry.version or "—"
				local dateText = type(entry.date) == "string" and entry.date or ""
				local title = Instance.new("TextLabel")
				title.Size = UDim2.new(1, 0, 0, 18)
				title.BackgroundTransparency = 1
				title.Font = Enum.Font.GothamBold
				title.TextSize = 12
				title.TextColor3 = uiKit.COLORS.text
				title.TextXAlignment = Enum.TextXAlignment.Left
				title.Text = versionText .. (dateText ~= "" and (" · " .. dateText) or "")
				title.LayoutOrder = 1
				title.Parent = card

				for i, line in ipairs(entry.changes) do
					if type(line) == "string" and line ~= "" then
						local row = Instance.new("TextLabel")
						row.Size = UDim2.new(1, 0, 0, 0)
						row.AutomaticSize = Enum.AutomaticSize.Y
						row.BackgroundTransparency = 1
						row.Font = Enum.Font.Gotham
						row.TextSize = 11
						row.TextColor3 = uiKit.COLORS.muted
						row.TextWrapped = true
						row.TextXAlignment = Enum.TextXAlignment.Left
						row.Text = "• " .. line
						row.LayoutOrder = i + 1
						row.Parent = card
					end
				end
			end
		end
	else
		local wip = Instance.new("TextLabel")
		wip.Size = UDim2.new(1, 0, 0, 48)
		wip.BackgroundColor3 = uiKit.COLORS.panel
		wip.BorderSizePixel = 0
		wip.Font = Enum.Font.Gotham
		wip.TextSize = 13
		wip.TextColor3 = uiKit.COLORS.muted
		wip.Text = L("changelog_wip")
		wip.LayoutOrder = 2
		wip.Parent = wrap
		uiKit.addCorner(wip, 8)
		registerLocale(wip, "changelog_wip")
	end
end

-- Вкладка «Кредиты» — обязательная, копировать в лаунчеры других игр
function buildMaxiHubCreditsTab(page, uiKit, opts)
	opts = opts or {}
	local telegram = opts.telegram or TELEGRAM_LINK
	local scriptLine = opts.scriptLine or L("script_line")

	local credScroll = uiKit.makeScrollPage(page)
	local credWrap = uiKit.makeListWrap(credScroll)

	local about = Instance.new("TextLabel")
	about.Size = UDim2.new(1, 0, 0, 64)
	about.BackgroundColor3 = uiKit.COLORS.panel
	about.BorderSizePixel = 0
	about.Font = Enum.Font.Gotham
	about.TextSize = 12
	about.TextColor3 = uiKit.COLORS.text
	about.TextWrapped = true
	about.Text = SCRIPT_TITLE .. "\n" .. scriptLine .. "\n" .. L("credits_thanks")
	about.LayoutOrder = 1
	about.Parent = credWrap
	creditsAboutLabel = about
	uiKit.addCorner(about, 8)

	local aboutPad = Instance.new("UIPadding")
	aboutPad.PaddingTop = UDim.new(0, 10)
	aboutPad.PaddingLeft = UDim.new(0, 12)
	aboutPad.PaddingRight = UDim.new(0, 12)
	aboutPad.Parent = about

	local tgButton = Instance.new("TextButton")
	tgButton.Size = UDim2.new(1, 0, 0, 40)
	tgButton.BackgroundColor3 = uiKit.COLORS.accent
	tgButton.BorderSizePixel = 0
	tgButton.Font = Enum.Font.GothamBold
	tgButton.TextSize = 13
	tgButton.TextColor3 = uiKit.COLORS.bg
	tgButton.Text = L("tg_button")
	tgButton.AutoButtonColor = false
	tgButton.LayoutOrder = 2
	tgButton.Parent = credWrap
	creditsTgButton = tgButton
	registerLocale(tgButton, "tg_button")
	uiKit.addCorner(tgButton, 8)

	local note = Instance.new("TextLabel")
	note.Size = UDim2.new(1, 0, 0, 32)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.Gotham
	note.TextSize = 10
	note.TextColor3 = uiKit.COLORS.muted
	note.TextWrapped = true
	note.Text = telegram
	note.LayoutOrder = 3
	note.Parent = credWrap

	tgButton.MouseButton1Click:Connect(function()
		pcall(function() setclipboard(telegram) end)
		tgButton.Text = L("tg_copied")
		task.delay(1.5, function()
			if tgButton.Parent then
				tgButton.Text = L("tg_button")
			end
		end)
	end)
end

hubBootstrapped = false

function bootstrapMaxiHub()
	if hubBootstrapped then return end
	hubBootstrapped = true
	loadConfig()
	genv.MaxiHubVersion = SCRIPT_VERSION
	loadLocaleLib()
	loadEspLib()
	refreshPhaseText()

tabDefs = getTabDefs()

ui = MaxiHubUILib.create({
	player = player,
	playerGui = playerGui,
	genv = genv,
	title = SCRIPT_TITLE,
	version = (genv.MaxiHubVersion and tostring(genv.MaxiHubVersion)) or SCRIPT_VERSION or "",
	guiName = GUI_NAME,
	savedPosition = savedUiPos,
	defaultPosition = DEFAULT_UI_POS,
	displayOrder = 999999,
	titleHint = L("title_hint"),
	hideHintText = L("hide_hint"),
	language = UiLanguage,
	onLanguageChange = setUiLanguage,
	registerLocale = registerLocale,
	mobileStopText = L("mobile_btn_stop"),
	mobileMenuText = L("mobile_btn_menu"),
	onMobileFarmStop = function()
		setFarmState(false)
	end,
	onMobileMenuToggle = function()
		if uiRoot then
			uiRoot.Visible = not uiRoot.Visible
		end
	end,
	tabs = tabDefs,
	keyStatusText = function()
		local keyGate = genv.MaxiHubKeyGate
		if keyGate and typeof(keyGate.getKeyStatusText) == "function" then
			return keyGate.getKeyStatusText() or L("key_unpaid")
		end
		return L("key_unpaid")
	end,
	onSavePosition = scheduleSaveConfig,
	onDestroy = fullUnload,
	onCameraStart = startCameraLoop,
})

COLORS = ui.COLORS
contentPages = ui.contentPages
addCorner = ui.addCorner
switchTab = ui.switchTab
makeSectionTitle = ui.makeSectionTitle
makeToggle = ui.makeToggle
makeSlider = ui.makeSlider
makeScrollPage = ui.makeScrollPage
makeListWrap = ui.makeListWrap
makeFlowPanel = ui.makeFlowPanel
makeStatRow = ui.makeStatRow
makeFlowToggle = ui.makeFlowToggle
makeFlowSlider = ui.makeFlowSlider or function(parent, label, min, max, initial, onChange, layoutOrder, localeKey)
	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, 0, 0, 52)
	box.BackgroundTransparency = 1
	box.LayoutOrder = layoutOrder or 0
	box.Parent = parent
	makeSlider(box, 0, label, min, max, initial, onChange, localeKey)
	return box
end
screenGui = ui.screenGui
uiRoot = ui.uiRoot
uiBody = ui.uiBody
screenGuiRef = screenGui
mainFrameRef = ui.uiRoot

function formatSessionTimeUi()
	local secs = getFarmSeconds()
	local mins = math.floor(secs / 60)
	local secRem = secs % 60
	if mins > 0 then
		return string.format("%dм %02dс", mins, secRem)
	end
	return secs .. "с"
end

farmToggleSilent = false
setFarmToggle = nil
sessionStatLabels = {}

function setFarmState(enabled)
	if enabled then
		if FarmEnabled then return end
		farmToggleSilent = true
		setFarmToggle(true, true)
		farmToggleSilent = false
		startFarm()
	else
		if not FarmEnabled then return end
		local shouldReport = sessionTreesMined > 0
			or sessionStonesMined > 0
			or getFarmSeconds() > 20
		farmToggleSilent = true
		setFarmToggle(false, true)
		farmToggleSilent = false
		stopFarm()
		if shouldReport and DiscordLogOnStop then
			task.defer(function()
				pcall(function()
					logFarmSessionDiscord("Фарм остановлен", 15158332)
				end)
			end)
		end
	end
end

-- Главная (габариты: UI_LAYOUT + ui-layout.mdc)
mainPage = contentPages[1]

controlsPanel = makeFlowPanel(mainPage, L("panel_controls"), UI_LAYOUT.PANEL_W, 200, 0, 0, nil, "panel_controls")

makeFlowToggle(controlsPanel, L("toggle_autostart"), AutoStartFarm, function(state)
	AutoStartFarm = state
	scheduleSaveConfig()
end, 1, 0.22, "toggle_autostart")

setFarmToggle = makeFlowToggle(controlsPanel, L("toggle_autofarm"), false, function(state)
	if farmToggleSilent then return end
	setFarmState(state)
end, 2, 0.5, "toggle_autofarm")

makeFlowToggle(controlsPanel, L("toggle_rejoin"), RejoinAutoLoad, function(state)
	RejoinAutoLoad = state
	scheduleSaveConfig()
	if state and typeof(genv.MaxiHubRegisterRejoin) == "function" then
		pcall(genv.MaxiHubRegisterRejoin)
	end
end, 3, 0.78, "toggle_rejoin")

sessionPanel = makeFlowPanel(mainPage, L("panel_session"), UI_LAYOUT.PANEL_W, UI_LAYOUT.PANEL_H, UI_LAYOUT.PANEL_COL2_X, 0, UI_LAYOUT.SESSION_BODY_Y, "panel_session")

sessionStatLabels.phase = makeStatRow(sessionPanel, L("stat_status"), 1, "stat_status")
sessionStatLabels.trees = makeStatRow(sessionPanel, L("stat_trees"), 2, "stat_trees")
sessionStatLabels.stones = makeStatRow(sessionPanel, L("stat_stones"), 3, "stat_stones")
sessionStatLabels.loot = makeStatRow(sessionPanel, L("stat_loot"), 4, "stat_loot")
sessionStatLabels.time = makeStatRow(sessionPanel, L("stat_time"), 5, "stat_time")
sessionStatLabels.mode = makeStatRow(sessionPanel, L("stat_mode"), 6, "stat_mode")

slidersPanel = makeFlowPanel(mainPage, L("panel_tp_height"), UI_LAYOUT.FULL_W, UI_LAYOUT.SLIDER_PANEL_H, 0, UI_LAYOUT.ROW3_Y, UI_LAYOUT.SLIDER_BODY_Y, "panel_tp_height")

makeSlider(slidersPanel, 0, L("slider_trees"), 0, 12, TeleportHeight, function(v)
	TeleportHeight = v
	scheduleSaveConfig()
end, "slider_trees")

makeSlider(slidersPanel, UI_LAYOUT.SLIDER_Y_STEP, L("slider_stones"), 0, 12, StoneTeleportHeight, function(v)
	StoneTeleportHeight = v
	scheduleSaveConfig()
end, "slider_stones")

statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 0)
statusLabel.Visible = false
statusLabel.Parent = mainPage

-- Настройки
setScroll = makeScrollPage(contentPages[2])
setWrap = makeListWrap(setScroll)
setWrap:SetAttribute("MaxiHubCardToggles", true)

local setOrder = 0
local function nextSetOrder()
	setOrder += 1
	return setOrder
end

makeSectionTitle(setWrap, L("sec_targets"), nextSetOrder(), "sec_targets")
makeFlowToggle(setWrap, L("toggle_farm_trees"), FarmTreesEnabled, function(state)
	FarmTreesEnabled = state
	scheduleSaveConfig()
end, nextSetOrder(), 0.22, "toggle_farm_trees")
makeFlowToggle(setWrap, L("toggle_farm_stones"), FarmStonesEnabled, function(state)
	FarmStonesEnabled = state
	scheduleSaveConfig()
end, nextSetOrder(), 0.5, "toggle_farm_stones")
makeFlowToggle(setWrap, L("toggle_target_nearest"), TargetPickMode == "nearest", function(state)
	if state then
		TargetPickMode = "nearest"
		scheduleSaveConfig()
	end
end, nextSetOrder(), nil, "toggle_target_nearest")
makeFlowToggle(setWrap, L("toggle_target_random"), TargetPickMode == "random", function(state)
	if state then
		TargetPickMode = "random"
		scheduleSaveConfig()
	end
end, nextSetOrder(), nil, "toggle_target_random")

makeSectionTitle(setWrap, L("sec_teleport"), nextSetOrder(), "sec_teleport")
makeFlowToggle(setWrap, L("toggle_tp_smooth"), TeleportMode == "smooth", function(state)
	TeleportMode = state and "smooth" or "instant"
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_tp_smooth")
makeFlowSlider(setWrap, L("slider_tp_step_size"), 2, 40, TeleportStepSize, function(v)
	TeleportStepSize = math.floor(v)
	scheduleSaveConfig()
end, nextSetOrder(), "slider_tp_step_size")
makeFlowSlider(setWrap, L("slider_tp_step_delay"), 0.02, 0.3, TeleportStepDelay, function(v)
	TeleportStepDelay = v
	scheduleSaveConfig()
end, nextSetOrder(), "slider_tp_step_delay")
makeFlowSlider(setWrap, L("slider_attack_delay"), 0, 1.5, AttackDelay, function(v)
	AttackDelay = v
	scheduleSaveConfig()
end, nextSetOrder(), "slider_attack_delay")

makeSectionTitle(setWrap, L("sec_mining"), nextSetOrder(), "sec_mining")
makeFlowToggle(setWrap, L("toggle_orbit"), OrbitEnabled, function(state)
	OrbitEnabled = state
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_orbit")
makeFlowToggle(setWrap, L("toggle_aim"), AimAtTarget, function(state)
	AimAtTarget = state
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_aim")
makeFlowToggle(setWrap, L("toggle_fkey"), UseFKey, function(state)
	UseFKey = state
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_fkey")
makeFlowToggle(setWrap, L("toggle_click"), UseClick, function(state)
	UseClick = state
	if state then
		releaseMouseHold()
	end
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_click")
makeFlowToggle(setWrap, L("toggle_legit_mouse"), LegitMouseCapture, function(state)
	LegitMouseCapture = state
	if not state then
		releaseMouseHold()
	end
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_legit_mouse")
makeFlowSlider(setWrap, L("slider_orbit_speed"), 0.3, 3, OrbitSpeed, function(v)
	OrbitSpeed = v
	scheduleSaveConfig()
end, nextSetOrder(), "slider_orbit_speed")
makeFlowSlider(setWrap, L("slider_orbit_size"), 4, 30, OrbitDiameter, function(v)
	OrbitDiameter = v
	scheduleSaveConfig()
end, nextSetOrder(), "slider_orbit_size")

makeSectionTitle(setWrap, L("sec_performance"), nextSetOrder(), "sec_performance")
setRender3dToggle = makeFlowToggle(setWrap, L("toggle_render3d"), Render3dDisabled, function(state)
	if render3dToggleSilent then return end
	applyRender3dState(state)
end, nextSetOrder(), nil, "toggle_render3d")
makeFlowToggle(setWrap, L("toggle_render3d_farm"), AutoRender3dOnFarm, function(state)
	AutoRender3dOnFarm = state
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_render3d_farm")
makeFlowToggle(setWrap, L("toggle_black_screen"), BlackScreenOverlay, function(state)
	BlackScreenOverlay = state
	updateBlackScreenOverlay()
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_black_screen")

makeSectionTitle(setWrap, L("sec_safety"), nextSetOrder(), "sec_safety")
makeFlowToggle(setWrap, L("toggle_block_ui"), BlockUiDuringFarm, function(state)
	BlockUiDuringFarm = state
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_block_ui")
makeFlowToggle(setWrap, L("toggle_block_trades"), BlockTrades, function(state)
	BlockTrades = state
	if FarmEnabled then
		scanTrades(playerGui)
	end
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_block_trades")

makeSectionTitle(setWrap, L("sec_antitp"), nextSetOrder(), "sec_antitp")
makeFlowToggle(setWrap, L("toggle_antitp"), BlockedZonesEnabled, function(state)
	BlockedZonesEnabled = state
	updateBlockedZoneVisual()
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_antitp")

zoneBtnRow = Instance.new("Frame")
zoneBtnRow.Size = UDim2.new(1, 0, 0, 36)
zoneBtnRow.BackgroundTransparency = 1
zoneBtnRow.LayoutOrder = nextSetOrder()
zoneBtnRow.Parent = setWrap

zonePlaceBtn = Instance.new("TextButton")
zonePlaceBtn.Size = UDim2.new(0.48, 0, 1, 0)
zonePlaceBtn.BackgroundColor3 = COLORS.panel
zonePlaceBtn.BorderSizePixel = 0
zonePlaceBtn.Font = Enum.Font.GothamBold
zonePlaceBtn.TextSize = 11
zonePlaceBtn.TextColor3 = COLORS.text
zonePlaceBtn.Text = L("btn_add_zone")
zonePlaceBtn.AutoButtonColor = false
zonePlaceBtn.Parent = zoneBtnRow
addCorner(zonePlaceBtn, 8)
registerLocale(zonePlaceBtn, "btn_add_zone")

zoneClearBtn = Instance.new("TextButton")
zoneClearBtn.Size = UDim2.new(0.48, 0, 1, 0)
zoneClearBtn.Position = UDim2.new(0.52, 0, 0, 0)
zoneClearBtn.BackgroundColor3 = COLORS.card
zoneClearBtn.BorderSizePixel = 0
zoneClearBtn.Font = Enum.Font.GothamBold
zoneClearBtn.TextSize = 11
zoneClearBtn.TextColor3 = COLORS.muted
zoneClearBtn.Text = L("btn_clear_zones")
zoneClearBtn.AutoButtonColor = false
zoneClearBtn.Parent = zoneBtnRow
addCorner(zoneClearBtn, 8)
registerLocale(zoneClearBtn, "btn_clear_zones")

zonesListContainer = Instance.new("Frame")
zonesListContainer.Size = UDim2.new(1, 0, 0, 0)
zonesListContainer.AutomaticSize = Enum.AutomaticSize.Y
zonesListContainer.BackgroundTransparency = 1
zonesListContainer.LayoutOrder = nextSetOrder()
zonesListContainer.Parent = setWrap

local zonesListLayout = Instance.new("UIListLayout")
zonesListLayout.Padding = UDim.new(0, 8)
zonesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
zonesListLayout.Parent = zonesListContainer

zonePlaceBtn.MouseButton1Click:Connect(function()
	if setBlockedZoneAtPlayer() then
		zonePlaceBtn.Text = L("btn_cube_placed")
		task.delay(1.2, function()
			if zonePlaceBtn.Parent then
				zonePlaceBtn.Text = L("btn_add_zone")
			end
		end)
	else
		zonePlaceBtn.Text = L("btn_no_character")
	end
end)

zoneClearBtn.MouseButton1Click:Connect(function()
	clearBlockedZones()
end)

rebuildZonesListUI()

makeSectionTitle(setWrap, L("sec_hub"), nextSetOrder(), "sec_hub")
makeFlowToggle(setWrap, L("toggle_hub_wait"), HubWaitEnabled, function(state)
	HubWaitEnabled = state
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_hub_wait")

makeSectionTitle(setWrap, L("sec_sell"), nextSetOrder(), "sec_sell")
makeFlowToggle(setWrap, L("toggle_autosell"), AutoSellEnabled, function(state)
	AutoSellEnabled = state
	scheduleSaveConfig()
end, nextSetOrder(), nil, "toggle_autosell")
makeFlowSlider(setWrap, L("slider_sell_check"), 20, 120, SellCheckInterval, function(v)
	SellCheckInterval = math.floor(v)
	scheduleSaveConfig()
end, nextSetOrder(), "slider_sell_check")

sellBtnRow = Instance.new("Frame")
sellBtnRow.Size = UDim2.new(1, 0, 0, 36)
sellBtnRow.BackgroundTransparency = 1
sellBtnRow.LayoutOrder = nextSetOrder()
sellBtnRow.Parent = setWrap

manualSellBtn = Instance.new("TextButton")
manualSellBtn.Size = UDim2.new(1, 0, 1, 0)
manualSellBtn.BackgroundColor3 = COLORS.accent
manualSellBtn.BorderSizePixel = 0
manualSellBtn.Font = Enum.Font.GothamBold
manualSellBtn.TextSize = 11
manualSellBtn.TextColor3 = COLORS.bg
manualSellBtn.Text = L("btn_sell_now")
manualSellBtn.AutoButtonColor = false
manualSellBtn.Parent = sellBtnRow
addCorner(manualSellBtn, 8)
registerLocale(manualSellBtn, "btn_sell_now")

sellStatus = Instance.new("TextLabel")
sellStatus.Size = UDim2.new(1, 0, 0, 16)
sellStatus.BackgroundTransparency = 1
sellStatus.Font = Enum.Font.Gotham
sellStatus.TextSize = 10
sellStatus.TextColor3 = COLORS.muted
sellStatus.TextXAlignment = Enum.TextXAlignment.Left
sellStatus.Text = ""
sellStatus.LayoutOrder = nextSetOrder()
sellStatus.Parent = setWrap

manualSellBtn.MouseButton1Click:Connect(function()
	if sellInProgress then
		sellStatus.Text = L("sell_busy")
		sellStatus.TextColor3 = COLORS.red
		return
	end
	manualSellBtn.Text = L("btn_selling")
	sellStatus.Text = L("sell_tp")
	sellStatus.TextColor3 = COLORS.muted
	runManualSell(function(ok, msg)
		manualSellBtn.Text = L("btn_sell_now")
		sellStatus.Text = msg or (ok and L("sell_done") or L("sell_error"))
		sellStatus.TextColor3 = ok and COLORS.accent or COLORS.red
	end)
end)

-- Discord
discordScroll = makeScrollPage(contentPages[3])
discordWrap = makeListWrap(discordScroll)

webhookBox = Instance.new("Frame")
webhookBox.Size = UDim2.new(1, 0, 0, 74)
webhookBox.BackgroundColor3 = COLORS.card
webhookBox.BorderSizePixel = 0
webhookBox.LayoutOrder = 1
webhookBox.Parent = discordWrap
addCorner(webhookBox, 10)

webhookTitle = Instance.new("TextLabel")
webhookTitle.Size = UDim2.new(1, -20, 0, 18)
webhookTitle.Position = UDim2.new(0, 10, 0, 8)
webhookTitle.BackgroundTransparency = 1
webhookTitle.Font = Enum.Font.GothamBold
webhookTitle.TextSize = 11
webhookTitle.TextColor3 = COLORS.text
webhookTitle.TextXAlignment = Enum.TextXAlignment.Left
webhookTitle.Text = L("webhook_title")
webhookTitle.Parent = webhookBox
registerLocale(webhookTitle, "webhook_title")

webhookInput = Instance.new("TextBox")
webhookInput.Size = UDim2.new(1, -20, 0, 30)
webhookInput.Position = UDim2.new(0, 10, 0, 32)
webhookInput.BackgroundColor3 = COLORS.panel
webhookInput.BorderSizePixel = 0
webhookInput.ClearTextOnFocus = false
webhookInput.Font = Enum.Font.Gotham
webhookInput.TextSize = 10
webhookInput.TextColor3 = COLORS.text
webhookInput.PlaceholderText = "https://discord.com/api/webhooks/..."
webhookInput.PlaceholderColor3 = COLORS.muted
webhookInput.Text = UserDiscordWebhook
webhookInput.TextXAlignment = Enum.TextXAlignment.Left
webhookInput.Parent = webhookBox
addCorner(webhookInput, 8)

discordStatus = Instance.new("TextLabel")
discordStatus.Size = UDim2.new(1, 0, 0, 16)
discordStatus.BackgroundTransparency = 1
discordStatus.Font = Enum.Font.Gotham
discordStatus.TextSize = 10
discordStatus.TextColor3 = COLORS.muted
discordStatus.TextXAlignment = Enum.TextXAlignment.Left
discordStatus.Text = canUseConfigFile() and L("webhook_saved_ok") or L("webhook_saved_bad")
discordStatus.LayoutOrder = 2
discordStatus.Parent = discordWrap

discordOpts = Instance.new("Frame")
discordOpts.Size = UDim2.new(1, 0, 0, 210)
discordOpts.BackgroundColor3 = COLORS.card
discordOpts.BorderSizePixel = 0
discordOpts.LayoutOrder = 3
discordOpts.Parent = discordWrap
addCorner(discordOpts, 10)

discordOptsLayout = Instance.new("UIListLayout")
discordOptsLayout.Padding = UDim.new(0, 4)
discordOptsLayout.SortOrder = Enum.SortOrder.LayoutOrder
discordOptsLayout.Parent = discordOpts

discordPad = Instance.new("UIPadding")
discordPad.PaddingTop = UDim.new(0, 8)
discordPad.PaddingBottom = UDim.new(0, 8)
discordPad.PaddingLeft = UDim.new(0, 4)
discordPad.PaddingRight = UDim.new(0, 4)
discordPad.Parent = discordOpts

makeFlowToggle(discordOpts, L("toggle_discord_reports"), DiscordReportsEnabled, function(state)
	DiscordReportsEnabled = state
	FARM_REPORT_INTERVAL = DiscordReportMinutes * 60
	saveDiscordConfig()
end, 1, 0.22, "toggle_discord_reports")

makeFlowToggle(discordOpts, L("toggle_discord_stop"), DiscordLogOnStop, function(state)
	DiscordLogOnStop = state
	saveDiscordConfig()
end, 2, 0.5, "toggle_discord_stop")

makeFlowToggle(discordOpts, L("toggle_discord_sell"), DiscordLogOnSell, function(state)
	DiscordLogOnSell = state
	saveDiscordConfig()
end, 3, 0.78, "toggle_discord_sell")

intervalBox = Instance.new("Frame")
intervalBox.Size = UDim2.new(1, -8, 0, 52)
intervalBox.BackgroundTransparency = 1
intervalBox.LayoutOrder = 4
intervalBox.Parent = discordOpts

makeSlider(intervalBox, 0, L("slider_discord_interval"), 1, 120, DiscordReportMinutes, function(v)
	DiscordReportMinutes = math.floor(v)
	FARM_REPORT_INTERVAL = DiscordReportMinutes * 60
	saveDiscordConfig()
end, "slider_discord_interval")

discordBtns = Instance.new("Frame")
discordBtns.Size = UDim2.new(1, 0, 0, 36)
discordBtns.BackgroundTransparency = 1
discordBtns.LayoutOrder = 5
discordBtns.Parent = discordWrap

testBtn = Instance.new("TextButton")
testBtn.Size = UDim2.new(0.48, 0, 1, 0)
testBtn.BackgroundColor3 = COLORS.accent
testBtn.BorderSizePixel = 0
testBtn.Font = Enum.Font.GothamBold
testBtn.TextSize = 11
testBtn.TextColor3 = COLORS.bg
testBtn.Text = L("btn_test_webhook")
testBtn.AutoButtonColor = false
testBtn.Parent = discordBtns
addCorner(testBtn, 8)
registerLocale(testBtn, "btn_test_webhook")

saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(0.48, 0, 1, 0)
saveBtn.Position = UDim2.new(0.52, 0, 0, 0)
saveBtn.BackgroundColor3 = COLORS.panel
saveBtn.BorderSizePixel = 0
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 11
saveBtn.TextColor3 = COLORS.text
saveBtn.Text = L("btn_save")
saveBtn.AutoButtonColor = false
saveBtn.Parent = discordBtns
addCorner(saveBtn, 8)
registerLocale(saveBtn, "btn_save")

function applyWebhookFromInput()
	UserDiscordWebhook = webhookInput.Text:gsub("^%s+", ""):gsub("%s+$", "")
	saveDiscordConfig()
end

webhookInput.FocusLost:Connect(function()
	applyWebhookFromInput()
end)

saveBtn.MouseButton1Click:Connect(function()
	applyWebhookFromInput()
	discordStatus.Text = L("discord_saved")
	discordStatus.TextColor3 = COLORS.accent
	task.delay(2, function()
		if discordStatus.Parent then
			updateDiscordStatusText()
			discordStatus.TextColor3 = COLORS.muted
		end
	end)
end)

testBtn.MouseButton1Click:Connect(function()
	applyWebhookFromInput()
	local ok, msg = sendDiscordEmbed(
		getFarmDiscordWebhook(),
		"Тест MAXI HUB",
		3447003,
		{
			{ name = "Проверка", value = "Если видишь это — webhook работает", inline = false },
			{ name = "Интервал", value = tostring(DiscordReportMinutes) .. " мин", inline = true },
		}
	)
	discordStatus.Text = msg
	discordStatus.TextColor3 = ok and COLORS.accent or COLORS.red
end)

-- ESP (локальная вкладка — пути добавим позже)
if MaxiHubESPLib and typeof(MaxiHubESPLib.buildTab) == "function" then
	MaxiHubESPLib.buildTab(contentPages[4], {
		COLORS = COLORS,
		makeScrollPage = makeScrollPage,
		makeListWrap = makeListWrap,
		addCorner = addCorner,
		makeSectionTitle = makeSectionTitle,
		makeFlowToggle = makeFlowToggle,
		makeFlowSlider = makeFlowSlider,
		makeSlider = makeSlider,
		L = L,
		registerLocale = registerLocale,
		getConfig = function()
			return {
				EspEnabled = EspEnabled,
				EspTrees = EspTrees,
				EspStones = EspStones,
				EspPlayers = EspPlayers,
				EspResources = EspResources,
				EspDragons = EspDragons,
				EspTracers = EspTracers,
				EspNames = EspNames,
				EspTextSize = EspTextSize,
				EspColors = EspColors,
			}
		end,
		onFieldChange = function(key, value)
			if key == "EspEnabled" then EspEnabled = value
			elseif key == "EspTrees" then EspTrees = value
			elseif key == "EspStones" then EspStones = value
			elseif key == "EspPlayers" then EspPlayers = value
			elseif key == "EspResources" then EspResources = value
			elseif key == "EspDragons" then EspDragons = value
			elseif key == "EspTracers" then EspTracers = value
			elseif key == "EspNames" then EspNames = value
			elseif key == "EspTextSize" then EspTextSize = value
			elseif key == "EspColors" then EspColors = value
			end
			refreshEsp()
			scheduleSaveConfig()
		end,
	})
end

-- Кредиты (обязательная вкладка — не удалять)
buildMaxiHubChangelogTab(contentPages[5], {
	COLORS = COLORS,
	makeScrollPage = makeScrollPage,
	makeListWrap = makeListWrap,
	addCorner = addCorner,
})

buildMaxiHubCreditsTab(contentPages[6], {
	COLORS = COLORS,
	makeScrollPage = makeScrollPage,
	makeListWrap = makeListWrap,
	addCorner = addCorner,
})

ui.onInputBegan(function(input)
	if input.KeyCode ~= HOTKEY then return end
	local now = tick()
	if now - (genv.MaxiHubLastHotkeyAt or 0) < 0.45 then return end
	genv.MaxiHubLastHotkeyAt = now
	setFarmState(not FarmEnabled)
end)

ui.finalize()
applyMaxiHubLocale()
refreshEsp()

task.spawn(function()
	while screenGui.Parent do
		if activeNode and (farmPhase == "wait" or farmPhase == "collect") then
			cachedDropCount = #findDropsNear(activeNode)
		else
			cachedDropCount = 0
		end

		local phaseText = PHASE_TEXT[farmPhase] or farmPhase
		local autoFText = autoFActive and " · автоF" or ""
		local modeText = getFarmModeText()
		if sessionStatLabels.phase then
			sessionStatLabels.phase.Text = phaseText .. autoFText
		end
		if sessionStatLabels.trees then
			sessionStatLabels.trees.Text = tostring(sessionTreesMined)
		end
		if sessionStatLabels.stones then
			sessionStatLabels.stones.Text = tostring(sessionStonesMined)
		end
		if sessionStatLabels.loot then
			sessionStatLabels.loot.Text = tostring(cachedDropCount)
		end
		if sessionStatLabels.time then
			sessionStatLabels.time.Text = formatSessionTimeUi()
		end
		if sessionStatLabels.mode then
			sessionStatLabels.mode.Text = modeText
		end
		if statusLabel and statusLabel.Visible then
			local invText = ""
			if AutoSellEnabled then
				local invAmount, invName = getSellTriggerAmount()
				invText = string.format(" | %s:%d", invName, invAmount)
			end
			statusLabel.Text = string.format(
				"%s | д:%d к:%d | %s | лут:%d%s",
				modeText,
				cachedTreeCount,
				cachedStoneCount,
				phaseText,
				cachedDropCount,
				invText
			)
		end
		task.wait(0.4)
	end
end)

updateBlockedZoneVisual()
applyRender3dState(Render3dDisabled, { silent = true, skipSave = true })

if hasPendingSellState() then
	resumePendingSellAfterBootstrap()
elseif AutoStartFarm then
	task.defer(function()
		farmToggleSilent = true
		setFarmToggle(true, true)
		farmToggleSilent = false
		setFarmState(true)
	end)
end

if RejoinAutoLoad and typeof(genv.MaxiHubRegisterRejoin) == "function" then
	pcall(genv.MaxiHubRegisterRejoin)
end

end -- bootstrapMaxiHub

function launchMaxiHub()
	if not ensurePlayer() then
		warn("[MAXI HUB] Не удалось получить PlayerGui")
		return
	end

	print("[MAXI HUB] запуск UI...")
	local ok, err = pcall(bootstrapMaxiHub)
	if not ok then
		hubBootstrapped = false
		warn("[MAXI HUB] Ошибка запуска:", err)
	end
end

genv.MaxiHubRelaunch = function()
	hubBootstrapped = false
	softCleanup()
	return launchMaxiHub()
end

if not player or not playerGui then
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	player = Players.LocalPlayer or Players.PlayerAdded:Wait()
	playerGui = player:WaitForChild("PlayerGui")
end

print("[MAXI HUB] модуль загружен")
task.defer(function()
	local ok, err = pcall(launchMaxiHub)
	if not ok then
		warn("[MAXI HUB] Критическая ошибка:", err)
	end
end)

