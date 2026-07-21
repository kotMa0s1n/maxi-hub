local RAW = "https://raw.githubusercontent.com/kotMa0s1n/maxi-hub/master/"
local genv = typeof(getgenv) == "function" and getgenv() or _G
genv.MaxiHubRemoteBase = RAW
genv.MaxiHubLoaderUrl = RAW .. "loader.lua"

if typeof(game.HttpGet) ~= "function" then
	error("[MAXI HUB] Нужен executor с HttpGet")
end

local src = game:HttpGet(RAW .. "launcher.lua")
local chunk, err = loadstring(src, "@launcher.lua")
if not chunk then
	error("[MAXI HUB] loader: " .. tostring(err))
end
chunk()
