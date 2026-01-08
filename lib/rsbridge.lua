-- RS Bridge wrapper module for RS Manager
-- Compatible with Advanced Peripherals 0.7.57b on MC 1.21.1
-- Optimized for minimal server impact with smart caching

local RSBridge = {}
RSBridge.__index = RSBridge

-- Logging configuration
local LOG_FILE = "/rsmanager/logs/rsbridge.log"
local MAX_LOG_SIZE = 50000  -- ~50KB max log size
local LOG_ENABLED = true

-- Rate limiting
local MIN_CALL_INTERVAL = 0.1  -- Minimum seconds between API calls
local lastCallTime = 0

local function log(message)
    if not LOG_ENABLED then return end
    
    -- Check log size and rotate if needed
    if fs.exists(LOG_FILE) then
        local size = fs.getSize(LOG_FILE)
        if size > MAX_LOG_SIZE then
            -- Rotate log - keep backup
            if fs.exists(LOG_FILE .. ".old") then
                fs.delete(LOG_FILE .. ".old")
            end
            fs.move(LOG_FILE, LOG_FILE .. ".old")
        end
    end
    
    local file = fs.open(LOG_FILE, "a")
    if file then
        file.write("[" .. os.date("%H:%M:%S") .. "] " .. tostring(message) .. "\n")
        file.close()
    end
end

-- Rate limiter to prevent server overload
local function rateLimit()
    local now = os.epoch("utc") / 1000
    local elapsed = now - lastCallTime
    if elapsed < MIN_CALL_INTERVAL then
        sleep(MIN_CALL_INTERVAL - elapsed)
    end
    lastCallTime = os.epoch("utc") / 1000
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
        energy = nil,
        energyTime = 0,
        maxEnergy = nil,
        maxEnergyTime = 0,
        tasks = nil,
        tasksTime = 0,
    }
    -- Cache timeouts (in seconds) - longer = less server load
    self.cacheTimeout = {
        items = 5,       -- Item list updates every 5s
        fluids = 5,      -- Fluid list updates every 5s
        craftables = 300, -- Craftable list: 5 min cache, manual refresh when adding items
        energy = 2,      -- Energy updates faster for responsiveness
        tasks = 3,       -- Crafting tasks update moderately
    }
    self.callCount = 0   -- Track API calls for debugging
    self.craftableIndex = {}  -- Quick lookup: name -> true for craftable items
    
    -- Dynamic field detection - remembers which field names work
    self.fieldMap = {
        -- Item fields: detected field name -> standard name
        itemAmount = nil,      -- amount, count, size
        itemName = nil,        -- name, id
        itemDisplayName = nil, -- displayName, label
        -- Fluid fields
        fluidAmount = nil,     -- amount, count, stored
        fluidName = nil,       -- name, id
        -- Task fields
        taskName = nil,        -- name, item, output
        taskAmount = nil,      -- amount, count, quantity
    }
    self.fieldMapLogged = false
    
    return self
end

-- Safely get a field from a table, trying multiple possible names
function RSBridge:getField(tbl, fieldType, ...)
    if not tbl then return nil end
    
    local candidates = {...}
    
    -- If we've already detected which field works, try it first
    if self.fieldMap[fieldType] then
        local val = tbl[self.fieldMap[fieldType]]
        if val ~= nil then return val end
    end
    
    -- Try each candidate
    for _, field in ipairs(candidates) do
        local val = tbl[field]
        if val ~= nil then
            -- Remember which field worked
            self.fieldMap[fieldType] = field
            return val
        end
    end
    
    return nil
end

-- Get item amount with auto-detection
function RSBridge:getItemAmountField(item)
    return self:getField(item, "itemAmount", "amount", "count", "size") or 0
end

-- Get item name with auto-detection
function RSBridge:getItemNameField(item)
    return self:getField(item, "itemName", "name", "id") or "unknown"
end

-- Get item display name with auto-detection
function RSBridge:getItemDisplayNameField(item)
    return self:getField(item, "itemDisplayName", "displayName", "label") or self:getItemNameField(item)
end

-- Get fluid amount with auto-detection
function RSBridge:getFluidAmountField(fluid)
    return self:getField(fluid, "fluidAmount", "amount", "count", "stored") or 0
end

-- Get task name with auto-detection
function RSBridge:getTaskNameField(task)
    -- Handle nested structures
    if task.stack and task.stack.name then return task.stack.name end
    if task.output and type(task.output) == "table" and task.output.name then return task.output.name end
    return self:getField(task, "taskName", "name", "item", "output") or "Unknown"
end

