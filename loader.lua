local LOADER_VERSION = "2.1"

local BASES = {
	"https://raw.githubusercontent.com/kotMa0s1n/maxi-hub/master/",
	"https://cdn.jsdelivr.net/gh/kotMa0s1n/maxi-hub@master/",
}

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

local HttpService = game:GetService("HttpService")

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

local function isValidDownload(fileName, src)
	if type(src) ~= "string" or src == "" then
		return false
	end
	if fileName:sub(-5) == ".json" then
		local ok = pcall(function()
			HttpService:JSONDecode(src)
		end)
		return ok
	end
	local chunk = loadstring(src, "@" .. fileName)
	return chunk ~= nil
end

local function fetchOfficial(fileName)
	local bust = cacheBust()
	for _, base in ipairs(BASES) do
		local url = base .. fileName .. "?v=" .. bust
		local src = httpGet(url)
		if isValidDownload(fileName, src) then
			return src
		end
	end
	error("[MAXI HUB] Не скачался: " .. fileName .. " (loader v" .. LOADER_VERSION .. ")")
end

local genv = typeof(getgenv) == "function" and getgenv() or _G
genv.MaxiHubOfficialRaw = BASES[1]
genv.MaxiHubLoaderUrl = BASES[1] .. "loader.lua"
genv.MaxiHubRepoOnly = true
genv.MaxiHubLoaderVersion = LOADER_VERSION

if typeof(makefolder) == "function" then
	pcall(makefolder, "maxi-hub")
end

for _, name in ipairs(FILES) do
	writefile("maxi-hub/" .. name, fetchOfficial(name))
end

writefile("maxi-hub-whitelist.json", fetchOfficial("maxi-hub-whitelist.json"))

local launcher = readfile("maxi-hub/launcher.lua")
local chunk, err = loadstring(launcher, "@launcher.lua")
if not chunk then
	error("[MAXI HUB] launcher: " .. tostring(err))
end
chunk()
