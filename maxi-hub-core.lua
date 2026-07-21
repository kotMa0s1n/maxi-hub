-- MAXI HUB core (auto-loaded by maxi-hub.lua)
SCRIPT_TITLE = "🔰MAXI HUB"
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
SELL_STATE_FILE = "maxi-hub-sell-state.json"
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
OrbitEnabled = false
AimAtTarget = true
BlockUiDuringFarm = true
BlockTrades = true
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

function canUseConfigFile()
	return typeof(writefile) == "function"
		and typeof(readfile) == "function"
		and typeof(isfile) == "function"
end

saveConfigScheduled = false
mainFrameRef = nil

function saveConfig()
	if not canUseConfigFile() then return end
	local payload = {
		TeleportHeight = TeleportHeight,
		StoneTeleportHeight = StoneTeleportHeight,
		UseFKey = UseFKey,
		UseClick = UseClick,
		OrbitEnabled = OrbitEnabled,
		AimAtTarget = AimAtTarget,
		OrbitSpeed = OrbitSpeed,
		OrbitDiameter = OrbitDiameter,
		BlockUiDuringFarm = BlockUiDuringFarm,
		BlockTrades = BlockTrades,
		HubWaitEnabled = HubWaitEnabled,
		AutoStartFarm = AutoStartFarm,
		RejoinAutoLoad = RejoinAutoLoad,
		BlockedZonesEnabled = BlockedZonesEnabled,
		BlockedZoneSize = BlockedZoneSize,
		BlockedZoneCenter = BlockedZoneCenter and {
			BlockedZoneCenter.X,
			BlockedZoneCenter.Y,
			BlockedZoneCenter.Z,
		} or nil,
		AutoSellEnabled = AutoSellEnabled,
		SellCheckInterval = SellCheckInterval,
		UserDiscordWebhook = UserDiscordWebhook,
		DiscordReportsEnabled = DiscordReportsEnabled,
		DiscordReportMinutes = DiscordReportMinutes,
		DiscordLogOnSell = DiscordLogOnSell,
		DiscordLogOnStop = DiscordLogOnStop,
	}
	if mainFrameRef then
		local p = mainFrameRef.Position
		payload.UiXScale = p.X.Scale
		payload.UiXOffset = p.X.Offset
		payload.UiYScale = p.Y.Scale
		payload.UiYOffset = p.Y.Offset
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if ok then
		pcall(function() writefile(CONFIG_FILE, json) end)
	end
end

function scheduleSaveConfig()
	if saveConfigScheduled then return end
	saveConfigScheduled = true
	task.delay(0.25, function()
		saveConfigScheduled = false
		saveConfig()
	end)
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
	if data.OrbitEnabled ~= nil then OrbitEnabled = data.OrbitEnabled end
	if data.AimAtTarget ~= nil then AimAtTarget = data.AimAtTarget end
	if typeof(data.OrbitSpeed) == "number" then OrbitSpeed = data.OrbitSpeed end
	if typeof(data.OrbitDiameter) == "number" then OrbitDiameter = data.OrbitDiameter end
	if data.BlockUiDuringFarm ~= nil then BlockUiDuringFarm = data.BlockUiDuringFarm end
	if data.BlockTrades ~= nil then BlockTrades = data.BlockTrades end
	if data.HubWaitEnabled ~= nil then HubWaitEnabled = data.HubWaitEnabled end
	if data.AutoStartFarm ~= nil then AutoStartFarm = data.AutoStartFarm end
	if data.RejoinAutoLoad ~= nil then RejoinAutoLoad = data.RejoinAutoLoad end
	if data.BlockedZonesEnabled ~= nil then BlockedZonesEnabled = data.BlockedZonesEnabled end
	if typeof(data.BlockedZoneSize) == "number" then
		BlockedZoneSize = math.clamp(math.floor(data.BlockedZoneSize), 20, 120)
	end
	if typeof(data.BlockedZoneCenter) == "table" and #data.BlockedZoneCenter >= 3 then
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
	if typeof(data.UiYScale) == "number" then
		savedUiPos = UDim2.new(
			data.UiXScale or 0,
			data.UiXOffset or 16,
			data.UiYScale,
			data.UiYOffset or 0
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
	if cachedTreeCount > 0 then
		return "деревья"
	end
	if cachedStoneCount > 0 then
		return "камни"
	end
	return "поиск"
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
}

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

