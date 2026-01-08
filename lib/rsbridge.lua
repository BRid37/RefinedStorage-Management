-- RS Bridge wrapper module for RS Manager
-- Compatible with Advanced Peripherals 0.7.57b on MC 1.21.1

local RSBridge = {}
RSBridge.__index = RSBridge

-- Logging helper
local LOG_FILE = "/rsmanager/logs/rsbridge.log"
local function log(message)
    local file = fs.open(LOG_FILE, "a")
    if file then
        file.write("[" .. os.date("%H:%M:%S") .. "] " .. tostring(message) .. "\n")
        file.close()
    end
end

function RSBridge.new()
    local self = setmetatable({}, RSBridge)
    self.bridge = nil
    self.connected = false
    self.methods = {}
    self.cache = {
        items = nil,
        itemsTime = 0,
        fluids = nil,
        fluidsTime = 0,
        craftables = nil,
        craftablesTime = 0,
    }
    self.cacheTimeout = 2 -- seconds
    return self
end

function RSBridge:connect()
    self.bridge = peripheral.find("rs_bridge")
    if self.bridge then
        self.connected = true
        -- Discover available methods
        self:discoverMethods()
        return true
    end
    return false
end

function RSBridge:discoverMethods()
    if not self.bridge then return end
    
    local name = peripheral.getName(self.bridge)
    self.methods = peripheral.getMethods(name)
    
    -- Log discovered methods
    log("=== RS Bridge Methods Discovered ===")
    for _, method in ipairs(self.methods) do
        log("  " .. method)
    end
    log("=== End Methods ===")
end

function RSBridge:hasMethod(methodName)
    for _, m in ipairs(self.methods) do
        if m == methodName then return true end
    end
    return false
end

function RSBridge:call(methodName, ...)
    if not self.connected or not self.bridge then 
        return nil, "Not connected"
    end
    
    local ok, result = pcall(function(...)
        return self.bridge[methodName](...)
    end, ...)
    
    if not ok then
        log("Error calling " .. methodName .. ": " .. tostring(result))
        return nil, result
    end
    return result
end

function RSBridge:isConnected()
    if not self.connected or not self.bridge then
        return false
    end
    local ok = pcall(function() self.bridge.getEnergyUsage() end)
    return ok
end

-- Energy methods (these work in AP 0.7.57b)
function RSBridge:getEnergyStorage()
    if not self.connected then return 0 end
    -- Try different method names
    local result = self:call("getEnergyStorage")
    if result then return result end
    
    result = self:call("getStoredEnergy")
    if result then return result end
    
    return 0
end

function RSBridge:getMaxEnergyStorage()
    if not self.connected then return 1 end
    local result = self:call("getMaxEnergyStorage")
    if result then return result end
    
    result = self:call("getEnergyCapacity")
    if result then return result end
    
    return 1
end

function RSBridge:getEnergyUsage()
    if not self.connected then return 0 end
    local result = self:call("getEnergyUsage")
    return result or 0
end

