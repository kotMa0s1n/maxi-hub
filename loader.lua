local RAW = "https://raw.githubusercontent.com/kotMa0s1n/maxi-hub/master/"
local FILES = {
	"launcher.lua",
	"maxi-hub-key.lua",
	"maxi-hub-whitelist.lua",
	"maxi-hub-core.lua",
	"maxi-hub-ui.lua",
}
local DATA_FILES = {
	"maxi-hub-whitelist.json",
}

if typeof(game.HttpGet) ~= "function" then
	error("[MAXI HUB] Нужен executor с HttpGet")
end
if typeof(writefile) ~= "function" or typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then
	error("[MAXI HUB] Нужен executor с writefile/readfile/isfile")
end

local genv = typeof(getgenv) == "function" and getgenv() or _G
genv.MaxiHubLoaderUrl = RAW .. "loader.lua"
genv.MaxiHubRemoteBase = RAW

if typeof(makefolder) == "function" then
	pcall(makefolder, "maxi-hub")
end

for _, name in ipairs(FILES) do
	local path = "maxi-hub/" .. name
	local ok, src = pcall(function()
		return game:HttpGet(RAW .. name)
	end)
	if not ok or type(src) ~= "string" or src == "" then
		error("[MAXI HUB] Не скачался: " .. name)
	end
	writefile(path, src)
end

for _, name in ipairs(DATA_FILES) do
	local ok, src = pcall(function()
		return game:HttpGet(RAW .. name)
	end)
	if ok and type(src) == "string" and src ~= "" then
		writefile(name, src)
	end
end

local launcher = readfile("maxi-hub/launcher.lua")
local chunk, err = loadstring(launcher, "@launcher.lua")
if not chunk then
	error("[MAXI HUB] launcher: " .. tostring(err))
end
chunk()
