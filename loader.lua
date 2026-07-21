local OFFICIAL_RAW = "https://raw.githubusercontent.com/kotMa0s1n/maxi-hub/master/"
local FILES = {
	"launcher.lua",
	"maxi-hub-key.lua",
	"maxi-hub-core.lua",
	"maxi-hub-ui.lua",
}

if typeof(game.HttpGet) ~= "function" then
	error("[MAXI HUB] Нужен executor с HttpGet")
end
if typeof(writefile) ~= "function" or typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then
	error("[MAXI HUB] Нужен executor с writefile/readfile/isfile")
end

local function fetchOfficial(fileName)
	local ok, src = pcall(function()
		return game:HttpGet(OFFICIAL_RAW .. fileName)
	end)
	if not ok or type(src) ~= "string" or src == "" then
		error("[MAXI HUB] Не скачался: " .. fileName)
	end
	if src:find("<!DOCTYPE", 1, true) or src:find("<html", 1, true) then
		error("[MAXI HUB] Не официальный файл: " .. fileName)
	end
	return src
end

local genv = typeof(getgenv) == "function" and getgenv() or _G
genv.MaxiHubOfficialRaw = OFFICIAL_RAW
genv.MaxiHubLoaderUrl = OFFICIAL_RAW .. "loader.lua"
genv.MaxiHubRepoOnly = true

if typeof(makefolder) == "function" then
	pcall(makefolder, "maxi-hub")
end

for _, name in ipairs(FILES) do
	writefile("maxi-hub/" .. name, fetchOfficial(name))
end

local launcher = fetchOfficial("launcher.lua")
local chunk, err = loadstring(launcher, "@launcher.lua")
if not chunk then
	error("[MAXI HUB] launcher: " .. tostring(err))
end
chunk()
