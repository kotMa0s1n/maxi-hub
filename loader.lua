local RAW = "https://raw.githubusercontent.com/kotMa0s1n/maxi-hub/master/"
local FILES = {
	"launcher.lua",
	"maxi-hub-key.lua",
	"maxi-hub-core.lua",
	"maxi-hub-ui.lua",
}
local JSON_FILES = {
	"maxi-hub-config.json",
	"maxi-hub-key-cache.json",
	"maxi-hub-sell-state.json",
}

if typeof(game.HttpGet) ~= "function" then
	error("[MAXI HUB] Нужен executor с HttpGet")
end
if typeof(writefile) ~= "function" or typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then
	error("[MAXI HUB] Нужен executor с writefile/readfile/isfile")
end

local rawIsfile = isfile
local rawReadfile = readfile
local rawWritefile = writefile

local genv = typeof(getgenv) == "function" and getgenv() or _G
genv.MaxiHubLoaderUrl = RAW .. "loader.lua"
genv.MaxiHubDataDir = "maxi-hub"

if typeof(makefolder) == "function" then
	pcall(makefolder, "maxi-hub")
end

local jsonSet = {}
for _, name in ipairs(JSON_FILES) do
	jsonSet[name] = true
end

local function syncJsonPaths(name)
	local rootPath = name
	local subPath = "maxi-hub/" .. name
	local rootOk = rawIsfile(rootPath)
	local subOk = rawIsfile(subPath)
	if rootOk and not subOk then
		pcall(rawWritefile, subPath, rawReadfile(rootPath))
	elseif subOk and not rootOk then
		pcall(rawWritefile, rootPath, rawReadfile(subPath))
	end
end

for _, name in ipairs(JSON_FILES) do
	syncJsonPaths(name)
end

local function resolveJsonPath(path)
	if not jsonSet[path] then
		return path
	end
	if rawIsfile(path) then
		return path
	end
	local subPath = "maxi-hub/" .. path
	if rawIsfile(subPath) then
		return subPath
	end
	return path
end

isfile = function(path)
	return rawIsfile(resolveJsonPath(path))
end

readfile = function(path)
	return rawReadfile(resolveJsonPath(path))
end

writefile = function(path, data)
	local ok = rawWritefile(path, data)
	if jsonSet[path] then
		pcall(rawWritefile, "maxi-hub/" .. path, data)
	end
	return ok
end

if getgenv then
	local ge = getgenv()
	ge.isfile = isfile
	ge.readfile = readfile
	ge.writefile = writefile
end

for _, name in ipairs(FILES) do
	local path = "maxi-hub/" .. name
	local ok, src = pcall(function()
		return game:HttpGet(RAW .. name)
	end)
	if not ok or type(src) ~= "string" or src == "" then
		error("[MAXI HUB] Не скачался: " .. name)
	end
	rawWritefile(path, src)
end

local launcher = rawReadfile("maxi-hub/launcher.lua")
local chunk, err = loadstring(launcher, "@launcher.lua")
if not chunk then
	error("[MAXI HUB] launcher: " .. tostring(err))
end
chunk()
