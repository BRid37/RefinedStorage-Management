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

function Monitor.new(bridge, stockKeeper)
    local self = setmetatable({}, Monitor)
    self.bridge = bridge
    self.stockKeeper = stockKeeper
    self.monitor = nil
    self.scale = 0.5  -- Default scale for larger text
    self.width = 0
    self.height = 0
    self.layout = "small"  -- small, medium, large
    self.tooSmall = false
    
    self:findMonitor()
    return self
end

function Monitor:findMonitor()
    self.monitor = peripheral.find("monitor")
    if self.monitor then
        self:autoScale()
        return true
    end
    return false
end

function Monitor:autoScale()
    if not self.monitor then return end
    
    -- Try different scales to find best fit
    local scales = {0.5, 1, 1.5, 2}
    
    for _, scale in ipairs(scales) do
        self.monitor.setTextScale(scale)
        local w, h = self.monitor.getSize()
        
        if w >= self.MIN_WIDTH and h >= self.MIN_HEIGHT then
            self.scale = scale
            self.width = w
            self.height = h
            self:determineLayout()
            self.tooSmall = false
            return
        end
    end
    
    -- Monitor too small even at smallest scale
    self.monitor.setTextScale(0.5)
    self.width, self.height = self.monitor.getSize()
    self.tooSmall = self.width < self.MIN_WIDTH or self.height < self.MIN_HEIGHT
    self:determineLayout()
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
        self.monitor.setTextScale(scale)
        self.width, self.height = self.monitor.getSize()
        self:determineLayout()
    end
end

function Monitor:clear()
    if not self.monitor then return end
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.clear()
    self.monitor.setCursorPos(1, 1)
end

function Monitor:setColors(fg, bg)
    if not self.monitor then return end
    if fg then self.monitor.setTextColor(fg) end
    if bg then self.monitor.setBackgroundColor(bg) end
end

function Monitor:write(x, y, text, fg, bg)
    if not self.monitor then return end
    if x < 1 or y < 1 or x > self.width or y > self.height then return end
    self.monitor.setCursorPos(x, y)
    if fg then self.monitor.setTextColor(fg) end
    if bg then self.monitor.setBackgroundColor(bg) end
    self.monitor.write(text)
end

function Monitor:fillLine(y, color)
    if not self.monitor then return end
    self.monitor.setCursorPos(1, y)
    self.monitor.setBackgroundColor(color or colors.black)
    self.monitor.write(string.rep(" ", self.width))
end

function Monitor:drawProgressBar(x, y, width, percent, color, showPercent)
    if not self.monitor then return end
    
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
end

function Monitor:drawBox(x, y, w, h, title, borderColor, fillColor)
    if not self.monitor then return end
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
    
    self.monitor.setBackgroundColor(colors.black)
end

function Monitor:update()
    if not self.monitor then return end
    
    -- Refresh size in case monitor changed
    local newW, newH = self.monitor.getSize()
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
        self:drawHeader()
        self.initialized = true
    end
    
    -- Clear content area only (not header) - overwrite with spaces
    for y = 3, self.height - 1 do
        self.monitor.setCursorPos(1, y)
        self.monitor.setBackgroundColor(colors.black)
        self.monitor.write(string.rep(" ", self.width))
    end
    
    if self.layout == "large" then
        self:drawLargeLayout()
    elseif self.layout == "medium" then
        self:drawMediumLayout()
    else
        self:drawSmallLayout()
    end
    
    -- Timestamp
    local timeStr = os.date("%H:%M:%S")
    self:write(self.width - #timeStr, self.height, timeStr, colors.gray)
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
        total = total + (item.amount or item.count or 0)
    end
    return items, total
end

function Monitor:showAlert(message, color)
    if not self.monitor then return end
    
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

return Monitor
