-- Stock Keeper module for RS Manager
-- Maintains minimum stock levels via autocrafting

local StockKeeper = {}
StockKeeper.__index = StockKeeper

-- Pattern status constants
StockKeeper.STATUS_OK = "ok"
StockKeeper.STATUS_NO_PATTERN = "no_pattern"
StockKeeper.STATUS_NO_MATERIALS = "no_materials"
StockKeeper.STATUS_CRAFTING = "crafting"
StockKeeper.STATUS_UNKNOWN = "unknown"

function StockKeeper.new(bridge, configPath)
    local self = setmetatable({}, StockKeeper)
    self.bridge = bridge
    self.configPath = configPath
    self.enabled = true
    self.items = {}
    self.craftingQueue = {}
    self.lastCheck = 0
    self.checkInterval = 5
    self.lastPatternCheck = 0
    self.patternCheckInterval = 60  -- Check patterns every 60 seconds
    
    self:load()
    
    -- Validate patterns immediately after loading so items show on monitor at boot
    if #self.items > 0 then
        self:validatePatterns(true)
    end
    
    return self
end

function StockKeeper:load()
    if fs.exists(self.configPath) then
        local file = fs.open(self.configPath, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            local data = textutils.unserialise(content)
            if data then
                self.items = data.items or {}
                self.enabled = data.enabled ~= false
            end
        end
    end
end

function StockKeeper:save()
    local dir = fs.getDir(self.configPath)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(self.configPath, "w")
    if file then
        file.write(textutils.serialise({
            items = self.items,
            enabled = self.enabled
        }))
        file.close()
        return true
    end
    return false
end

function StockKeeper:isEnabled()
    return self.enabled
end

function StockKeeper:toggle()
    self.enabled = not self.enabled
    self:save()
    return self.enabled
end

function StockKeeper:enable()
    self.enabled = true
    self:save()
end

function StockKeeper:disable()
    self.enabled = false
    self:save()
end

function StockKeeper:getItems()
    return self.items
end

function StockKeeper:getActiveCount()
    local count = 0
    for _, item in ipairs(self.items) do
        if item.enabled ~= false and item.patternStatus ~= StockKeeper.STATUS_NO_PATTERN then
            count = count + 1
        end
    end
    return count
end

-- Validate all items have patterns, mark those missing
function StockKeeper:validatePatterns(forceRefresh)
    local now = os.epoch("utc") / 1000
    
    -- Skip if checked recently (unless forced)
    if not forceRefresh and (now - self.lastPatternCheck) < self.patternCheckInterval then
        return
    end
    
    self.lastPatternCheck = now
    local changed = false
    
    for i, item in ipairs(self.items) do
        if item and item.name then
            local isCraftable = self.bridge:isCraftable(item.name, forceRefresh)
            local oldStatus = item.patternStatus
            
            if isCraftable then
                self.items[i].patternStatus = StockKeeper.STATUS_OK
            else
                self.items[i].patternStatus = StockKeeper.STATUS_NO_PATTERN
            end
            
            if oldStatus ~= self.items[i].patternStatus then
                changed = true
            end
        end
    end
    
    if changed then
        self:save()
    end
    
    return changed
end

-- Get items with missing patterns
function StockKeeper:getMissingPatterns()
    local missing = {}
    for _, item in ipairs(self.items) do
        if item.patternStatus == StockKeeper.STATUS_NO_PATTERN then
            table.insert(missing, item)
        end
    end
    return missing
end

-- Check single item's pattern status
function StockKeeper:checkItemPattern(name, forceRefresh)
    for i, item in ipairs(self.items) do
        if item.name == name then
            local isCraftable = self.bridge:isCraftable(name, forceRefresh)
            if isCraftable then
                self.items[i].patternStatus = StockKeeper.STATUS_OK
                self:save()
                return true, StockKeeper.STATUS_OK
            else
                self.items[i].patternStatus = StockKeeper.STATUS_NO_PATTERN
                self:save()
                return false, StockKeeper.STATUS_NO_PATTERN
            end
        end
    end
    return false, "not_found"
end

function StockKeeper:addItem(name, amount, displayName)
    -- First verify the item is craftable
    local isCraftable = self.bridge:isCraftable(name, true)  -- Force refresh
    local patternStatus = isCraftable and StockKeeper.STATUS_OK or StockKeeper.STATUS_NO_PATTERN
    
    -- Check if item already exists
    for i, item in ipairs(self.items) do
        if item.name == name then
            self.items[i].amount = amount
            self.items[i].displayName = displayName or item.displayName
            self.items[i].patternStatus = patternStatus
            self:save()
            return true, patternStatus
        end
    end
    
    -- Add new item
    table.insert(self.items, {
        name = name,
        amount = amount,
        displayName = displayName or name,
        priority = 1,
        enabled = true,
        patternStatus = patternStatus,
        lastCraftStatus = nil,  -- Track last craft attempt result
        lastCraftTime = 0
    })
    
    self:save()
    return true, patternStatus
end

function StockKeeper:removeItem(name)
    for i, item in ipairs(self.items) do
        if item.name == name then
            table.remove(self.items, i)
            self:save()
            return true
        end
    end
    return false
end

function StockKeeper:updateItem(name, amount, priority)
    for i, item in ipairs(self.items) do
        if item.name == name then
            if amount then self.items[i].amount = amount end
            if priority then self.items[i].priority = priority end
            self:save()
            return true
        end
    end
    return false
end

function StockKeeper:getItem(name)
    for _, item in ipairs(self.items) do
        if item.name == name then
            return item
        end
    end
    return nil
end

function StockKeeper:getLowStock()
    local lowStock = {}
    
    for _, item in ipairs(self.items or {}) do
        if item and item.enabled ~= false and item.name and item.amount then
            local current = self.bridge:getItemAmount(item.name) or 0
            local target = item.amount or 1
            if current < target then
                table.insert(lowStock, {
                    name = item.name,
                    displayName = item.displayName or item.name,
                    current = current,
                    target = target,
                    needed = math.max(0, target - current),
                    priority = item.priority or 1,
                    patternStatus = item.patternStatus or StockKeeper.STATUS_OK,
                    lastCraftStatus = item.lastCraftStatus,
                    lastCraftTime = item.lastCraftTime
                })
            end
        end
    end
    
    -- Sort by priority (higher first), then by percentage
    -- Items with missing patterns go to the end
    table.sort(lowStock, function(a, b)
        -- Missing patterns last
        local aNoPattern = a.patternStatus == StockKeeper.STATUS_NO_PATTERN
        local bNoPattern = b.patternStatus == StockKeeper.STATUS_NO_PATTERN
        if aNoPattern ~= bNoPattern then
            return bNoPattern  -- non-missing first
        end
        
        if (a.priority or 1) ~= (b.priority or 1) then
            return (a.priority or 1) > (b.priority or 1)
        end
        local aPct = a.target > 0 and (a.current / a.target) or 0
        local bPct = b.target > 0 and (b.current / b.target) or 0
        return aPct < bPct
    end)
    
    return lowStock
end

function StockKeeper:check()
    if not self.enabled then return end
    
    -- Periodically validate patterns
    self:validatePatterns()
    
    local lowStock = self:getLowStock()
    local craftedAny = false
    
    for _, item in ipairs(lowStock) do
        -- Skip items with missing patterns
        if item.patternStatus == StockKeeper.STATUS_NO_PATTERN then
            goto continue
        end
        
        -- Check if already crafting
        local isCrafting = self.bridge:isItemCrafting(item.name)
        
        if isCrafting then
            -- Update status
            self:updateItemCraftStatus(item.name, StockKeeper.STATUS_CRAFTING)
        else
            -- Try to craft
            local success, reason = self.bridge:craftItem(item.name, item.needed)
            
            if success then
                self.craftingQueue[item.name] = {
                    amount = item.needed,
                    requestTime = os.epoch("utc")
                }
                self:updateItemCraftStatus(item.name, StockKeeper.STATUS_CRAFTING)
                craftedAny = true
            else
                -- Track the failure reason
                if reason == "no_pattern" then
                    self:updateItemCraftStatus(item.name, StockKeeper.STATUS_NO_PATTERN)
                    -- Mark pattern as missing
                    for i, it in ipairs(self.items) do
                        if it.name == item.name then
                            self.items[i].patternStatus = StockKeeper.STATUS_NO_PATTERN
                            break
                        end
                    end
                    self:save()
                elseif reason == "no_materials" then
                    self:updateItemCraftStatus(item.name, StockKeeper.STATUS_NO_MATERIALS)
                else
                    self:updateItemCraftStatus(item.name, StockKeeper.STATUS_UNKNOWN)
                end
            end
        end
        
        ::continue::
    end
    
    return craftedAny
end

-- Update craft status for an item
function StockKeeper:updateItemCraftStatus(name, status)
    for i, item in ipairs(self.items) do
        if item.name == name then
            self.items[i].lastCraftStatus = status
            self.items[i].lastCraftTime = os.epoch("utc") / 1000
            return
        end
    end
end

function StockKeeper:getCraftingQueue()
    return self.craftingQueue
end

function StockKeeper:clearCraftingQueue()
    self.craftingQueue = {}
end

function StockKeeper:getStatus()
    local items = self.items or {}
    local total = #items
    local satisfied = 0
    local low = 0
    local critical = 0
    
    for _, item in ipairs(items) do
        if item and item.enabled ~= false and item.name then
            local current = self.bridge:getItemAmount(item.name) or 0
            local target = item.amount or 1
            local percent = target > 0 and (current / target) or 0
            
            if percent >= 1 then
                satisfied = satisfied + 1
            elseif percent >= 0.5 then
                low = low + 1
            else
                critical = critical + 1
            end
        end
    end
    
    return {
        total = total,
        satisfied = satisfied,
        low = low,
        critical = critical,
        enabled = self.enabled
    }
end

function StockKeeper:importFromFile(path)
    if not fs.exists(path) then
        return false, "File not found"
    end
    
    local file = fs.open(path, "r")
    if not file then
        return false, "Could not open file"
    end
    
    local content = file.readAll()
    file.close()
    
    local data = textutils.unserialise(content)
    if not data or type(data) ~= "table" then
        return false, "Invalid file format"
    end
    
    local imported = 0
    for _, item in ipairs(data) do
        if item.name and item.amount then
            self:addItem(item.name, item.amount, item.displayName)
            imported = imported + 1
        end
    end
    
    return true, imported .. " items imported"
end

function StockKeeper:exportToFile(path)
    local file = fs.open(path, "w")
    if not file then
        return false, "Could not create file"
    end
    
    file.write(textutils.serialise(self.items))
    file.close()
    return true
end

return StockKeeper