-- Get task display name
function RSBridge:getTaskDisplayNameField(task)
    if task.stack and task.stack.displayName then return task.stack.displayName end
    if task.output and type(task.output) == "table" and task.output.displayName then return task.output.displayName end
    return self:getField(task, "taskDisplayName", "displayName", "label") or self:getTaskNameField(task)
end

-- Get task amount with auto-detection  
function RSBridge:getTaskAmountField(task)
    if task.stack and task.stack.count then return task.stack.count end
    return self:getField(task, "taskAmount", "amount", "count", "quantity") or 1
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
    
    -- Rate limit API calls
    rateLimit()
    self.callCount = self.callCount + 1
    
    local ok, result = pcall(function(...)
        return self.bridge[methodName](...)
    end, ...)
    
    if not ok then
        log("Error calling " .. methodName .. ": " .. tostring(result))
        return nil, result
    end
    return result
end

-- Get API call statistics
function RSBridge:getStats()
    return {
        callCount = self.callCount,
        connected = self.connected,
        cacheHits = self.cacheHits or 0,
    }
end

function RSBridge:isConnected()
    if not self.connected or not self.bridge then
        return false
    end
    local ok = pcall(function() self.bridge.getEnergyUsage() end)
    return ok
end

-- Energy methods with caching
function RSBridge:getEnergyStorage()
    if not self.connected then return 0 end
    
    local now = os.epoch("utc") / 1000
    if self.cache.energy and (now - self.cache.energyTime) < self.cacheTimeout.energy then
        self.cacheHits = (self.cacheHits or 0) + 1
        return self.cache.energy
    end
    
    -- Try different method names
    local result = self:call("getEnergyStorage")
    if not result then
        result = self:call("getStoredEnergy")
    end
    
    if result then
        self.cache.energy = result
        self.cache.energyTime = now
    end
    
    return result or 0
end

function RSBridge:getMaxEnergyStorage()
    if not self.connected then return 1 end
    
    local now = os.epoch("utc") / 1000
    if self.cache.maxEnergy and (now - self.cache.maxEnergyTime) < self.cacheTimeout.energy then
        self.cacheHits = (self.cacheHits or 0) + 1
        return self.cache.maxEnergy
    end
    
    local result = self:call("getMaxEnergyStorage")
    if not result then
        result = self:call("getEnergyCapacity")
    end
    
    if result then
        self.cache.maxEnergy = result
        self.cache.maxEnergyTime = now
    end
    
    return result or 1
end

function RSBridge:getEnergyUsage()
    if not self.connected then return 0 end
    local result = self:call("getEnergyUsage")
    return result or 0
end

-- Item methods with smart caching
function RSBridge:listItems(forceRefresh)
    if not self.connected then return {} end
    
    local now = os.epoch("utc") / 1000
    if not forceRefresh and self.cache.items and (now - self.cache.itemsTime) < self.cacheTimeout.items then
        self.cacheHits = (self.cacheHits or 0) + 1
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
        return result
    end
    
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
    if not forceRefresh and self.cache.fluids and (now - self.cache.fluidsTime) < self.cacheTimeout.fluids then
        self.cacheHits = (self.cacheHits or 0) + 1
        return self.cache.fluids
    end
    
    -- Try different method names
    local result = self:call("listFluids")
    if not result then
        result = self:call("getFluids")
    end
    
    if result and type(result) == "table" then
        -- Log first fluid structure for debugging (only once)
        if #result > 0 and not self.fluidLogged then
            log("First fluid keys: " .. textutils.serialise(result[1]))
            self.fluidLogged = true
        end
        
        -- Normalize fluid data using dynamic field detection
        local normalized = {}
        for _, fluid in ipairs(result) do
            local f = {
                name = self:getField(fluid, "fluidName", "name", "id") or "unknown",
                displayName = self:getField(fluid, "fluidDisplayName", "displayName", "label") or fluid.name or "Unknown",
                amount = self:getFluidAmountField(fluid),
                raw = fluid
            }
            table.insert(normalized, f)
        end
        
        self.cache.fluids = normalized
        self.cache.fluidsTime = now
        return normalized
    end
    
    return self.cache.fluids or {}
end