-- Item methods with caching
function RSBridge:listItems(forceRefresh)
    if not self.connected then return {} end
    
    local now = os.epoch("utc") / 1000
    if not forceRefresh and self.cache.items and (now - self.cache.itemsTime) < self.cacheTimeout then
        return self.cache.items
    end
    
    -- Try different method names for listing items
    local result = self:call("listItems")
    if not result then
        result = self:call("getItems")
    end
    
    if result and type(result) == "table" then
        self.cache.items = result
        self.cache.itemsTime = now
        log("listItems returned " .. #result .. " items")
        return result
    end
    
    log("listItems failed or returned nil")
    return self.cache.items or {}
end

function RSBridge:getItem(name)
    if not self.connected then return nil end
    
    -- Try direct lookup with table parameter
    local result = self:call("getItem", {name = name})
    if result then return result end
    
    -- Try with just the name string
    result = self:call("getItem", name)
    if result then return result end
    
    -- Fallback to searching list
    local items = self:listItems()
    for _, item in ipairs(items) do
        if item.name == name then
            return item
        end
    end
    return nil
end

function RSBridge:getItemAmount(name)
    local item = self:getItem(name)
    if item then
        return item.amount or 0
    end
    return 0
end

function RSBridge:findItem(searchTerm)
    local items = self:listItems()
    local results = {}
    local searchLower = searchTerm:lower()
    
    for _, item in ipairs(items) do
        local displayName = (item.displayName or item.name):lower()
        local itemName = item.name:lower()
        
        if displayName:find(searchLower, 1, true) or itemName:find(searchLower, 1, true) then
            table.insert(results, item)
        end
    end
    
    -- Sort by relevance (exact matches first, then by amount)
    table.sort(results, function(a, b)
        local aName = (a.displayName or a.name):lower()
        local bName = (b.displayName or b.name):lower()
        local aExact = aName == searchLower
        local bExact = bName == searchLower
        
        if aExact ~= bExact then
            return aExact
        end
        return (a.amount or 0) > (b.amount or 0)
    end)
    
    return results
end

-- Fluid methods
function RSBridge:listFluids(forceRefresh)
    if not self.connected then return {} end
    
    local now = os.epoch("utc") / 1000
    if not forceRefresh and self.cache.fluids and (now - self.cache.fluidsTime) < self.cacheTimeout then
        return self.cache.fluids
    end
    
    -- Try different method names
    local result = self:call("listFluids")
    if not result then
        result = self:call("getFluids")
    end
    
    if result and type(result) == "table" then
        self.cache.fluids = result
        self.cache.fluidsTime = now
        log("listFluids returned " .. #result .. " fluids")
        return result
    end
    
    log("listFluids failed or returned nil")
    return self.cache.fluids or {}
end

-- Crafting methods
function RSBridge:listCraftableItems(forceRefresh)
    if not self.connected then return {} end
    
    local now = os.epoch("utc") / 1000
    if not forceRefresh and self.cache.craftables and (now - self.cache.craftablesTime) < self.cacheTimeout then
        return self.cache.craftables
    end
    
    -- Try different method names
    local result = self:call("listCraftableItems")
    if not result then
        result = self:call("getCraftableItems")
    end
    
    if result and type(result) == "table" then
        self.cache.craftables = result
        self.cache.craftablesTime = now
        log("listCraftableItems returned " .. #result .. " craftables")
        return result
    end
    
    log("listCraftableItems failed or returned nil")
    return self.cache.craftables or {}
end

function RSBridge:findCraftable(searchTerm)
    local craftables = self:listCraftableItems()
    local results = {}
    local searchLower = searchTerm:lower()
    
    for _, item in ipairs(craftables) do
        local displayName = (item.displayName or item.name):lower()
        local itemName = item.name:lower()
        
        if displayName:find(searchLower, 1, true) or itemName:find(searchLower, 1, true) then
            table.insert(results, item)
        end
    end
    
    table.sort(results, function(a, b)
        local aName = (a.displayName or a.name):lower()
        local bName = (b.displayName or b.name):lower()
        return aName < bName
    end)
    
    return results
end

function RSBridge:isCraftable(name)
    if not self.connected then return false end
    
    -- Try direct method with table
    local result = self:call("isItemCraftable", {name = name})
    if result ~= nil then return result end
    
    -- Try with string
    result = self:call("isItemCraftable", name)
    if result ~= nil then return result end
    
    -- Fallback to searching craftables list
    local craftables = self:listCraftableItems()
    for _, item in ipairs(craftables) do
        if item.name == name then
            return true
        end
    end
    return false
end

function RSBridge:craftItem(name, amount)
    if not self.connected then return false, "Not connected" end
    
    -- Try with table parameter (AP style)
    local result = self:call("craftItem", {name = name, count = amount})
    if result then
        log("craftItem succeeded: " .. name .. " x" .. amount)
        return result
    end
    
    -- Try alternate format
    result = self:call("craftItem", name, amount)
    if result then
        log("craftItem (alt) succeeded: " .. name .. " x" .. amount)
        return result
    end
    
    log("craftItem failed: " .. name)
    return false, "Craft request failed"
end

function RSBridge:getCraftingTasks()
    if not self.connected then return {} end
    
    -- Try different method names
    local result = self:call("craftingTasks")
    if result and type(result) == "table" then
        log("craftingTasks returned " .. #result .. " tasks")
        return result
    end
    
    result = self:call("getCraftingTasks")
    if result and type(result) == "table" then
        log("getCraftingTasks returned " .. #result .. " tasks")
        return result
    end
    
    result = self:call("listCraftingTasks")
    if result and type(result) == "table" then
        log("listCraftingTasks returned " .. #result .. " tasks")
        return result
    end
    
    return {}
end

function RSBridge:isItemCrafting(name)
    local tasks = self:getCraftingTasks()
    for _, task in ipairs(tasks) do
        if task.name == name then
            return true, task
        end
    end
    return false
end

-- Export/Import methods
function RSBridge:exportItem(name, amount, direction)
    if not self.connected then return 0 end
    
    local ok, result = pcall(function()
        return self.bridge.exportItem({name = name, count = amount}, direction or "down")
    end)
    
    return ok and result or 0
end

function RSBridge:importItem(direction)
    if not self.connected then return 0 end
    
    local ok, result = pcall(function()
        return self.bridge.importItem(direction or "down")
    end)
    
    return ok and result or 0
end

-- Pattern methods (for autocrafting management)
function RSBridge:getPatterns()
    if not self.connected then return {} end
    
    local ok, result = pcall(function()
        return self.bridge.getPatterns()
    end)
    
    return ok and result or {}
end

-- Refresh cache
function RSBridge:refreshCache()
    self:listItems(true)
    self:listFluids(true)
    self:listCraftableItems(true)
end

-- Get all available methods (useful for debugging)
function RSBridge:getMethods()
    if not self.bridge then return {} end
    return peripheral.getMethods(peripheral.getName(self.bridge))
end

return RSBridge
