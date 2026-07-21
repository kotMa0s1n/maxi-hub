local OFFICIAL_RAW = "https://raw.githubusercontent.com/kotMa0s1n/maxi-hub/master/"
local FILES = {
	"launcher.lua",
	"maxi-hub-key.lua",
	"maxi-hub-whitelist.lua",
	"maxi-hub-core.lua",
	"maxi-hub-ui.lua",
}

if typeof(game.HttpGet) ~= "function" then
	error("[MAXI HUB] Нужен executor с HttpGet")
end
if typeof(writefile) ~= "function" or typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then
	error("[MAXI HUB] Нужен executor с writefile/readfile/isfile")
end

local function isErrorPage(src)
	if type(src) ~= "string" or src == "" then
		return true
	end
	if src:sub(1, 1) ~= "<" then
		return false
	end
	local head = src:sub(1, 400):lower()
	return head:find("<!doctype", 1, true) ~= nil
		or head:find("<html", 1, true) ~= nil
end

local function httpGet(url)
	if typeof(request) == "function" then
		local ok, res = pcall(function()
			return request({ Url = url, Method = "GET" })
		end)
		if ok and type(res) == "table" and type(res.Body) == "string" and res.Body ~= "" then
			return res.Body
		end
	end
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
	return nil
end

local function fetchOfficial(fileName)
	local url = OFFICIAL_RAW .. fileName .. "?v=" .. tostring(os.time())
	local src = httpGet(url)
	if not src then
		error("[MAXI HUB] Не скачался: " .. fileName)
	end
	if isErrorPage(src) then
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

local whitelistJson = fetchOfficial("maxi-hub-whitelist.json")
writefile("maxi-hub-whitelist.json", whitelistJson)

local launcher = fetchOfficial("launcher.lua")
local chunk, err = loadstring(launcher, "@launcher.lua")
if not chunk then
	error("[MAXI HUB] launcher: " .. tostring(err))
end
chunk()
