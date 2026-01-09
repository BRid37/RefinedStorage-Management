-- External Monitor module for RS Manager
-- Displays RS status on external monitors
-- Supports scaling for small to large multi-block monitors

-- Utils functions (inline to avoid require issues)
local Utils = {}

function Utils.formatNumber(num)
    if not num then return "0" end
    if num >= 1000000000 then
        return string.format("%.1fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    end
    return tostring(math.floor(num))
end

function Utils.truncate(str, maxLen)
    if not str then return "" end
    if #str <= maxLen then return str end
    return str:sub(1, maxLen - 3) .. "..."
end

local Monitor = {}
Monitor.__index = Monitor

-- Monitor size thresholds
Monitor.MIN_WIDTH = 18   -- Minimum 2 wide monitor
Monitor.MIN_HEIGHT = 12  -- Minimum 2 tall monitor
Monitor.MEDIUM_WIDTH = 39  -- 4+ wide
Monitor.MEDIUM_HEIGHT = 19 -- 3+ tall
Monitor.LARGE_WIDTH = 57   -- 6+ wide
Monitor.LARGE_HEIGHT = 26  -- 4+ tall

function Monitor.new(bridge, stockKeeper, monitoredItems, config)
    local self = setmetatable({}, Monitor)
    self.bridge = bridge
    self.stockKeeper = stockKeeper
    self.monitoredItems = monitoredItems or {}  -- Item monitor list
    self.config = config or {}
    self.monitor = nil
    self.scale = 0.5  -- Default scale for larger text
    self.width = 0
    self.height = 0
    self.layout = "small"  -- small, medium, large
    self.tooSmall = false
    self.lastDrawn = {}  -- Cache of last drawn values to avoid redraw
    
    -- Auto-scroll state
    self.scrollOffset = 0
    self.scrollTimer = 0
    self.lastScrollTime = os.epoch("utc") / 1000
    
    self:findMonitor()
    return self
end

-- Update monitored items reference
function Monitor:setMonitoredItems(items)
    self.monitoredItems = items or {}
end

function Monitor:findMonitor()
    local ok, result = pcall(function()
        return peripheral.find("monitor")
    end)
    
    if ok and result then
        self.monitor = result
        self:autoScale()
        return true
    end
    
    if not ok then
        print("Error finding monitor: " .. tostring(result))
    end
    return false
end

function Monitor:autoScale()
    if not self.monitor then return end
    
    -- Get monitor dimensions at smallest scale to determine optimal scaling
    local ok = pcall(function()
        self.monitor.setTextScale(0.5)
    end)
    if not ok then return end
    
    local ok2, baseW, baseH = pcall(function()
        return self.monitor.getSize()
    end)
    if not ok2 then return end
    
    -- Calculate how much content we need to show
    local hasStock = self.stockKeeper and self.stockKeeper:getActiveCount() > 0
    local hasMonitor = self.monitoredItems and #self.monitoredItems > 0
    local contentSections = 1 -- Always have system info
    if hasStock then contentSections = contentSections + 1 end
    if hasMonitor then contentSections = contentSections + 1 end
    
    -- Try scales from largest to smallest to maximize readability
    local scales = {2, 1.5, 1, 0.5}
    
    for _, scale in ipairs(scales) do
        local ok = pcall(function()
            self.monitor.setTextScale(scale)
        end)
        if not ok then break end
        
        local ok2, w, h = pcall(function()
            return self.monitor.getSize()
        end)
        if not ok2 then break end
        
        -- Check if this scale provides enough space for content
        -- Need at least 18 wide and 12 tall for basic display
        if w >= self.MIN_WIDTH and h >= self.MIN_HEIGHT then
            -- For monitors with little content, prefer larger text
            if contentSections <= 1 and scale >= 1.5 then
                self.scale = scale
                self.width = w
                self.height = h
                self:determineLayout()
                self.tooSmall = false
                return
            -- For monitors with more content, ensure we have enough space
            elseif w >= 25 and h >= 15 then
                self.scale = scale
                self.width = w
                self.height = h
                self:determineLayout()
                self.tooSmall = false
                return
            end
        end
    end
    
    -- Fallback to smallest scale
    pcall(function()
        self.monitor.setTextScale(0.5)
        local w, h = self.monitor.getSize()
        self.width, self.height = w, h
        self.tooSmall = self.width < self.MIN_WIDTH or self.height < self.MIN_HEIGHT
        self:determineLayout()
    end)
end

function Monitor:determineLayout()
    if self.width >= self.LARGE_WIDTH and self.height >= self.LARGE_HEIGHT then
        self.layout = "large"
    elseif self.width >= self.MEDIUM_WIDTH and self.height >= self.MEDIUM_HEIGHT then
        self.layout = "medium"
    else
        self.layout = "small"
    end
end

function Monitor:hasMonitor()
    return self.monitor ~= nil and not self.tooSmall
end

function Monitor:setScale(scale)
    if self.monitor then
        self.scale = scale
        pcall(function()
            self.monitor.setTextScale(scale)
            local w, h = self.monitor.getSize()
            self.width, self.height = w, h
            self:determineLayout()
        end)
    end
end

function Monitor:clear()
    if not self.monitor then return end
    pcall(function()
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.clear()
        self.monitor.setCursorPos(1, 1)
    end)
end

function Monitor:setColors(fg, bg)
    if not self.monitor then return end
    pcall(function()
        if fg then self.monitor.setTextColor(fg) end
        if bg then self.monitor.setBackgroundColor(bg) end
    end)
end

function Monitor:write(x, y, text, fg, bg)
    if not self.monitor then return end
    if x < 1 or y < 1 or x > self.width or y > self.height then return end
    pcall(function()
        self.monitor.setCursorPos(x, y)
        if fg then self.monitor.setTextColor(fg) end
        if bg then self.monitor.setBackgroundColor(bg) end
        self.monitor.write(text)
    end)
end

function Monitor:fillLine(y, color)
    if not self.monitor then return end
    pcall(function()
        self.monitor.setCursorPos(1, y)
        self.monitor.setBackgroundColor(color or colors.black)
        self.monitor.write(string.rep(" ", self.width))
    end)
end

function Monitor:drawProgressBar(x, y, width, percent, color, showPercent)
    if not self.monitor then return end
    
    pcall(function()
        percent = math.max(0, math.min(100, percent))
        local filled = math.floor((width * percent) / 100)
        
        self.monitor.setCursorPos(x, y)
        self.monitor.setBackgroundColor(color or colors.green)
        self.monitor.write(string.rep(" ", filled))
        self.monitor.setBackgroundColor(colors.gray)
        self.monitor.write(string.rep(" ", width - filled))
        self.monitor.setBackgroundColor(colors.black)
        
        if showPercent then
            local pctText = tostring(percent) .. "%"
            local pctX = x + math.floor((width - #pctText) / 2)
            self.monitor.setCursorPos(pctX, y)
            self.monitor.setTextColor(colors.white)
            self.monitor.setBackgroundColor(percent > 50 and color or colors.gray)
            self.monitor.write(pctText)
            self.monitor.setBackgroundColor(colors.black)
        end
    end)
end

function Monitor:drawBox(x, y, w, h, title, borderColor, fillColor)
    if not self.monitor then return end
    
    pcall(function()
        borderColor = borderColor or colors.gray
        fillColor = fillColor or colors.black
        
        -- Fill background
        self.monitor.setBackgroundColor(fillColor)
        for i = y, y + h - 1 do
            self.monitor.setCursorPos(x, i)
            self.monitor.write(string.rep(" ", w))
        end
        
        -- Draw border
        self.monitor.setTextColor(borderColor)
        self.monitor.setBackgroundColor(fillColor)
        
        -- Top and bottom
        self.monitor.setCursorPos(x, y)
        self.monitor.write("+" .. string.rep("-", w - 2) .. "+")
        self.monitor.setCursorPos(x, y + h - 1)
        self.monitor.write("+" .. string.rep("-", w - 2) .. "+")
        
        -- Sides
        for i = y + 1, y + h - 2 do
            self.monitor.setCursorPos(x, i)
            self.monitor.write("|")
            self.monitor.setCursorPos(x + w - 1, i)
            self.monitor.write("|")
        end
        
        -- Title
        if title then
            local titleX = x + math.floor((w - #title - 2) / 2)
            self.monitor.setCursorPos(titleX, y)
            self.monitor.setTextColor(colors.white)
            self.monitor.write(" " .. title .. " ")
        end
        
        self.monitor.setBackgroundColor(colors.black)
    end)
end

function Monitor:drawHeader()
    if not self.monitor then return end
    
    self:fillLine(1, colors.blue)
    local title = "RS Manager"
    if self.layout == "large" then
        title = "=[ RS Manager - Storage System ]="
    elseif self.layout == "medium" then
        title = "[ RS Manager ]"
    end
    local titleX = math.floor((self.width - #title) / 2) + 1
    self:write(titleX, 1, title, colors.white, colors.blue)
    
    pcall(function()
        self.monitor.setBackgroundColor(colors.black)
    end)
end

function Monitor:update()
    if not self.monitor then return end
    
    -- Refresh size in case monitor changed
    local ok, newW, newH = pcall(function()
        return self.monitor.getSize()
    end)
    if not ok then return end
    
    local sizeChanged = (newW ~= self.width or newH ~= self.height)
    self.width, self.height = newW, newH
    self:determineLayout()
    
    if self.tooSmall then
        self:drawTooSmallMessage()
        return
    end
    
    -- Only do full clear on first draw or size change
    if not self.initialized or sizeChanged then
        self:clear()
        self.initialized = true
        self.needsFullRedraw = true
    end
    
    -- Draw header once
    if self.needsFullRedraw then
        self:drawHeader()
        self.needsFullRedraw = false
    end
    
    if self.layout == "large" then
        self:drawLargeLayoutDynamic()
    elseif self.layout == "medium" then
        self:drawMediumLayoutDynamic()
    else
        self:drawSmallLayoutDynamic()
    end
    
    -- Timestamp - overwrite in place
    local timeStr = os.date("%H:%M:%S")
    self:writePadded(self.width - #timeStr, self.height, timeStr, #timeStr, colors.gray)
end

-- Write text and pad with spaces to clear old content
function Monitor:writePadded(x, y, text, minWidth, fg, bg)
    if not self.monitor then return end
    if x < 1 or y < 1 or x > self.width or y > self.height then return end
    
    pcall(function()
        self.monitor.setCursorPos(x, y)
        if fg then self.monitor.setTextColor(fg) end
        if bg then self.monitor.setBackgroundColor(bg) else self.monitor.setBackgroundColor(colors.black) end
        
        local padded = text .. string.rep(" ", math.max(0, minWidth - #text))
        self.monitor.write(padded)
    end)
end

-- Clear a specific line
function Monitor:clearLine(y)
    if not self.monitor then return end
    pcall(function()
        self.monitor.setCursorPos(1, y)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write(string.rep(" ", self.width))
    end)
end

function Monitor:drawTooSmallMessage()
    self:clear()
    local msg1 = "Monitor"
    local msg2 = "Too Small"
    local msg3 = "Min: 2x2"
    self:write(math.floor((self.width - #msg1) / 2) + 1, math.floor(self.height / 2) - 1, msg1, colors.red)
    self:write(math.floor((self.width - #msg2) / 2) + 1, math.floor(self.height / 2), msg2, colors.red)
    self:write(math.floor((self.width - #msg3) / 2) + 1, math.floor(self.height / 2) + 1, msg3, colors.gray)
end

function Monitor:drawSmallLayout()
    local y = 3
    
    -- Energy
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    local energyColor = self:getEnergyColor(energyPercent)
    
    self:write(2, y, "Energy:", colors.yellow)
    y = y + 1
    self:drawProgressBar(2, y, self.width - 4, energyPercent, energyColor, true)
    y = y + 2
    
    -- Items
    local items, totalItems = self:getItemData()
    self:write(2, y, "Items: " .. Utils.formatNumber(totalItems), colors.cyan)
    y = y + 1
    self:write(2, y, "Types: " .. #items, colors.cyan)
    y = y + 2
    
    -- Stock status
    if self.stockKeeper then
        local status = self.stockKeeper:getStatus()
        self:write(2, y, "Stock:", colors.orange)
        if status.enabled then
            self:write(9, y, status.satisfied .. "/" .. status.total, colors.green)
        else
            self:write(9, y, "OFF", colors.red)
        end
        y = y + 2
        
        -- Low stock (limited)
        local lowStock = self.stockKeeper:getLowStock()
        local maxShow = math.min(3, #lowStock, self.height - y - 1)
        for i = 1, maxShow do
            local item = lowStock[i]
            self:write(2, y, Utils.truncate(item.displayName, self.width - 2), colors.orange)
            y = y + 1
        end
    end
end

function Monitor:drawMediumLayout()
    local y = 3
    local halfW = math.floor(self.width / 2)
    
    -- === LEFT COLUMN: System Status ===
    self:write(2, y, "=== System ===", colors.yellow)
    y = y + 1
    
    -- Energy
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    local energyColor = self:getEnergyColor(energyPercent)
    
    self:write(2, y, "Energy:", colors.white)
    y = y + 1
    self:drawProgressBar(2, y, halfW - 4, energyPercent, energyColor, true)
    y = y + 2
    
    -- Storage
    local items, totalItems = self:getItemData()
    self:write(2, y, "Storage:", colors.cyan)
    y = y + 1
    self:write(2, y, " Items: " .. Utils.formatNumber(totalItems), colors.white)
    y = y + 1
    self:write(2, y, " Types: " .. #items, colors.white)
    y = y + 2
    
    -- Crafting
    local tasks = self.bridge:getCraftingTasks() or {}
    self:write(2, y, "Crafting: " .. #tasks .. " jobs", colors.purple)
    y = y + 1
    
    local maxTasks = math.min(4, #tasks)
    for i = 1, maxTasks do
        local task = tasks[i]
        local name = Utils.truncate(task.name or "Unknown", halfW - 6)
        self:write(3, y, name, colors.lightGray)
        y = y + 1
    end
    
    -- === RIGHT COLUMN: Stock Keeper ===
    local ry = 3
    self:write(halfW + 2, ry, "=== Stock ===", colors.orange)
    ry = ry + 1
    
    if self.stockKeeper then
        local status = self.stockKeeper:getStatus()
        
        if status.enabled then
            self:write(halfW + 2, ry, "Status: ", colors.white)
            self:write(halfW + 10, ry, "ACTIVE", colors.green)
        else
            self:write(halfW + 2, ry, "Status: ", colors.white)
            self:write(halfW + 10, ry, "DISABLED", colors.red)
        end
        ry = ry + 1
        
        self:write(halfW + 2, ry, "OK: " .. status.satisfied, colors.green)
        self:write(halfW + 12, ry, "Low: " .. status.low, colors.orange)
        ry = ry + 1
        self:write(halfW + 2, ry, "Critical: " .. status.critical, colors.red)
        ry = ry + 2
        
        -- Low stock list
        local lowStock = self.stockKeeper:getLowStock()
        if #lowStock > 0 then
            self:write(halfW + 2, ry, "Low Stock:", colors.red)
            ry = ry + 1
            
            local maxShow = math.min(8, #lowStock, self.height - ry - 1)
            for i = 1, maxShow do
                local item = lowStock[i]
                local name = Utils.truncate(item.displayName, halfW - 12)
                self:write(halfW + 2, ry, name, colors.orange)
                local count = item.current .. "/" .. item.target
                self:write(self.width - #count - 1, ry, count, colors.gray)
                ry = ry + 1
            end
        end
    end
end

function Monitor:drawLargeLayout()
    local colWidth = math.floor(self.width / 3)
    
    -- === COLUMN 1: System Status ===
    self:drawBox(1, 2, colWidth, self.height - 2, "System", colors.blue)
    local y = 4
    
    -- Energy with big bar
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    local energyColor = self:getEnergyColor(energyPercent)
    
    self:write(3, y, "Energy Storage", colors.yellow)
    y = y + 1
    self:drawProgressBar(3, y, colWidth - 6, energyPercent, energyColor, true)
    y = y + 1
    self:write(3, y, Utils.formatNumber(energy) .. " / " .. Utils.formatNumber(maxEnergy) .. " FE", colors.gray)
    y = y + 2
    
    -- Energy usage
    local usage = self.bridge:getEnergyUsage()
    self:write(3, y, "Usage: " .. Utils.formatNumber(usage) .. " FE/t", colors.white)
    y = y + 2
    
    -- Storage stats
    local items, totalItems = self:getItemData()
    self:write(3, y, "Storage", colors.cyan)
    y = y + 1
    self:write(3, y, "Total Items: " .. Utils.formatNumber(totalItems), colors.white)
    y = y + 1
    self:write(3, y, "Unique Types: " .. #items, colors.white)
    y = y + 2
    
    -- Fluids
    local fluids = self.bridge:listFluids() or {}
    self:write(3, y, "Fluids: " .. #fluids .. " types", colors.lightBlue)
    y = y + 1
    local maxFluids = math.min(4, #fluids)
    for i = 1, maxFluids do
        local fluid = fluids[i]
        if fluid then
            -- Data is already normalized by rsbridge
            local name = Utils.truncate(fluid.displayName or fluid.name or "Unknown", colWidth - 12)
            self:write(4, y, name .. " " .. Utils.formatNumber(fluid.amount or 0) .. "mB", colors.gray)
            y = y + 1
        end
    end
    
    -- === COLUMN 2: Stock Keeper ===
    self:drawBox(colWidth + 1, 2, colWidth, self.height - 2, "Stock Keeper", colors.orange)
    y = 4
    
    if self.stockKeeper then
        local status = self.stockKeeper:getStatus()
        
        -- Status
        self:write(colWidth + 3, y, "Status: ", colors.white)
        if status.enabled then
            self:write(colWidth + 11, y, "ACTIVE", colors.green)
        else
            self:write(colWidth + 11, y, "DISABLED", colors.red)
        end
        y = y + 2
        
        -- Stats
        self:write(colWidth + 3, y, "Satisfied: " .. status.satisfied, colors.green)
        y = y + 1
        self:write(colWidth + 3, y, "Low: " .. status.low, colors.orange)
        y = y + 1
        self:write(colWidth + 3, y, "Critical: " .. status.critical, colors.red)
        y = y + 2
        
        -- Low stock list with progress bars
        local lowStock = self.stockKeeper:getLowStock()
        if #lowStock > 0 then
            self:write(colWidth + 3, y, "--- Low Stock ---", colors.red)
            y = y + 1
            
            local maxShow = math.min(10, #lowStock, self.height - y - 3)
            for i = 1, maxShow do
                local item = lowStock[i]
                local name = Utils.truncate(item.displayName, colWidth - 6)
                self:write(colWidth + 3, y, name, colors.orange)
                y = y + 1
                
                local pct = math.floor((item.current / item.target) * 100)
                local barW = colWidth - 14
                self:drawProgressBar(colWidth + 3, y, barW, pct, colors.orange)
                self:write(colWidth + 3 + barW + 1, y, item.current .. "/" .. item.target, colors.gray)
                y = y + 1
            end
        else
            self:write(colWidth + 3, y, "All items stocked!", colors.green)
        end
    end
    
    -- === COLUMN 3: Crafting ===
    self:drawBox(colWidth * 2 + 1, 2, self.width - colWidth * 2, self.height - 2, "Crafting", colors.purple)
    y = 4
    
    local tasks = self.bridge:getCraftingTasks() or {}
    self:write(colWidth * 2 + 3, y, "Active Jobs: " .. #tasks, colors.white)
    y = y + 2
    
    if #tasks > 0 then
        local maxTasks = math.min(12, #tasks, self.height - y - 3)
        for i = 1, maxTasks do
            local task = tasks[i]
            local name = Utils.truncate(task.name or "Unknown", colWidth - 6)
            self:write(colWidth * 2 + 3, y, name, colors.lightGray)
            y = y + 1
            
            if task.amount then
                self:write(colWidth * 2 + 4, y, "x" .. Utils.formatNumber(task.amount), colors.gray)
            end
            if task.progress then
                local pct = math.floor(task.progress * 100)
                self:write(colWidth * 2 + 14, y, pct .. "%", colors.green)
            end
            y = y + 1
        end
    else
        self:write(colWidth * 2 + 3, y, "No active crafts", colors.gray)
    end
end

-- Helper methods
function Monitor:getEnergyData()
    local energy = self.bridge:getEnergyStorage() or 0
    local maxEnergy = self.bridge:getMaxEnergyStorage() or 1
    local percent = maxEnergy > 0 and math.floor((energy / maxEnergy) * 100) or 0
    return energy, maxEnergy, percent
end

function Monitor:getEnergyColor(percent)
    if percent < 25 then return colors.red
    elseif percent < 50 then return colors.orange
    else return colors.green end
end
function Monitor:getItemData()
    local items = self.bridge:listItems() or {}
    local total = 0
    for _, item in ipairs(items) do
        -- Use dynamic field detection for item amounts
        local amount = self.bridge:getItemAmountField(item)
        total = total + amount
    end
    return items, total
end


function Monitor:showAlert(message, color)
    if not self.monitor then return end
    
    pcall(function()
        local oldBg = self.monitor.getBackgroundColor()
        
        self.monitor.setBackgroundColor(color or colors.red)
        self.monitor.setTextColor(colors.white)
        
        local y = math.floor(self.height / 2)
        self.monitor.setCursorPos(1, y)
        self.monitor.clearLine()
        
        local x = math.floor((self.width - #message) / 2) + 1
        self.monitor.setCursorPos(x, y)
        self.monitor.write(message)
        
        self.monitor.setBackgroundColor(oldBg)
    end)
end

function Monitor:drawItemList(items, startY, maxItems)
    if not self.monitor then return end
    
    local y = startY
    local count = 0
    
    for _, item in ipairs(items) do
        if count >= maxItems then break end
        
        local name = Utils.truncate(item.displayName or item.name, self.width - 12)
        self:write(2, y, name, colors.cyan)
        self:write(self.width - 8, y, Utils.formatNumber(item.amount or item.count or 0), colors.white)
        
        y = y + 1
        count = count + 1
    end
    
    return y
end

function Monitor:drawCraftingList(tasks, startY, maxItems)
    if not self.monitor then return end
    
    local y = startY
    local count = 0
    
    for _, task in ipairs(tasks) do
        if count >= maxItems then break end
        
        local name = Utils.truncate(task.name or "Unknown", self.width - 12)
        self:write(2, y, name, colors.purple)
        
        if task.progress then
            local pct = math.floor(task.progress * 100)
            self:write(self.width - 4, y, pct .. "%", colors.green)
        else
            self:write(self.width - 8, y, Utils.formatNumber(task.amount or 0), colors.white)
        end
        
        y = y + 1
        count = count + 1
    end
    
    return y
end

-- ============================================================
-- DYNAMIC LAYOUTS - No flickering, show only active sections
-- ============================================================

function Monitor:drawSmallLayoutDynamic()
    local y = 3
    local lineWidth = self.width - 2
    
    -- Energy (only show if low)
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    local energyColor = self:getEnergyColor(energyPercent)
    
    if energyPercent < 25 then
        self:writePadded(2, y, "Energy: " .. energyPercent .. "% LOW!", lineWidth, colors.red)
        y = y + 1
        self:drawProgressBar(2, y, self.width - 4, energyPercent, energyColor, false)
        y = y + 2
    end
    
    -- Items count and storage info
    local items, totalItems = self:getItemData()
    local itemTypes = #items
    self:writePadded(2, y, "Items: " .. Utils.formatNumber(totalItems), lineWidth, colors.cyan)
    y = y + 1
    self:writePadded(2, y, "Types: " .. itemTypes, lineWidth, colors.white)
    y = y + 2
    
    -- Dynamic sections based on what's active
    local hasStock = self.stockKeeper and self.stockKeeper:getActiveCount() > 0
    local hasMonitor = self.monitoredItems and #self.monitoredItems > 0
    local tasks = self.bridge:getCraftingTasks() or {}
    local hasCrafting = #tasks > 0
    
    -- Stock Keeper (if has items)
    if hasStock then
        local status = self.stockKeeper:getStatus()
        local allItems = self.stockKeeper:getItems()
        self:writePadded(2, y, "=== Stock Keeper ===", lineWidth, colors.orange)
        y = y + 1
        self:writePadded(2, y, "OK:" .. status.satisfied .. " Low:" .. status.low .. " Crit:" .. status.critical, lineWidth, colors.white)
        y = y + 2
        
        -- Show all stock keeper items, not just low stock
        local maxShow = math.min(6, #allItems, self.height - y - 2)
        for i = 1, maxShow do
            local item = allItems[i]
            if item then
                local current = self.bridge:getItemAmount(item.name) or 0
                local target = item.amount or 0
                local name = Utils.truncate(item.displayName or item.name or "?", lineWidth - 12)
                local statusChar = current >= target and "+" or (current >= target * 0.5 and "~" or "!")
                local statusColor = current >= target and colors.green or (current >= target * 0.5 and colors.orange or colors.red)
                self:writePadded(2, y, statusChar .. " " .. name .. " " .. current .. "/" .. target, lineWidth, statusColor)
                y = y + 1
            end
        end
        y = y + 1
    end
    
    -- Item Monitor (if has items)
    if hasMonitor and y < self.height - 2 then
        self:writePadded(2, y, "=== Item Monitor ===", lineWidth, colors.lightBlue)
        y = y + 1
        
        local maxShow = math.min(4, #self.monitoredItems, self.height - y - 1)
        for i = 1, maxShow do
            local item = self.monitoredItems[i]
            if item then
                local current = self.bridge:getItemAmount(item.name) or 0
                local threshold = item.threshold or 0
                local name = Utils.truncate(item.displayName or item.name or "?", lineWidth - 12)
                local statusChar = current < threshold and "!" or " "
                local statusColor = current < threshold and colors.red or colors.green
                self:writePadded(2, y, statusChar .. " " .. name .. " " .. current, lineWidth, statusColor)
                y = y + 1
            end
        end
        y = y + 1
    end
    
    -- Clear remaining lines
    while y < self.height do
        self:clearLine(y)
        y = y + 1
    end
end

function Monitor:drawMediumLayoutDynamic()
    local halfW = math.floor(self.width / 2)
    local colWidth = halfW - 2
    
    -- Determine what sections to show
    local hasStock = self.stockKeeper and self.stockKeeper:getActiveCount() > 0
    local hasMonitor = self.monitoredItems and #self.monitoredItems > 0
    local tasks = self.bridge:getCraftingTasks() or {}
    local hasCrafting = #tasks > 0
    
    -- === LEFT COLUMN ===
    local y = 3
    
    -- Energy (only show if low)
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    local energyColor = self:getEnergyColor(energyPercent)
    
    if energyPercent < 25 then
        self:writePadded(2, y, "Energy: " .. energyPercent .. "% LOW!", colWidth, colors.red)
        y = y + 1
        self:drawProgressBar(2, y, halfW - 4, energyPercent, energyColor, true)
        y = y + 2
    end
    
    -- Storage
    local items, totalItems = self:getItemData()
    local itemTypes = #items
    self:writePadded(2, y, "Items: " .. Utils.formatNumber(totalItems), colWidth, colors.cyan)
    y = y + 1
    self:writePadded(2, y, "Types: " .. itemTypes, colWidth, colors.white)
    y = y + 2
    
    -- Crafting (if active)
    if hasCrafting then
        self:writePadded(2, y, "Crafting: " .. #tasks, colWidth, colors.purple)
        y = y + 1
        local maxTasks = math.min(3, #tasks, self.height - y - 1)
        for i = 1, maxTasks do
            local task = tasks[i]
            if task then
                local name = Utils.truncate(task.displayName or task.name or "?", colWidth - 2)
                self:writePadded(3, y, name, colWidth - 1, colors.lightGray)
                y = y + 1
            end
        end
    end
    
    -- Clear rest of left column
    while y < self.height do
        self:writePadded(2, y, "", colWidth, colors.black)
        y = y + 1
    end
    
    -- === RIGHT COLUMN ===
    local ry = 3
    
    -- Stock Keeper section
    if hasStock then
        local status = self.stockKeeper:getStatus()
        self:writePadded(halfW + 2, ry, "Stock Keeper", colWidth, colors.orange)
        ry = ry + 1
        
        if status.enabled then
            self:writePadded(halfW + 2, ry, "OK:" .. status.satisfied .. " Low:" .. status.low .. " Crit:" .. status.critical, colWidth, colors.white)
        else
            self:writePadded(halfW + 2, ry, "DISABLED", colWidth, colors.red)
        end
        ry = ry + 2
        
        local lowStock = self.stockKeeper:getLowStock()
        local maxShow = math.min(4, #lowStock)
        for i = 1, maxShow do
            local item = lowStock[i]
            if item then
                local name = Utils.truncate(item.displayName or item.name or "?", colWidth - 10)
                local status_char = item.patternStatus == "no_pattern" and "X" or "!"
                self:writePadded(halfW + 2, ry, status_char .. " " .. name, colWidth, item.patternStatus == "no_pattern" and colors.magenta or colors.red)
                ry = ry + 1
            end
        end
        ry = ry + 1
    end
    
    -- Item Monitor section
    if hasMonitor and ry < self.height - 2 then
        self:writePadded(halfW + 2, ry, "Item Monitor", colWidth, colors.lightBlue)
        ry = ry + 1
        
        local alerts = self:getMonitorAlerts()
        local maxShow = math.min(4, #self.monitoredItems, self.height - ry - 1)
        
        for i = 1, maxShow do
            local item = self.monitoredItems[i]
            if item then
                local current = self.bridge:getItemAmount(item.name) or 0
                local threshold = item.threshold or 0
                local name = Utils.truncate(item.displayName or item.name or "?", colWidth - 12)
                local color = current < threshold and colors.red or colors.green
                local status_char = current < threshold and "!" or " "
                self:writePadded(halfW + 2, ry, status_char .. " " .. name .. " " .. Utils.formatNumber(current), colWidth, color)
                ry = ry + 1
            end
        end
    end
    
    -- Clear rest of right column
    while ry < self.height do
        self:writePadded(halfW + 2, ry, "", colWidth, colors.black)
        ry = ry + 1
    end
end

function Monitor:drawLargeLayoutDynamic()
    -- For large monitors, use 3 columns
    local colWidth = math.floor(self.width / 3) - 1
    
    local hasStock = self.stockKeeper and self.stockKeeper:getActiveCount() > 0
    local hasMonitor = self.monitoredItems and #self.monitoredItems > 0
    local tasks = self.bridge:getCraftingTasks() or {}
    local hasCrafting = #tasks > 0
    
    -- === COLUMN 1: System ===
    local y = 3
    self:writePadded(2, y, "=== System ===", colWidth, colors.yellow)
    y = y + 1
    
    -- Energy (only show if low)
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    local energyColor = self:getEnergyColor(energyPercent)
    
    if energyPercent < 25 then
        self:writePadded(2, y, "Energy: " .. energyPercent .. "% LOW!", colWidth, colors.red)
        y = y + 1
        self:drawProgressBar(2, y, colWidth - 2, energyPercent, energyColor, true)
        y = y + 2
    end
    
    local items, totalItems = self:getItemData()
    local itemTypes = #items
    self:writePadded(2, y, "Items: " .. Utils.formatNumber(totalItems), colWidth, colors.cyan)
    y = y + 1
    self:writePadded(2, y, "Types: " .. itemTypes, colWidth, colors.white)
    y = y + 2
    
    -- Fluids
    local fluids = self.bridge:listFluids() or {}
    self:writePadded(2, y, "Fluids: " .. #fluids .. " types", colWidth, colors.lightBlue)
    y = y + 1
    local maxFluids = math.min(3, #fluids)
    for i = 1, maxFluids do
        local fluid = fluids[i]
        if fluid then
            local name = Utils.truncate(fluid.displayName or fluid.name or "?", colWidth - 8)
            self:writePadded(3, y, name .. " " .. Utils.formatNumber(fluid.amount or 0), colWidth - 1, colors.gray)
            y = y + 1
        end
    end
    
    -- Crafting
    if hasCrafting then
        y = y + 1
        self:writePadded(2, y, "Crafting: " .. #tasks, colWidth, colors.purple)
        y = y + 1
        local maxTasks = math.min(4, #tasks)
        for i = 1, maxTasks do
            local task = tasks[i]
            if task then
                local name = Utils.truncate(task.displayName or task.name or "?", colWidth - 2)
                self:writePadded(3, y, name, colWidth - 1, colors.lightGray)
                y = y + 1
            end
        end
    end
    
    while y < self.height do
        self:writePadded(2, y, "", colWidth, colors.black)
        y = y + 1
    end
    
    -- === COLUMN 2: Stock Keeper ===
    local col2X = colWidth + 3
    y = 3
    
    if hasStock then
        local status = self.stockKeeper:getStatus()
        local allItems = self.stockKeeper:getItems()
        self:writePadded(col2X, y, "=== Stock Keeper ===", colWidth, colors.orange)
        y = y + 1
        
        if status.enabled then
            self:writePadded(col2X, y, "OK:" .. status.satisfied .. " Low:" .. status.low .. " Crit:" .. status.critical, colWidth, colors.white)
        else
            self:writePadded(col2X, y, "DISABLED", colWidth, colors.red)
        end
        y = y + 2
        
        -- Auto-scroll through all items if enabled
        local maxShow = self.height - y - 1
        local totalItems = #allItems
        
        if self.config.monitorAutoScroll and totalItems > maxShow then
            -- Update scroll position
            local now = os.epoch("utc") / 1000
            local scrollSpeed = self.config.monitorScrollSpeed or 3
            if now - self.lastScrollTime >= scrollSpeed then
                self.scrollOffset = (self.scrollOffset + 1) % math.max(1, totalItems - maxShow + 1)
                self.lastScrollTime = now
            end
            
            -- Display scrolled items
            for i = 1, maxShow do
                local idx = self.scrollOffset + i
                if idx <= totalItems then
                    local item = allItems[idx]
                    if item then
                        local current = self.bridge:getItemAmount(item.name) or 0
                        local target = item.amount or 1
                        local name = Utils.truncate(item.displayName or item.name or "?", colWidth - 15)
                        
                        -- Clear stale craft status if item is now stocked
                        if current >= target and (item.lastCraftStatus == "no_materials" or item.lastCraftStatus == "crafting") then
                            item.lastCraftStatus = nil
                        end
                        
                        -- Status indicator - prioritize actual stock level
                        local statusChar = "+"
                        local statusColor = colors.green
                        if item.patternStatus == "no_pattern" then
                            statusChar = "X"
                            statusColor = colors.magenta
                        elseif current < target and item.lastCraftStatus == "no_materials" then
                            statusChar = "M"
                            statusColor = colors.yellow
                        elseif current >= target then
                            statusChar = "+"
                            statusColor = colors.green
                        elseif current >= target * 0.5 then
                            statusChar = "~"
                            statusColor = colors.orange
                        else
                            statusChar = "!"
                            statusColor = colors.red
                        end
                        
                        local amtStr = Utils.formatNumber(current) .. "/" .. Utils.formatNumber(target)
                        self:writePadded(col2X, y, statusChar .. " " .. name, colWidth - #amtStr - 1, statusColor)
                        self:writePadded(col2X + colWidth - #amtStr - 1, y, amtStr, #amtStr + 1, colors.white)
                        y = y + 1
                    end
                end
            end
        else
            -- No scroll, show first items
            for i = 1, math.min(maxShow, totalItems) do
                local item = allItems[i]
                if item then
                    local current = self.bridge:getItemAmount(item.name) or 0
                    local target = item.amount or 1
                    local name = Utils.truncate(item.displayName or item.name or "?", colWidth - 15)
                    
                    -- Clear stale craft status if item is now stocked
                    if current >= target and (item.lastCraftStatus == "no_materials" or item.lastCraftStatus == "crafting") then
                        item.lastCraftStatus = nil
                    end
                    
                    -- Status indicator - prioritize actual stock level
                    local statusChar = "+"
                    local statusColor = colors.green
                    if item.patternStatus == "no_pattern" then
                        statusChar = "X"
                        statusColor = colors.magenta
                    elseif current < target and item.lastCraftStatus == "no_materials" then
                        statusChar = "M"
                        statusColor = colors.yellow
                    elseif current >= target then
                        statusChar = "+"
                        statusColor = colors.green
                    elseif current >= target * 0.5 then
                        statusChar = "~"
                        statusColor = colors.orange
                    else
                        statusChar = "!"
                        statusColor = colors.red
                    end
                    
                    local amtStr = Utils.formatNumber(current) .. "/" .. Utils.formatNumber(target)
                    self:writePadded(col2X, y, statusChar .. " " .. name, colWidth - #amtStr - 1, statusColor)
                    self:writePadded(col2X + colWidth - #amtStr - 1, y, amtStr, #amtStr + 1, colors.white)
                    y = y + 1
                end
            end
        end
    end
    
    -- Clear column 2 (whether Stock Keeper shown or not)
    while y < self.height do
        self:writePadded(col2X, y, "", colWidth, colors.black)
        y = y + 1
    end
    
    -- === COLUMN 3: Item Monitor ===
    local col3X = colWidth * 2 + 4
    y = 3
    
    if hasMonitor then
        self:writePadded(col3X, y, "=== Item Monitor ===", colWidth, colors.lightBlue)
        y = y + 1
        
        local alerts = self:getMonitorAlerts()
        self:writePadded(col3X, y, "Tracking: " .. #self.monitoredItems .. " | Low: " .. #alerts, colWidth, #alerts > 0 and colors.yellow or colors.green)
        y = y + 2
        
        local maxShow = math.min(self.height - y - 1, #self.monitoredItems)
        for i = 1, maxShow do
            local item = self.monitoredItems[i]
            if item then
                local current = self.bridge:getItemAmount(item.name) or 0
                local threshold = item.threshold or 0
                local name = Utils.truncate(item.displayName or item.name or "?", colWidth - 10)
                local amtStr = Utils.formatNumber(current)
                local color = current < threshold and colors.red or colors.green
                self:writePadded(col3X, y, name, colWidth - #amtStr - 1, color)
                self:writePadded(col3X + colWidth - #amtStr - 1, y, amtStr, #amtStr + 1, colors.white)
                y = y + 1
            end
        end
    end
    
    -- Clear column 3 (whether Item Monitor shown or not)
    while y < self.height do
        self:writePadded(col3X, y, "", colWidth, colors.black)
        y = y + 1
    end
end

-- Get items from monitor that are below threshold
function Monitor:getMonitorAlerts()
    local alerts = {}
    if not self.monitoredItems then return alerts end
    
    for _, item in ipairs(self.monitoredItems) do
        if item and item.name then
            local current = self.bridge:getItemAmount(item.name) or 0
            local threshold = item.threshold or 0
            if current < threshold then
                table.insert(alerts, {
                    name = item.name,
                    displayName = item.displayName or item.name,
                    current = current,
                    threshold = threshold
                })
            end
        end
    end
    
    return alerts
end

return Monitor
