-- Auto-updater module for RS Manager
-- Uses GitHub commit hash to detect updates - any new commit triggers update

local Updater = {}
Updater.__index = Updater

-- Version info (for display only)
Updater.VERSION = "1.2.3"
Updater.GITHUB_USER = "BRid37"
Updater.GITHUB_REPO = "RefinedStorage-Management"
Updater.GITHUB_BRANCH = "main"

local GITHUB_RAW = "https://raw.githubusercontent.com/"
local GITHUB_API = "https://api.github.com/repos/"
local INSTALL_DIR = "/rsmanager"
local COMMIT_FILE = "/rsmanager/.commit"

local files = {
    "rsmanager.lua",
    "lib/config.lua",
    "lib/rsbridge.lua",
    "lib/stockkeeper.lua",
    "lib/monitor.lua",
    "lib/gui.lua",
    "lib/utils.lua",
    "lib/updater.lua",
    "version.txt",
}

function Updater.new()
    local self = setmetatable({}, Updater)
    self.localCommit = self:getLocalCommit()
    self.remoteCommit = nil
    self.updateAvailable = false
    return self
end

function Updater:getLocalCommit()
    if fs.exists(COMMIT_FILE) then
        local file = fs.open(COMMIT_FILE, "r")
        if file then
            local hash = file.readAll()
            file.close()
            return hash:gsub("%s+", "")
        end
    end
    return nil
end

function Updater:saveLocalCommit(hash)
    local file = fs.open(COMMIT_FILE, "w")
    if file then
        file.write(hash)
        file.close()
        return true
    end
    return false
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

function Updater:getRemoteCommit()
    -- Use GitHub API to get latest commit hash
    local url = GITHUB_API .. Updater.GITHUB_USER .. "/" .. Updater.GITHUB_REPO .. "/commits/" .. Updater.GITHUB_BRANCH
    local response = http.get(url, {["User-Agent"] = "CC-Tweaked"})
    
    if response then
        local content = response.readAll()
        response.close()
        
        -- Parse JSON to get sha (simple pattern match)
        local sha = content:match('"sha"%s*:%s*"([a-f0-9]+)"')
        if sha then
            self.remoteCommit = sha:sub(1, 7)  -- Use short hash
            return self.remoteCommit
        end
    end
    return nil
end

function Updater:checkForUpdates()
    if not http then
        return false, "HTTP API disabled"
    end
    
    local remote = self:getRemoteCommit()
    if not remote then
        return false, "Could not check remote commit"
    end
    
    -- If no local commit stored, or commits differ, update available
    if not self.localCommit or self.localCommit ~= remote then
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
    
    -- Save the commit hash we just downloaded
    if success and self.remoteCommit then
        self:saveLocalCommit(self.remoteCommit)
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
    
    printFunc("Update available! (commit: " .. (self.remoteCommit or "unknown") .. ")")
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
        printFunc("RS Manager is up to date (v" .. Updater.VERSION .. ")")
        return false, info
    end
    
    printFunc("Update found! (commit: " .. (self.remoteCommit or "new") .. ")")
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