function isPosInBlockedZone(pos)
	if not BlockedZonesEnabled or not pos or not BlockedZoneCenter then return false end
	local mn, mx = getBlockedZoneMinMax()
	if not mn or not mx then return false end
	return pos.X >= mn.X and pos.X <= mx.X
		and pos.Y >= mn.Y and pos.Y <= mx.Y
		and pos.Z >= mn.Z and pos.Z <= mx.Z
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
	if not BlockedZonesEnabled or not BlockedZoneCenter then
		destroyBlockedZoneVisual()
		return
	end

	local folder = ensureBlockedZoneFolder()
	if not blockedZoneVisualPart or not blockedZoneVisualPart.Parent then
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
		blockedZoneVisualPart.Parent = folder
	end

	blockedZoneVisualPart.Size = Vector3.new(BlockedZoneSize, BlockedZoneSize, BlockedZoneSize)
	blockedZoneVisualPart.CFrame = CFrame.new(BlockedZoneCenter)
	blockedZoneVisualPart.Transparency = 0.72
end

function setBlockedZoneAtPlayer()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	BlockedZoneCenter = hrp.Position
	updateBlockedZoneVisual()
	scheduleSaveConfig()
	return true
end

function teleportHrpTo(pos)
	if isPosInBlockedZone(pos) then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not pos then return end
	hrp.CFrame = CFrame.new(pos)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
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

function teleportToHub()
	if isNearHub() then return end

	local spawnPart = getTeleportSpawnPart()
	if spawnPart then
		hubPosition = spawnPart.Position + Vector3.new(0, 3, 0)
		teleportHrpTo(hubPosition)
		return
	end
	teleportHrpTo(getHubPosition())
end

function hubRestWait(runId, doTeleport)
	if doTeleport == nil then doTeleport = true end

	farmPhase = "hub"
	releaseMouseHold()
	releaseFKey()
	stopCharacterMotion()
	currentTargetPart = nil
	if doTeleport then
		teleportToHub()
	end
	if not HubWaitEnabled then
		return true
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

function holdMouseAt(x, y)
	x, y = x or 0, y or 0
	if mouseHeld and math.abs(holdMouseX - x) < 2 and math.abs(holdMouseY - y) < 2 then
		return
	end
	releaseMouseHold()
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
		end)
	else
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
	releaseMouseHold()
	if VirtualInputManager and x and y then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
			task.wait(0.05)
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
		end)
	else
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
	local aimPos = getPartPosition(part)
	if AimAtTarget and currentTargetPart and currentTargetPart.Parent then
		aimPos = getPartPosition(currentTargetPart) or aimPos
	end
	local x, y = getScreenPos(aimPos)
	if not x then
		x, y = getFallbackScreenPos()
	end
	return x, y
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

function updateAutoF(node)
	if UseFKey then
		autoFActive = false
		return
	end

	local health = getNodeHealth(node)
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

		local treeFolder = nodesFolder:FindFirstChild("Food")
		if treeFolder then
			for _, node in ipairs(treeFolder:GetChildren()) do
				if isNodeAlive(node) and not isNodeInBlockedZone(node) then
					table.insert(trees, { node = node, kind = "tree" })
				end
			end
		end

		local stoneFolder = nodesFolder:FindFirstChild("Resources")
		if stoneFolder then
			for _, node in ipairs(stoneFolder:GetChildren()) do
				if isNodeAlive(node) and not isNodeInBlockedZone(node) then
					table.insert(stones, { node = node, kind = "stone" })
				end
			end
		end
	end)

	local targets = #trees > 0 and trees or stones
	if #targets == 0 then
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
		local center = getNodeCenter(target.node)
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
			local center = getNodeCenter(target.node)
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
	pressF()
	local x, y = getAimScreenPos(part)
	if not x or not y then return end
	if UseClick then
		clickAt(x, y)
	else
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

	if AimAtTarget and activeTargetKind ~= "stone" then
		hrp.CFrame = CFrame.new(pos, partPos)
	else
		hrp.CFrame = CFrame.new(pos)
	end

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	if not UseClick and currentTargetPart then
		local x, y = getAimScreenPos(currentTargetPart)
		holdMouseAt(x, y)
	end
end

