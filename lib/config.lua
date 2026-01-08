-- Configuration module for RS Manager

local Config = {}

local defaults = {
    refreshRate = 1,        -- Monitor refresh rate in seconds (1s = real-time feel, data is cached)
    craftDelay = 10,        -- Delay between stock keeper checks
    lowStockPercent = 50,   -- Percentage threshold for low stock warning
    useMonitor = true,      -- Use external monitor if available
    monitorScale = 1,       -- Monitor text scale
    stockKeeperEnabled = true,
    maxCraftingJobs = 5,    -- Maximum concurrent crafting jobs
    autoUpdate = true,      -- Check for updates on startup
    monitorAutoScroll = true,  -- Auto-scroll external monitor lists
    monitorScrollSpeed = 3,    -- Seconds between scroll steps (1-10)
}

function Config.getDefaults()
    local copy = {}
    for k, v in pairs(defaults) do
        copy[k] = v
    end
    return copy
end

function Config.load(path)
    local config = Config.getDefaults()
    
    if fs.exists(path) then
        local file = fs.open(path, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            local loaded = textutils.unserialise(content)
            if loaded then
                for k, v in pairs(loaded) do
                    config[k] = v
                end
            end
        end
    end
    
    return config
end

function Config.save(path, config)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(path, "w")
    if file then
        file.write(textutils.serialise(config))
        file.close()
        return true
    end
    return false
end

return Config
