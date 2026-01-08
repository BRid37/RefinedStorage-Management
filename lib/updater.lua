-- Auto-updater module for RS Manager
-- Checks GitHub for updates and downloads new versions

local Updater = {}
Updater.__index = Updater

-- Version info
Updater.VERSION = "1.0.0"
Updater.GITHUB_USER = "BRid37"
Updater.GITHUB_REPO = "RefinedStorage-Management"
Updater.GITHUB_BRANCH = "main"

local GITHUB_RAW = "https://raw.githubusercontent.com/"
local VERSION_FILE = "version.txt"
local INSTALL_DIR = "/rsmanager"

local files = {
    "rsmanager.lua",
    "lib/config.lua",
    "lib/rsbridge.lua",
    "lib/stockkeeper.lua",
    "lib/monitor.lua",
    "lib/gui.lua",
    "lib/utils.lua",
    "lib/updater.lua",
}

function Updater.new()
    local self = setmetatable({}, Updater)
    self.currentVersion = Updater.VERSION
    self.remoteVersion = nil
    self.updateAvailable = false
    self.lastCheck = 0
    return self
end

local function getBaseUrl()
    return GITHUB_RAW .. Updater.GITHUB_USER .. "/" .. Updater.GITHUB_REPO .. "/" .. Updater.GITHUB_BRANCH .. "/"
end

local function httpGet(url)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        return content
    end
    return nil
end

local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local file = fs.open(path, "w")
    if file then
        file.write(content)
        file.close()
        return true
    end
    return false
end

local function parseVersion(versionStr)
    if not versionStr then return {0, 0, 0} end
    versionStr = versionStr:gsub("%s+", ""):gsub("^v", "")
    local parts = {}
    for num in versionStr:gmatch("(%d+)") do
        table.insert(parts, tonumber(num) or 0)
    end
    while #parts < 3 do
        table.insert(parts, 0)
    end
    return parts
end

local function compareVersions(v1, v2)
    local p1 = parseVersion(v1)
    local p2 = parseVersion(v2)
    
    for i = 1, 3 do
        if p1[i] > p2[i] then return 1 end
        if p1[i] < p2[i] then return -1 end
    end
    return 0
end

function Updater:getRemoteVersion()
    local url = getBaseUrl() .. VERSION_FILE
    local content = httpGet(url)
    if content then
        self.remoteVersion = content:gsub("%s+", "")
        return self.remoteVersion
    end
    return nil
end

function Updater:checkForUpdates()
    if not http then
        return false, "HTTP API disabled"
    end
    
    local remote = self:getRemoteVersion()
    if not remote then
        return false, "Could not check remote version"
    end
    
    self.lastCheck = os.epoch("utc")
    
    if compareVersions(remote, self.currentVersion) > 0 then
        self.updateAvailable = true
        return true, remote
    end
    
    self.updateAvailable = false
    return false, "Up to date"
end

function Updater:downloadUpdate(progressCallback)
    if not http then
        return false, "HTTP API disabled"
    end
    
    local baseUrl = getBaseUrl()
    local success = true
    local downloaded = 0
    local total = #files
    
    for _, file in ipairs(files) do
        local url = baseUrl .. file
        local path = INSTALL_DIR .. "/" .. file
        
        if progressCallback then
            progressCallback(file, downloaded, total)
        end
        
        local content = httpGet(url)
        if content then
            if writeFile(path, content) then
                downloaded = downloaded + 1
            else
                success = false
            end
        else
            success = false
        end
    end
    
    if progressCallback then
        progressCallback("complete", downloaded, total)
    end
    
    -- Update local version file
    if success then
        writeFile(INSTALL_DIR .. "/" .. VERSION_FILE, self.remoteVersion or Updater.VERSION)
    end
    
    return success, downloaded .. "/" .. total .. " files updated"
end

function Updater:performUpdate(printFunc)
    printFunc = printFunc or print
    
    printFunc("Checking for updates...")
    local hasUpdate, info = self:checkForUpdates()
    
    if not hasUpdate then
        printFunc("No updates available. " .. (info or ""))
        return false
    end
    
    printFunc("Update available: v" .. self.currentVersion .. " -> v" .. self.remoteVersion)
    printFunc("Downloading update...")
    
    local success, result = self:downloadUpdate(function(file, current, total)
        if file == "complete" then
            printFunc("Download complete: " .. current .. "/" .. total .. " files")
        else
            printFunc("  Downloading: " .. file)
        end
    end)
    
    if success then
        printFunc("Update successful! Restart to apply changes.")
        return true
    else
        printFunc("Update failed: " .. result)
        return false
    end
end

function Updater:autoUpdate(config, printFunc)
    printFunc = printFunc or function() end
    
    -- Check if auto-update is enabled
    if config and config.autoUpdate == false then
        return false, "Auto-update disabled"
    end
    
    -- Check if HTTP is available
    if not http then
        return false, "HTTP API disabled"
    end
    
    printFunc("Checking for updates...")
    
    local hasUpdate, info = self:checkForUpdates()
    if not hasUpdate then
        printFunc("RS Manager is up to date (v" .. self.currentVersion .. ")")
        return false, info
    end
    
    printFunc("Update found: v" .. self.remoteVersion)
    printFunc("Downloading...")
    
    local success, result = self:downloadUpdate(function(file, current, total)
        if file ~= "complete" then
            printFunc("  " .. file)
        end
    end)
    
    if success then
        printFunc("Update complete! Restarting...")
        sleep(1)
        os.reboot()
    else
        printFunc("Update failed, continuing with current version")
        return false, result
    end
    
    return true
end

function Updater.getVersion()
    return Updater.VERSION
end

return Updater