function isOurGui(gui)
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
	scanTrades(playerGui)

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
		-- В центр — один раз; дальше только ждём, без повторного ТП
		if not hubRestWait(runId, not hubPlaced) then break end
		hubPlaced = true
	end

	farmPhase = "idle"
	return {}
end

function killFarmLoops()
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
	pcall(stopSafeMode)
end

function stopFarm()
	killFarmLoops()
end

function softCleanup()
	stopFarm()
	stopSafeMode()
	stopCameraLoop()
	destroyBlockedZoneVisual()
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

genv.MaxiHubStop = softCleanup

if pendingPrevStop and pendingPrevStop ~= softCleanup then
	pcall(pendingPrevStop)
end
pendingPrevStop = nil

function startFarm()
	killFarmLoops()
	FarmEnabled = true
	farmTimeStarted = tick()
	lastFarmReportAt = tick()
	local myRunId = farmRunId
	startSafeMode()

	teleportConnection = RunService.Heartbeat:Connect(function()
		if not shouldFarmContinue(myRunId) then return end
		if farmPhase == "collect" or farmPhase == "wait" or farmPhase == "sell" or farmPhase == "hub" or farmPhase == "search" then return end
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
				if not hubRestWait(myRunId) then return end
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
			farmPhase = "mine"
			orbitAngle = 0
			resetAutoF()

			local hitboxes = getHitboxes(activeNode)
			if #hitboxes == 0 then
				pushFarmWarning("no_hitbox", "У цели нет Hitbox")
				task.wait(0.5)
				return
			end
			clearFarmWarning("no_hitbox")

			currentTargetPart = hitboxes[1]
			local mineDeadline = tick() + 60

			while shouldFarmContinue(myRunId)
				and tick() < mineDeadline
				and isNodeAlive(activeNode) do
				updateAutoF(activeNode)
				if autoFActive then
					pushFarmWarning("stuck_mining", "Долго не ломается — жму F")
				else
					clearFarmWarning("stuck_mining")
				end
				attackPart(currentTargetPart)
				task.wait(0.05)
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
	if not genvUi._MaxiHubUILibrary then
		local source
		local base = genvUi.MaxiHubOfficialRaw or genvUi.MaxiHubRemoteBase
		local repoOnly = genvUi.MaxiHubRepoOnly == true
		if base and typeof(game.HttpGet) == "function" then
			local ok, remote = pcall(function()
				return game:HttpGet(base .. "maxi-hub-ui.lua")
			end)
			if ok and type(remote) == "string" and remote ~= "" then
				if not remote:find("<!DOCTYPE", 1, true) and not remote:find("<html", 1, true) then
					source = remote
				elseif repoOnly then
					error("[MAXI HUB] UI только с официального репо")
				end
			end
		end
		if not source and not repoOnly and typeof(readfile) == "function" and typeof(isfile) == "function" then
			for _, p in ipairs({ "maxi-hub/maxi-hub-ui.lua", "maxi-hub-ui.lua" }) do
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

-- Вкладка «Кредиты» — обязательная, копировать в лаунчеры других игр
function buildMaxiHubCreditsTab(page, uiKit, opts)
	opts = opts or {}
	local telegram = opts.telegram or TELEGRAM_LINK
	local scriptLine = opts.scriptLine or "Авто-фарм скрипт"

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
	about.Text = SCRIPT_TITLE .. "\n" .. scriptLine .. "\nСпасибо что пользуешься!"
	about.LayoutOrder = 1
	about.Parent = credWrap
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
	tgButton.Text = "Telegram канал"
	tgButton.AutoButtonColor = false
	tgButton.LayoutOrder = 2
	tgButton.Parent = credWrap
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
		tgButton.Text = "Скопировано!"
		task.delay(1.5, function()
			if tgButton.Parent then
				tgButton.Text = "Telegram канал"
			end
		end)
	end)
end

hubBootstrapped = false

function bootstrapMaxiHub()
	if hubBootstrapped then return end
	hubBootstrapped = true
	loadConfig()

-- ===== СБОРКА ВКЛАДОК (твой контент) =====
-- ▼ Свой контент вкладок — секция «Главная» и ниже в этом файле

tabDefs = {
	{ name = "Главная", title = "Главная", subtitle = "Управление фармом и статистика сессии" },
	{ name = "Настройки", title = "Настройки", subtitle = "Добыча, безопасность и авто-продажа" },
	{ name = "Discord", title = "Discord", subtitle = "Webhook, тайминги и тест отчётов" },
	{ name = "Кредиты", title = "Кредиты", subtitle = "О скрипте и контакты" },
}