-- Crafting methods
function RSBridge:listCraftableItems(forceRefresh)
    if not self.connected then return {} end
    
    local now = os.epoch("utc") / 1000
    if not forceRefresh and self.cache.craftables and (now - self.cache.craftablesTime) < self.cacheTimeout.craftables then
        self.cacheHits = (self.cacheHits or 0) + 1
        return self.cache.craftables
    end
    
    log("Refreshing craftable items list...")
    
    -- Try different method names
    local result = self:call("listCraftableItems")
    if not result then
        result = self:call("getCraftableItems")
    end
    
    if result and type(result) == "table" then
        self.cache.craftables = result
        self.cache.craftablesTime = now
        
        -- Build quick lookup index
        self.craftableIndex = {}
        for _, item in ipairs(result) do
            if item.name then
                self.craftableIndex[item.name] = true
            end
        end
        log("Craftable index built with " .. #result .. " items")
        
        return result
    end
    
    log("listCraftableItems failed or returned nil")
    return self.cache.craftables or {}
end

-- Force refresh craftables (call when user adds new stock item)
function RSBridge:refreshCraftables()
    return self:listCraftableItems(true)
end

function RSBridge:findCraftable(searchTerm, forceRefresh)
    local craftables = self:listCraftableItems(forceRefresh)
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

-- Check if item has a pattern (uses index for speed, can force refresh)
function RSBridge:isCraftable(name, forceRefresh)
    if not self.connected then return false end
    
    -- If forcing refresh or index empty, rebuild
    if forceRefresh or not next(self.craftableIndex) then
        self:listCraftableItems(true)
    end
    
    -- Quick index lookup
    if self.craftableIndex[name] then
        return true
    end
    
    -- Try direct API method as fallback
    local result = self:call("isItemCraftable", {name = name})
    if result ~= nil then return result end
    
    result = self:call("isItemCraftable", name)
    if result ~= nil then return result end
    
    return false
end

-- Check if item is missing (checks if we have enough materials or pattern missing)
-- Returns: canCraft (bool), reason (string: "ok", "no_pattern", "no_materials", "unknown")
function RSBridge:checkCraftStatus(name, amount)
    if not self.connected then return false, "not_connected" end
    
    amount = amount or 1
    
    -- First check if pattern exists
    local hasPat = self:isCraftable(name)
    if not hasPat then
        return false, "no_pattern"
    end
    
    -- Try to check if craftable with isItemCrafting or similar
    -- Advanced Peripherals may have isItemCrafting to check missing resources
    local result = self:call("isItemCrafting", {name = name})
    if result then
        -- Item is already being crafted
        return true, "already_crafting"
    end
    
    -- Try craftItem and check result/error
    -- Most RS Bridge implementations return false or error string when missing materials
    local craftResult, err = self:call("craftItem", {name = name, count = amount})
    
    if craftResult == true or craftResult == 1 then
        return true, "ok"
    end
    
    -- Analyze error message if available
    if err then
        local errLower = tostring(err):lower()
        if errLower:find("pattern") or errLower:find("recipe") then
            return false, "no_pattern"
        elseif errLower:find("material") or errLower:find("resource") or errLower:find("ingredient") then
            return false, "no_materials"
        end
    end
    
    -- If craft returned false but no specific error, likely missing materials
    if craftResult == false then
        return false, "no_materials"
    end
    
    return false, "unknown"
end

function RSBridge:craftItem(name, amount)
    if not self.connected then return false, "not_connected" end
    
    -- Check pattern first
    if not self:isCraftable(name) then
        log("craftItem failed: no pattern for " .. name)
        return false, "no_pattern"
    end
    
    -- Try with table parameter (AP style)
    local result, err = self:call("craftItem", {name = name, count = amount})
    if result then
        log("craftItem succeeded: " .. name .. " x" .. amount)
        return true, "ok"
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
    
    local now = os.epoch("utc") / 1000
    if self.cache.tasks and (now - self.cache.tasksTime) < self.cacheTimeout.tasks then
        self.cacheHits = (self.cacheHits or 0) + 1
        return self.cache.tasks
    end
    
    -- Try different method names
    local result = self:call("craftingTasks")
    if not result then
        result = self:call("getCraftingTasks")
    end
    if not result then
        result = self:call("listCraftingTasks")
    end
    
    if result and type(result) == "table" then
        -- Log first task structure for debugging
        if #result > 0 and not self.taskLogged then
            log("First crafting task structure: " .. textutils.serialise(result[1]))
            self.taskLogged = true
        end
        
        -- Normalize task data using dynamic field detection
        local normalized = {}
        for _, task in ipairs(result) do
            local t = {
                name = self:getTaskNameField(task),
                displayName = self:getTaskDisplayNameField(task),
                amount = self:getTaskAmountField(task),
                progress = task.progress or task.percentage or nil,
                raw = task
            }
            table.insert(normalized, t)
        end
        
        self.cache.tasks = normalized
        self.cache.tasksTime = now
        return normalized
    end
    
    return self.cache.tasks or {}
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
