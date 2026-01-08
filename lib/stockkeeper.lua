-- Stock Keeper module for RS Manager
-- Maintains minimum stock levels via autocrafting

local StockKeeper = {}
StockKeeper.__index = StockKeeper

function StockKeeper.new(bridge, configPath)
    local self = setmetatable({}, StockKeeper)
    self.bridge = bridge
    self.configPath = configPath
    self.enabled = true
    self.items = {}
    self.craftingQueue = {}
    self.lastCheck = 0
    self.checkInterval = 5
    
    self:load()
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
    return #self.items
end

function StockKeeper:addItem(name, amount, displayName)
    -- Check if item already exists
    for i, item in ipairs(self.items) do
        if item.name == name then
            self.items[i].amount = amount
            self.items[i].displayName = displayName or item.displayName
            self:save()
            return true
        end
    end
    
    -- Add new item
    table.insert(self.items, {
        name = name,
        amount = amount,
        displayName = displayName or name,
        priority = 1,
        enabled = true
    })
    
    self:save()
    return true
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
    
    for _, item in ipairs(self.items) do
        if item.enabled ~= false then
            local current = self.bridge:getItemAmount(item.name)
            if current < item.amount then
                table.insert(lowStock, {
                    name = item.name,
                    displayName = item.displayName or item.name,
                    current = current,
                    target = item.amount,
                    needed = item.amount - current,
                    priority = item.priority or 1
                })
            end
        end
    end
    
    -- Sort by priority (higher first), then by percentage
    table.sort(lowStock, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return (a.current / a.target) < (b.current / b.target)
    end)
    
    return lowStock
end

function StockKeeper:check()
    if not self.enabled then return end
    
    local lowStock = self:getLowStock()
    
    for _, item in ipairs(lowStock) do
        -- Check if already crafting
        local isCrafting = self.bridge:isItemCrafting(item.name)
        
        if not isCrafting then
            -- Check if craftable
            if self.bridge:isCraftable(item.name) then
                -- Request craft
                local success = self.bridge:craftItem(item.name, item.needed)
                if success then
                    self.craftingQueue[item.name] = {
                        amount = item.needed,
                        requestTime = os.epoch("utc")
                    }
                end
            end
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
    local total = #self.items
    local satisfied = 0
    local low = 0
    local critical = 0
    
    for _, item in ipairs(self.items) do
        if item.enabled ~= false then
            local current = self.bridge:getItemAmount(item.name)
            local percent = current / item.amount
            
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
