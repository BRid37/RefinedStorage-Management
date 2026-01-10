-- Storage monitoring module for RS Manager
-- Tracks file sizes and provides storage analytics

local Storage = {}
Storage.__index = Storage

function Storage.new(baseDir)
    local self = setmetatable({}, Storage)
    self.baseDir = baseDir or "/rsmanager"
    return self
end

-- Get file size in bytes
function Storage:getFileSize(path)
    if fs.exists(path) and not fs.isDir(path) then
        return fs.getSize(path)
    end
    return 0
end

-- Get directory size recursively
function Storage:getDirectorySize(path)
    if not fs.exists(path) then return 0 end
    
    local total = 0
    if fs.isDir(path) then
        local files = fs.list(path)
        for _, file in ipairs(files) do
            local fullPath = fs.combine(path, file)
            if fs.isDir(fullPath) then
                total = total + self:getDirectorySize(fullPath)
            else
                total = total + fs.getSize(fullPath)
            end
        end
    else
        total = fs.getSize(path)
    end
    return total
end

-- Count items in a serialized file
function Storage:countItemsInFile(path)
    if not fs.exists(path) then return 0 end
    
    local file = fs.open(path, "r")
    if not file then return 0 end
    
    local content = file.readAll()
    file.close()
    
    local ok, data = pcall(textutils.unserialise, content)
    if ok and type(data) == "table" then
        return #data
    end
    return 0
end

-- Get storage statistics
function Storage:getStats()
    local stats = {
        files = {},
        totalSize = 0,
        warnings = {}
    }
    
    -- Check stock keeper
    local stockPath = self.baseDir .. "/config/stockkeeper.lua"
    if fs.exists(stockPath) then
        local size = self:getFileSize(stockPath)
        local items = self:countItemsInFile(stockPath)
        table.insert(stats.files, {
            name = "Stock Keeper",
            path = stockPath,
            size = size,
            items = items,
            category = "config"
        })
        stats.totalSize = stats.totalSize + size
        
        -- Warn if too many items
        if items > 100 then
            table.insert(stats.warnings, {
                type = "large_list",
                file = "Stock Keeper",
                items = items,
                message = "Stock Keeper has " .. items .. " items (recommended max: 100)"
            })
        end
        if size > 50000 then
            table.insert(stats.warnings, {
                type = "large_file",
                file = "Stock Keeper",
                size = size,
                message = "Stock Keeper file is " .. math.floor(size/1000) .. "KB (recommended max: 50KB)"
            })
        end
    end
    
    -- Check monitored items
    local monitorPath = self.baseDir .. "/config/monitored.lua"
    if fs.exists(monitorPath) then
        local size = self:getFileSize(monitorPath)
        local items = self:countItemsInFile(monitorPath)
        table.insert(stats.files, {
            name = "Monitor Items",
            path = monitorPath,
            size = size,
            items = items,
            category = "config"
        })
        stats.totalSize = stats.totalSize + size
        
        if items > 50 then
            table.insert(stats.warnings, {
                type = "large_list",
                file = "Monitor Items",
                items = items,
                message = "Monitor Items has " .. items .. " items (recommended max: 50)"
            })
        end
    end
    
    -- Check logs directory
    local logsPath = self.baseDir .. "/logs"
    if fs.exists(logsPath) then
        local size = self:getDirectorySize(logsPath)
        local fileCount = #fs.list(logsPath)
        table.insert(stats.files, {
            name = "Logs",
            path = logsPath,
            size = size,
            items = fileCount,
            category = "logs"
        })
        stats.totalSize = stats.totalSize + size
        
        if size > 200000 then
            table.insert(stats.warnings, {
                type = "large_directory",
                file = "Logs",
                size = size,
                message = "Logs directory is " .. math.floor(size/1000) .. "KB (consider cleaning)"
            })
        end
    end
    
    -- Check data directory
    local dataPath = self.baseDir .. "/data"
    if fs.exists(dataPath) then
        local size = self:getDirectorySize(dataPath)
        table.insert(stats.files, {
            name = "Data",
            path = dataPath,
            size = size,
            items = #fs.list(dataPath),
            category = "data"
        })
        stats.totalSize = stats.totalSize + size
    end
    
    -- Sort files by size (largest first)
    table.sort(stats.files, function(a, b)
        return a.size > b.size
    end)
    
    return stats
end

-- Format bytes for display
function Storage.formatBytes(bytes)
    if bytes >= 1048576 then
        return string.format("%.2f MB", bytes / 1048576)
    elseif bytes >= 1024 then
        return string.format("%.2f KB", bytes / 1024)
    else
        return bytes .. " B"
    end
end

-- Clean old log files
function Storage:cleanLogs(keepDays)
    keepDays = keepDays or 7
    local logsPath = self.baseDir .. "/logs"
    if not fs.exists(logsPath) then return 0 end
    
    local now = os.epoch("utc") / 1000
    local cutoff = now - (keepDays * 86400)  -- days to seconds
    local deleted = 0
    
    for _, file in ipairs(fs.list(logsPath)) do
        local path = fs.combine(logsPath, file)
        if not fs.isDir(path) and file:match("%.old$") then
            -- Delete .old log files
            fs.delete(path)
            deleted = deleted + 1
        end
    end
    
    return deleted
end

return Storage