ui = MaxiHubUILib.create({
	player = player,
	playerGui = playerGui,
	genv = genv,
	title = SCRIPT_TITLE,
	guiName = GUI_NAME,
	savedPosition = savedUiPos,
	defaultPosition = DEFAULT_UI_POS,
	titleHint = "End — фарм · RightCtrl — скрыть",
	tabs = tabDefs,
	keyStatusText = function()
		local keyGate = genv.MaxiHubKeyGate
		if keyGate and typeof(keyGate.getKeyStatusText) == "function" then
			return keyGate.getKeyStatusText()
		end
		return nil
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
L = UI_LAYOUT

controlsPanel = makeFlowPanel(mainPage, "Управление", L.PANEL_W, 200, 0, 0)

makeFlowToggle(controlsPanel, "Старт при загрузке", AutoStartFarm, function(state)
	AutoStartFarm = state
	scheduleSaveConfig()
end, 1, 0.22)

setFarmToggle = makeFlowToggle(controlsPanel, "Авто фарм", false, function(state)
	if farmToggleSilent then return end
	setFarmState(state)
end, 2, 0.5)

makeFlowToggle(controlsPanel, "Авто при смене сервера", RejoinAutoLoad, function(state)
	RejoinAutoLoad = state
	scheduleSaveConfig()
	if state and typeof(genv.MaxiHubRegisterRejoin) == "function" then
		pcall(genv.MaxiHubRegisterRejoin)
	end
end, 3, 0.78)

sessionPanel = makeFlowPanel(mainPage, "Сессия", L.PANEL_W, L.PANEL_H, L.PANEL_COL2_X, 0, L.SESSION_BODY_Y)

sessionStatLabels.phase = makeStatRow(sessionPanel, "Статус", 1)
sessionStatLabels.trees = makeStatRow(sessionPanel, "Срубил деревьев", 2)
sessionStatLabels.stones = makeStatRow(sessionPanel, "Срубил камней", 3)
sessionStatLabels.loot = makeStatRow(sessionPanel, "Лут на земле", 4)
sessionStatLabels.time = makeStatRow(sessionPanel, "Время фарма", 5)
sessionStatLabels.mode = makeStatRow(sessionPanel, "Режим", 6)

slidersPanel = makeFlowPanel(mainPage, "Высота ТП", L.FULL_W, L.SLIDER_PANEL_H, 0, L.ROW3_Y, L.SLIDER_BODY_Y)

makeSlider(slidersPanel, 0, "Деревья", 0, 12, TeleportHeight, function(v)
	TeleportHeight = v
	scheduleSaveConfig()
end)

makeSlider(slidersPanel, L.SLIDER_Y_STEP, "Камни", 0, 12, StoneTeleportHeight, function(v)
	StoneTeleportHeight = v
	scheduleSaveConfig()
end)

statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 0)
statusLabel.Visible = false
statusLabel.Parent = mainPage

-- Настройки
setScroll = makeScrollPage(contentPages[2])
setWrap = makeListWrap(setScroll)

makeSectionTitle(setWrap, "добыча", 1)

mineBox = Instance.new("Frame")
mineBox.Size = UDim2.new(1, 0, 0, L.MINE_BOX_H)
mineBox.BackgroundTransparency = 1
mineBox.LayoutOrder = 2
mineBox.Parent = setWrap

makeToggle(mineBox, 0, "Кружение вокруг цели", OrbitEnabled, function(state)
	OrbitEnabled = state
	scheduleSaveConfig()
end)

makeToggle(mineBox, L.TOGGLE_Y_STEP, "Атака в цель", AimAtTarget, function(state)
	AimAtTarget = state
	scheduleSaveConfig()
end)

makeToggle(mineBox, L.TOGGLE_Y_STEP * 2, "Клавиша F", UseFKey, function(state)
	UseFKey = state
	scheduleSaveConfig()
end)

makeToggle(mineBox, L.TOGGLE_Y_STEP * 3, "Клик ЛКМ", UseClick, function(state)
	UseClick = state
	if state then
		releaseMouseHold()
	end
	scheduleSaveConfig()
end)

slidersBox = Instance.new("Frame")
slidersBox.Size = UDim2.new(1, 0, 0, L.SLIDERS_BOX_H)
slidersBox.BackgroundTransparency = 1
slidersBox.LayoutOrder = 3
slidersBox.Parent = setWrap

makeSlider(slidersBox, 0, "Скорость круга", 0.3, 3, OrbitSpeed, function(v)
	OrbitSpeed = v
	scheduleSaveConfig()
end)

makeSlider(slidersBox, L.SLIDER_Y_STEP, "Диаметр круга", 4, 30, OrbitDiameter, function(v)
	OrbitDiameter = v
	scheduleSaveConfig()
end)

makeSectionTitle(setWrap, "безопасность", 4)

safeBox = Instance.new("Frame")
safeBox.Size = UDim2.new(1, 0, 0, L.SAFE_BOX_H)
safeBox.BackgroundTransparency = 1
safeBox.LayoutOrder = 5
safeBox.Parent = setWrap

makeToggle(safeBox, 0, "Блок UI при фарме", BlockUiDuringFarm, function(state)
	BlockUiDuringFarm = state
	scheduleSaveConfig()
end)

makeToggle(safeBox, L.TOGGLE_Y_STEP, "Блок трейдов", BlockTrades, function(state)
	BlockTrades = state
	if FarmEnabled then
		scanTrades(playerGui)
	end
	scheduleSaveConfig()
end)

blockHint = Instance.new("TextLabel")
blockHint.Size = UDim2.new(1, 0, 0, 18)
blockHint.BackgroundTransparency = 1
blockHint.Font = Enum.Font.Gotham
blockHint.TextSize = 10
blockHint.TextColor3 = COLORS.muted
blockHint.TextXAlignment = Enum.TextXAlignment.Left
blockHint.Text = "Скрывает игровые меню при фарме"
blockHint.LayoutOrder = 6
blockHint.Parent = setWrap

makeSectionTitle(setWrap, "анти-тп", 7)

zoneBox = Instance.new("Frame")
zoneBox.Size = UDim2.new(1, 0, 0, 44)
zoneBox.BackgroundTransparency = 1
zoneBox.LayoutOrder = 8
zoneBox.Parent = setWrap

makeToggle(zoneBox, 0, "Анти-ТП зона", BlockedZonesEnabled, function(state)
	BlockedZonesEnabled = state
	updateBlockedZoneVisual()
	scheduleSaveConfig()
end)

zoneSliderBox = Instance.new("Frame")
zoneSliderBox.Size = UDim2.new(1, 0, 0, L.SLIDER_Y_STEP)
zoneSliderBox.BackgroundTransparency = 1
zoneSliderBox.LayoutOrder = 9
zoneSliderBox.Parent = setWrap

makeSlider(zoneSliderBox, 0, "Размер куба", 20, 120, BlockedZoneSize, function(v)
	BlockedZoneSize = math.floor(v)
	updateBlockedZoneVisual()
	scheduleSaveConfig()
end)

zoneBtnRow = Instance.new("Frame")
zoneBtnRow.Size = UDim2.new(1, 0, 0, 36)
zoneBtnRow.BackgroundTransparency = 1
zoneBtnRow.LayoutOrder = 10
zoneBtnRow.Parent = setWrap

zonePlaceBtn = Instance.new("TextButton")
zonePlaceBtn.Size = UDim2.new(1, 0, 1, 0)
zonePlaceBtn.BackgroundColor3 = COLORS.panel
zonePlaceBtn.BorderSizePixel = 0
zonePlaceBtn.Font = Enum.Font.GothamBold
zonePlaceBtn.TextSize = 11
zonePlaceBtn.TextColor3 = COLORS.text
zonePlaceBtn.Text = "Поставить куб здесь"
zonePlaceBtn.AutoButtonColor = false
zonePlaceBtn.Parent = zoneBtnRow
addCorner(zonePlaceBtn, 8)

zoneHint = Instance.new("TextLabel")
zoneHint.Size = UDim2.new(1, 0, 0, 32)
zoneHint.BackgroundTransparency = 1
zoneHint.Font = Enum.Font.Gotham
zoneHint.TextSize = 10
zoneHint.TextColor3 = COLORS.muted
zoneHint.TextWrapped = true
zoneHint.TextXAlignment = Enum.TextXAlignment.Left
zoneHint.Text = "Красный куб — запрет на ТП и фарм (деревья и камни)"
zoneHint.LayoutOrder = 11
zoneHint.Parent = setWrap

zonePlaceBtn.MouseButton1Click:Connect(function()
	if setBlockedZoneAtPlayer() then
		zonePlaceBtn.Text = "Куб установлен"
		task.delay(1.2, function()
			if zonePlaceBtn.Parent then
				zonePlaceBtn.Text = "Поставить куб здесь"
			end
		end)
	else
		zonePlaceBtn.Text = "Нет персонажа"
	end
end)

makeSectionTitle(setWrap, "центр", 12)

hubBox = Instance.new("Frame")
hubBox.Size = UDim2.new(1, 0, 0, 44)
hubBox.BackgroundTransparency = 1
hubBox.LayoutOrder = 13
hubBox.Parent = setWrap

makeToggle(hubBox, 0, "Пауза у спавна", HubWaitEnabled, function(state)
	HubWaitEnabled = state
	scheduleSaveConfig()
end)

hubHint = Instance.new("TextLabel")
hubHint.Size = UDim2.new(1, 0, 0, 28)
hubHint.BackgroundTransparency = 1
hubHint.Font = Enum.Font.Gotham
hubHint.TextSize = 10
hubHint.TextColor3 = COLORS.muted
hubHint.TextWrapped = true
hubHint.TextXAlignment = Enum.TextXAlignment.Left
hubHint.Text = "Выкл — ТП в центр без ожидания 3–8 сек"
hubHint.LayoutOrder = 14
hubHint.Parent = setWrap

makeSectionTitle(setWrap, "продажа", 15)

sellBox = Instance.new("Frame")
sellBox.Size = UDim2.new(1, 0, 0, 96)
sellBox.BackgroundTransparency = 1
sellBox.LayoutOrder = 16
sellBox.Parent = setWrap

makeToggle(sellBox, 0, "Авто продажа", AutoSellEnabled, function(state)
	AutoSellEnabled = state
	scheduleSaveConfig()
end)

makeSlider(sellBox, L.TOGGLE_Y_STEP, "Проверка (сек)", 20, 120, SellCheckInterval, function(v)
	SellCheckInterval = math.floor(v)
	scheduleSaveConfig()
end)

sellBtnRow = Instance.new("Frame")
sellBtnRow.Size = UDim2.new(1, 0, 0, 36)
sellBtnRow.BackgroundTransparency = 1
sellBtnRow.LayoutOrder = 17
sellBtnRow.Parent = setWrap

manualSellBtn = Instance.new("TextButton")
manualSellBtn.Size = UDim2.new(1, 0, 1, 0)
manualSellBtn.BackgroundColor3 = COLORS.accent
manualSellBtn.BorderSizePixel = 0
manualSellBtn.Font = Enum.Font.GothamBold
manualSellBtn.TextSize = 11
manualSellBtn.TextColor3 = COLORS.bg
manualSellBtn.Text = "Продать сейчас"
manualSellBtn.AutoButtonColor = false
manualSellBtn.Parent = sellBtnRow
addCorner(manualSellBtn, 8)

sellStatus = Instance.new("TextLabel")
sellStatus.Size = UDim2.new(1, 0, 0, 16)
sellStatus.BackgroundTransparency = 1
sellStatus.Font = Enum.Font.Gotham
sellStatus.TextSize = 10
sellStatus.TextColor3 = COLORS.muted
sellStatus.TextXAlignment = Enum.TextXAlignment.Left
sellStatus.Text = ""
sellStatus.LayoutOrder = 18
sellStatus.Parent = setWrap

sellHint = Instance.new("TextLabel")
sellHint.Size = UDim2.new(1, 0, 0, 36)
sellHint.BackgroundTransparency = 1
sellHint.Font = Enum.Font.Gotham
sellHint.TextSize = 10
sellHint.TextColor3 = COLORS.muted
sellHint.TextWrapped = true
sellHint.TextXAlignment = Enum.TextXAlignment.Left
sellHint.Text = "Авто: любой предмет > 8999. При ТП в другой плейс прогресс в maxi-hub-sell-state.json"
sellHint.LayoutOrder = 19
sellHint.Parent = setWrap

manualSellBtn.MouseButton1Click:Connect(function()
	if sellInProgress then
		sellStatus.Text = "Уже идёт продажа"
		sellStatus.TextColor3 = COLORS.red
		return
	end
	manualSellBtn.Text = "Продажа..."
	sellStatus.Text = "ТП на продажу..."
	sellStatus.TextColor3 = COLORS.muted
	runManualSell(function(ok, msg)
		manualSellBtn.Text = "Продать сейчас"
		sellStatus.Text = msg or (ok and "Готово" or "Ошибка")
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
webhookTitle.Text = "Webhook URL"
webhookTitle.Parent = webhookBox

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
discordStatus.Text = canUseConfigFile() and "Сохраняется в maxi-hub-config.json" or "Файлы недоступны — webhook до перезапуска"
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

makeFlowToggle(discordOpts, "Отчёты в Discord", DiscordReportsEnabled, function(state)
	DiscordReportsEnabled = state
	FARM_REPORT_INTERVAL = DiscordReportMinutes * 60
	saveDiscordConfig()
end, 1)

makeFlowToggle(discordOpts, "Лог при остановке", DiscordLogOnStop, function(state)
	DiscordLogOnStop = state
	saveDiscordConfig()
end, 2)

makeFlowToggle(discordOpts, "Лог после продажи", DiscordLogOnSell, function(state)
	DiscordLogOnSell = state
	saveDiscordConfig()
end, 3)

intervalBox = Instance.new("Frame")
intervalBox.Size = UDim2.new(1, -8, 0, 52)
intervalBox.BackgroundTransparency = 1
intervalBox.LayoutOrder = 4
intervalBox.Parent = discordOpts

makeSlider(intervalBox, 0, "Интервал (мин)", 1, 120, DiscordReportMinutes, function(v)
	DiscordReportMinutes = math.floor(v)
	FARM_REPORT_INTERVAL = DiscordReportMinutes * 60
	saveDiscordConfig()
end)

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
testBtn.Text = "Тест webhook"
testBtn.AutoButtonColor = false
testBtn.Parent = discordBtns
addCorner(testBtn, 8)

saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(0.48, 0, 1, 0)
saveBtn.Position = UDim2.new(0.52, 0, 0, 0)
saveBtn.BackgroundColor3 = COLORS.panel
saveBtn.BorderSizePixel = 0
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 11
saveBtn.TextColor3 = COLORS.text
saveBtn.Text = "Сохранить"
saveBtn.AutoButtonColor = false
saveBtn.Parent = discordBtns
addCorner(saveBtn, 8)

discordHint = Instance.new("TextLabel")
discordHint.Size = UDim2.new(1, 0, 0, 48)
discordHint.BackgroundTransparency = 1
discordHint.Font = Enum.Font.Gotham
discordHint.TextSize = 10
discordHint.TextColor3 = COLORS.muted
discordHint.TextWrapped = true
discordHint.TextXAlignment = Enum.TextXAlignment.Left
discordHint.Text = "Сюда идут логи фарма: срубил, лут, время, Resources."
discordHint.LayoutOrder = 6
discordHint.Parent = discordWrap

function applyWebhookFromInput()
	UserDiscordWebhook = webhookInput.Text:gsub("^%s+", ""):gsub("%s+$", "")
	saveDiscordConfig()
end

webhookInput.FocusLost:Connect(function()
	applyWebhookFromInput()
end)

saveBtn.MouseButton1Click:Connect(function()
	applyWebhookFromInput()
	discordStatus.Text = "Сохранено"
	discordStatus.TextColor3 = COLORS.accent
	task.delay(2, function()
		if discordStatus.Parent then
			discordStatus.Text = canUseConfigFile() and "Сохраняется в maxi-hub-config.json" or "Файлы недоступны — webhook до перезапуска"
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

-- Кредиты (обязательная вкладка — не удалять)
buildMaxiHubCreditsTab(contentPages[4], {
	COLORS = COLORS,
	makeScrollPage = makeScrollPage,
	makeListWrap = makeListWrap,
	addCorner = addCorner,
}, { scriptLine = "Авто-фарм скрипт" })

ui.onInputBegan(function(input)
	if input.KeyCode ~= HOTKEY then return end
	local now = tick()
	if now - (genv.MaxiHubLastHotkeyAt or 0) < 0.45 then return end
	genv.MaxiHubLastHotkeyAt = now
	setFarmState(not FarmEnabled)
end)

ui.finalize()

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

