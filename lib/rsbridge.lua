-- RS Bridge wrapper module for RS Manager
-- Compatible with Advanced Peripherals 0.7.57b on MC 1.21.1

local RSBridge = {}
RSBridge.__index = RSBridge

function RSBridge.new()
    local self = setmetatable({}, RSBridge)
    self.bridge = nil
    self.connected = false
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
    self.bridge = peripheral.find("rsBridge")
    if self.bridge then
        self.connected = true
        return true
    end
    return false
end

function RSBridge:isConnected()
    if not self.connected or not self.bridge then
        return false
    end
    -- Test connection
    local ok = pcall(function() self.bridge.getEnergyStorage() end)
    return ok
end

-- Energy methods
function RSBridge:getEnergyStorage()
    if not self.connected then return 0 end
    local ok, result = pcall(function() return self.bridge.getEnergyStorage() end)
    return ok and result or 0
end

function RSBridge:getMaxEnergyStorage()
    if not self.connected then return 1 end
    local ok, result = pcall(function() return self.bridge.getMaxEnergyStorage() end)
    return ok and result or 1
end

function RSBridge:getEnergyUsage()
    if not self.connected then return 0 end
    local ok, result = pcall(function() return self.bridge.getEnergyUsage() end)
    return ok and result or 0
end

-- Item methods with caching
function RSBridge:listItems(forceRefresh)
    if not self.connected then return {} end
    
    local now = os.epoch("utc") / 1000
    if not forceRefresh and self.cache.items and (now - self.cache.itemsTime) < self.cacheTimeout then
        return self.cache.items
    end
    
    local ok, result = pcall(function() return self.bridge.listItems() end)
    if ok and result then
        self.cache.items = result
        self.cache.itemsTime = now
        return result
    end
    return self.cache.items or {}
end

function RSBridge:getItem(name)
    if not self.connected then return nil end
    
    -- Try direct lookup first
    local ok, result = pcall(function() 
        return self.bridge.getItem({name = name})
    end)
    
    if ok and result then
        return result
    end
    
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
    
    local ok, result = pcall(function() return self.bridge.listFluids() end)
    if ok and result then
        self.cache.fluids = result
        self.cache.fluidsTime = now
        return result
    end
    return self.cache.fluids or {}
end

-- Crafting methods
function RSBridge:listCraftableItems(forceRefresh)
    if not self.connected then return {} end
    
    local now = os.epoch("utc") / 1000
    if not forceRefresh and self.cache.craftables and (now - self.cache.craftablesTime) < self.cacheTimeout then
        return self.cache.craftables
    end
    
    local ok, result = pcall(function() return self.bridge.listCraftableItems() end)
    if ok and result then
        self.cache.craftables = result
        self.cache.craftablesTime = now
        return result
    end
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
    
    local ok, result = pcall(function()
        return self.bridge.isItemCraftable({name = name})
    end)
    
    if ok then
        return result
    end
    
    -- Fallback
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
    
    local ok, result = pcall(function()
        return self.bridge.craftItem({name = name, count = amount})
    end)
    
    if ok then
        return result
    end
    return false, "Craft request failed"
end

function RSBridge:getCraftingTasks()
    if not self.connected then return {} end
    
    -- Try the standard method first
    local ok, result = pcall(function()
        return self.bridge.getCraftingTasks()
    end)
    
    if ok and result then
        return result
    end
    
    -- Some versions use different method names
    ok, result = pcall(function()
        return self.bridge.listCraftingTasks()
    end)
    
    if ok and result then
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
