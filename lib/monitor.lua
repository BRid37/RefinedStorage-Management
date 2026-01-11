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
    
    -- Activity tracking for dynamic display
    self.recentChanges = {}     -- {name, displayName, oldAmount, newAmount, time}
    self.recentCrafts = {}      -- {name, displayName, amount, startTime, estimatedEnd}
    self.lastItemCounts = {}    -- Track previous item counts to detect changes
    self.pendingUpdate = false  -- Flag for priority update
    self.lastUpdateTime = 0
    self.fastRefreshUntil = 0   -- Timestamp until which we use fast refresh
    
    self:findMonitor()
    return self
end

-- Update monitored items reference
function Monitor:setMonitoredItems(items)
    self.monitoredItems = items or {}
end

-- Request immediate update (call after user actions like crafting)
function Monitor:requestUpdate()
    self.pendingUpdate = true
end

-- Enable fast refresh mode for a duration (e.g., after starting a craft)
function Monitor:enableFastRefresh(durationSeconds)
    durationSeconds = durationSeconds or 30
    self.fastRefreshUntil = os.epoch("utc") / 1000 + durationSeconds
end

-- Check if we should use fast refresh
function Monitor:shouldFastRefresh()
    return os.epoch("utc") / 1000 < self.fastRefreshUntil
end

-- Get current refresh rate based on state
function Monitor:getRefreshRate()
    if self.pendingUpdate then
        return 0.5  -- Immediate update
    elseif self:shouldFastRefresh() then
        return 1    -- Fast refresh during expected changes
    else
        return self.config.refreshRate or 2  -- Normal rate
    end
end

-- Track a craft request for display
function Monitor:trackCraftRequest(name, displayName, amount)
    -- Add to recent crafts with estimated completion
    local now = os.epoch("utc") / 1000
    table.insert(self.recentCrafts, 1, {
        name = name,
        displayName = displayName or name,
        amount = amount,
        startTime = now,
        -- Rough estimate: 1 second per item, capped at 5 minutes
        estimatedEnd = now + math.min(amount * 1, 300)
    })
    -- Keep only last 10 craft requests
    while #self.recentCrafts > 10 do
        table.remove(self.recentCrafts)
    end
    -- Enable fast refresh to show crafting progress
    self:enableFastRefresh(60)
    self:requestUpdate()
end

-- Track stock changes for activity feed
function Monitor:trackStockChange(name, displayName, oldAmount, newAmount)
    if oldAmount == newAmount then return end
    local now = os.epoch("utc") / 1000
    table.insert(self.recentChanges, 1, {
        name = name,
        displayName = displayName or name,
        oldAmount = oldAmount,
        newAmount = newAmount,
        delta = newAmount - oldAmount,
        time = now
    })
    -- Keep only last 20 changes
    while #self.recentChanges > 20 do
        table.remove(self.recentChanges)
    end
end

-- Get active crafting jobs with ETA
function Monitor:getActiveCraftsWithETA()
    local tasks = self.bridge:getCraftingTasks() or {}
    local now = os.epoch("utc") / 1000
    local result = {}
    
    for _, task in ipairs(tasks) do
        local eta = nil
        -- Try to find matching tracked craft for ETA
        for _, tracked in ipairs(self.recentCrafts) do
            if tracked.name == task.name then
                if tracked.estimatedEnd > now then
                    eta = math.ceil(tracked.estimatedEnd - now)
                end
                break
            end
        end
        table.insert(result, {
            name = task.name,
            displayName = task.displayName or task.name,
            amount = task.amount,
            progress = task.progress,
            eta = eta
        })
    end
    return result
end

-- Detect and track stock changes by comparing current counts to last known counts
function Monitor:detectStockChanges()
    if not self.stockKeeper then return end
    
    local items = self.stockKeeper:getItems() or {}
    local now = os.epoch("utc") / 1000
    
    for _, item in ipairs(items) do
        if item and item.name then
            local current = self.bridge:getItemAmount(item.name) or 0
            local lastCount = self.lastItemCounts[item.name]
            
            -- Track change if count changed significantly
            if lastCount and lastCount ~= current then
                local delta = current - lastCount
                -- Only track meaningful changes (more than 0)
                if math.abs(delta) > 0 then
                    self:trackStockChange(item.name, item.displayName, lastCount, current)
                end
            end
            
            -- Update last known count
            self.lastItemCounts[item.name] = current
        end
    end
end

-- Get recent activity (changes + crafts)
function Monitor:getRecentActivity(maxItems)
    maxItems = maxItems or 5
    local now = os.epoch("utc") / 1000
    local activity = {}
    
    -- Add recent changes (within last 5 minutes)
    for _, change in ipairs(self.recentChanges) do
        if now - change.time < 300 then
            table.insert(activity, {
                type = "change",
                name = change.name,
                displayName = change.displayName,
                delta = change.delta,
                time = change.time,
                age = now - change.time
            })
        end
    end
    
    -- Sort by time (most recent first)
    table.sort(activity, function(a, b) return a.time > b.time end)
    
    -- Limit results
    while #activity > maxItems do
        table.remove(activity)
    end
    
    return activity
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
    
    local now = os.epoch("utc") / 1000
    
    -- Force refresh item data from bridge to get latest counts
    -- Use shorter cache when pending update or fast refresh mode
    if self.bridge then
        local forceRefresh = self.pendingUpdate or self:shouldFastRefresh() or (now - self.lastUpdateTime < 2)
        self.bridge:listItems(forceRefresh)
    end
    
    self.lastUpdateTime = now
    
    -- Track stock changes for activity feed
    self:detectStockChanges()
    
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
        local lowStock = self.stockKeeper:getLowStock(true)
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
        local lowStock = self.stockKeeper:getLowStock(true)
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
        local lowStock = self.stockKeeper:getLowStock(true)
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
    
    -- Active crafting with ETA (priority display)
    local craftsWithETA = self:getActiveCraftsWithETA()
    if #craftsWithETA > 0 then
        self:writePadded(2, y, "=== Crafting ===", lineWidth, colors.purple)
        y = y + 1
        local maxCrafts = math.min(3, #craftsWithETA)
        for i = 1, maxCrafts do
            local craft = craftsWithETA[i]
            local name = Utils.truncate(craft.displayName or craft.name or "?", lineWidth - 14)
            local etaStr = craft.eta and (" ~" .. craft.eta .. "s") or ""
            local progStr = craft.progress and (math.floor(craft.progress * 100) .. "%") or "..."
            self:writePadded(2, y, name .. " " .. progStr .. etaStr, lineWidth, colors.lightGray)
            y = y + 1
        end
        y = y + 1
    end
    
    -- Low stock items only (prioritize critical issues)
    local hasStock = self.stockKeeper and self.stockKeeper:getActiveCount() > 0
    if hasStock then
        local lowStock = self.stockKeeper:getLowStock(true)  -- Force refresh for accurate counts
        local status = self.stockKeeper:getStatus()
        
        if #lowStock > 0 then
            self:writePadded(2, y, "=== Low Stock (" .. #lowStock .. ") ===", lineWidth, colors.orange)
            y = y + 1
            
            local maxShow = math.min(4, #lowStock, self.height - y - 4)
            for i = 1, maxShow do
                local item = lowStock[i]
                if item then
                    local isAlwaysCraft = item.alwaysCraft or (item.target == -1)
                    local statusChar, statusColor
                    
                    if item.patternStatus == "no_pattern" then
                        statusChar = "X"
                        statusColor = colors.magenta
                    elseif isAlwaysCraft then
                        statusChar = "A"
                        statusColor = colors.purple
                    elseif item.lastCraftStatus == "no_materials" then
                        statusChar = "M"
                        statusColor = colors.yellow
                    elseif (item.percent or 0) >= 50 then
                        statusChar = "~"
                        statusColor = colors.orange
                    else
                        statusChar = "!"
                        statusColor = colors.red
                    end
                    
                    -- Line 1: Name with status and amount/percentage
                    local name = Utils.truncate(item.displayName or item.name or "?", lineWidth - 18)
                    local amtStr
                    if isAlwaysCraft then
                        amtStr = "(Auto)"
                    else
                        amtStr = item.current .. "/" .. item.target .. " (" .. (item.percent or 0) .. "%)"
                    end
                    self:writePadded(2, y, statusChar .. " " .. name, lineWidth - #amtStr - 1, statusColor)
                    self:writePadded(lineWidth - #amtStr + 1, y, amtStr, #amtStr + 1, colors.gray)
                    y = y + 1
                    
                    -- Line 2: Missing material or available batches (if space)
                    if y < self.height - 2 then
                        local detailLine = ""
                        local detailColor = colors.gray
                        
                        if item.patternStatus == "no_pattern" then
                            detailLine = "  No pattern"
                            detailColor = colors.magenta
                        elseif item.lastCraftStatus == "no_materials" and item.limitingItem then
                            detailLine = "  Need: " .. Utils.truncate(item.limitingItem.displayName or item.limitingItem.name or "?", lineWidth - 10)
                            detailColor = colors.yellow
                        elseif item.availableBatches and item.availableBatches > 0 then
                            detailLine = "  Avail: " .. item.availableBatches .. " batches"
                            detailColor = colors.cyan
                        end
                        
                        if detailLine ~= "" then
                            self:writePadded(2, y, detailLine, lineWidth, detailColor)
                            y = y + 1
                        end
                    end
                end
            end
        else
            self:writePadded(2, y, "All " .. status.total .. " items stocked!", lineWidth, colors.green)
            y = y + 1
        end
        y = y + 1
    end
    
    -- Recent activity (stock changes)
    local activity = self:getRecentActivity(3)
    if #activity > 0 and y < self.height - 2 then
        self:writePadded(2, y, "=== Recent ===", lineWidth, colors.lightBlue)
        y = y + 1
        for _, act in ipairs(activity) do
            if y >= self.height - 1 then break end
            local name = Utils.truncate(act.displayName or act.name or "?", lineWidth - 10)
            local deltaStr = act.delta > 0 and ("+" .. Utils.formatNumber(act.delta)) or Utils.formatNumber(act.delta)
            local color = act.delta > 0 and colors.green or colors.red
            self:writePadded(2, y, name .. " " .. deltaStr, lineWidth, color)
            y = y + 1
        end
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
    local craftsWithETA = self:getActiveCraftsWithETA()
    local hasCrafting = #craftsWithETA > 0
    
    -- === LEFT COLUMN: Crafting & Stats ===
    local y = 3
    
    -- Active crafting with ETA (priority)
    if hasCrafting then
        self:writePadded(2, y, "=== Crafting ===", colWidth, colors.purple)
        y = y + 1
        local maxTasks = math.min(5, #craftsWithETA)
        for i = 1, maxTasks do
            local craft = craftsWithETA[i]
            local name = Utils.truncate(craft.displayName or craft.name or "?", colWidth - 12)
            local etaStr = craft.eta and (" ~" .. craft.eta .. "s") or ""
            local progStr = craft.progress and (math.floor(craft.progress * 100) .. "%") or "..."
            self:writePadded(2, y, name .. " " .. progStr .. etaStr, colWidth, colors.lightGray)
            y = y + 1
        end
        y = y + 1
    end
    
    -- Recent activity
    local activity = self:getRecentActivity(4)
    if #activity > 0 then
        self:writePadded(2, y, "=== Recent Activity ===", colWidth, colors.lightBlue)
        y = y + 1
        for _, act in ipairs(activity) do
            if y >= self.height - 1 then break end
            local name = Utils.truncate(act.displayName or "?", colWidth - 8)
            local deltaStr = act.delta > 0 and ("+" .. Utils.formatNumber(act.delta)) or Utils.formatNumber(act.delta)
            local color = act.delta > 0 and colors.green or colors.red
            self:writePadded(2, y, name .. " " .. deltaStr, colWidth, color)
            y = y + 1
        end
        y = y + 1
    end
    
    -- Energy (only show if low)
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    if energyPercent < 25 then
        self:writePadded(2, y, "Energy: " .. energyPercent .. "% LOW!", colWidth, colors.red)
        y = y + 1
    end
    
    -- Clear rest of left column
    while y < self.height do
        self:writePadded(2, y, "", colWidth, colors.black)
        y = y + 1
    end
    
    -- === RIGHT COLUMN: Low Stock ===
    local ry = 3
    
    if hasStock then
        local status = self.stockKeeper:getStatus()
        local lowStock = self.stockKeeper:getLowStock(true)
        
        self:writePadded(halfW + 2, ry, "=== Low Stock ===", colWidth, colors.orange)
        ry = ry + 1
        
        if status.enabled then
            self:writePadded(halfW + 2, ry, "OK:" .. status.satisfied .. " Low:" .. status.low .. " Crit:" .. status.critical, colWidth, colors.white)
        else
            self:writePadded(halfW + 2, ry, "DISABLED", colWidth, colors.red)
        end
        ry = ry + 2
        
        if #lowStock > 0 then
            local maxShow = math.floor((self.height - ry - 1) / 2)  -- 2 lines per item
            maxShow = math.min(maxShow, #lowStock)
            for i = 1, maxShow do
                local item = lowStock[i]
                if item then
                    local isAlwaysCraft = item.alwaysCraft or (item.target == -1)
                    local statusChar, statusColor
                    
                    if item.patternStatus == "no_pattern" then
                        statusChar = "X"
                        statusColor = colors.magenta
                    elseif isAlwaysCraft then
                        statusChar = "A"
                        statusColor = colors.purple
                    elseif item.lastCraftStatus == "no_materials" then
                        statusChar = "M"
                        statusColor = colors.yellow
                    elseif (item.percent or 0) >= 50 then
                        statusChar = "~"
                        statusColor = colors.orange
                    else
                        statusChar = "!"
                        statusColor = colors.red
                    end
                    
                    -- Line 1: Name and amount with percentage
                    local name = Utils.truncate(item.displayName or item.name or "?", colWidth - 16)
                    local amtStr
                    if isAlwaysCraft then
                        amtStr = "Auto"
                    else
                        amtStr = item.current .. "/" .. item.target .. " (" .. (item.percent or 0) .. "%)"
                    end
                    self:writePadded(halfW + 2, ry, statusChar .. " " .. name, colWidth - #amtStr - 1, statusColor)
                    self:writePadded(halfW + colWidth - #amtStr, ry, amtStr, #amtStr + 1, isAlwaysCraft and colors.purple or colors.gray)
                    ry = ry + 1
                    
                    -- Line 2: Detail (missing material or batches)
                    local detailStr = ""
                    local detailColor = colors.gray
                    if item.patternStatus == "no_pattern" then
                        detailStr = "  No pattern available"
                        detailColor = colors.magenta
                    elseif item.lastCraftStatus == "no_materials" and item.limitingItem then
                        detailStr = "  Need: " .. Utils.truncate(item.limitingItem.displayName or "?", colWidth - 10)
                        detailColor = colors.yellow
                    elseif item.availableBatches and item.availableBatches > 0 then
                        detailStr = "  Avail: " .. item.availableBatches .. " batches"
                        detailColor = colors.cyan
                    end
                    if detailStr ~= "" then
                        self:writePadded(halfW + 2, ry, detailStr, colWidth, detailColor)
                        ry = ry + 1
                    end
                end
            end
        else
            self:writePadded(halfW + 2, ry, "All items stocked!", colWidth, colors.green)
            ry = ry + 1
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
    local craftsWithETA = self:getActiveCraftsWithETA()
    local hasCrafting = #craftsWithETA > 0
    
    -- === COLUMN 1: Crafting & Activity ===
    local y = 3
    
    -- Active crafting with ETA (priority display)
    if hasCrafting then
        self:writePadded(2, y, "=== Crafting ===", colWidth, colors.purple)
        y = y + 1
        local maxTasks = math.min(6, #craftsWithETA)
        for i = 1, maxTasks do
            local craft = craftsWithETA[i]
            local name = Utils.truncate(craft.displayName or craft.name or "?", colWidth - 14)
            local etaStr = craft.eta and (" ~" .. craft.eta .. "s") or ""
            local progStr = craft.progress and (math.floor(craft.progress * 100) .. "%") or "..."
            self:writePadded(2, y, name .. " " .. progStr .. etaStr, colWidth, colors.lightGray)
            y = y + 1
        end
        y = y + 1
    end
    
    -- Recent activity
    local activity = self:getRecentActivity(6)
    if #activity > 0 then
        self:writePadded(2, y, "=== Recent Activity ===", colWidth, colors.lightBlue)
        y = y + 1
        for _, act in ipairs(activity) do
            if y >= self.height - 2 then break end
            local name = Utils.truncate(act.displayName or "?", colWidth - 10)
            local deltaStr = act.delta > 0 and ("+" .. Utils.formatNumber(act.delta)) or Utils.formatNumber(act.delta)
            local color = act.delta > 0 and colors.green or colors.red
            self:writePadded(2, y, name .. " " .. deltaStr, colWidth, color)
            y = y + 1
        end
        y = y + 1
    end
    
    -- Energy (only show if low)
    local energy, maxEnergy, energyPercent = self:getEnergyData()
    if energyPercent < 25 then
        self:writePadded(2, y, "Energy: " .. energyPercent .. "% LOW!", colWidth, colors.red)
        y = y + 1
    end
    
    while y < self.height do
        self:writePadded(2, y, "", colWidth, colors.black)
        y = y + 1
    end
    
    -- === COLUMN 2: Low Stock ===
    local col2X = colWidth + 3
    y = 3
    
    if hasStock then
        local status = self.stockKeeper:getStatus()
        local lowStock = self.stockKeeper:getLowStock(true)
        
        self:writePadded(col2X, y, "=== Low Stock ===", colWidth, colors.orange)
        y = y + 1
        
        if status.enabled then
            self:writePadded(col2X, y, "OK:" .. status.satisfied .. " Low:" .. status.low .. " Crit:" .. status.critical, colWidth, colors.white)
        else
            self:writePadded(col2X, y, "DISABLED", colWidth, colors.red)
        end
        y = y + 2
        
        if #lowStock > 0 then
            -- Helper to draw a single low stock item (2 lines each)
            local function drawLowStockItem(item, yPos)
                local isAlwaysCraft = item.alwaysCraft or (item.target == -1)
                local statusChar, statusColor
                
                if item.patternStatus == "no_pattern" then
                    statusChar = "X"
                    statusColor = colors.magenta
                elseif isAlwaysCraft then
                    statusChar = "A"
                    statusColor = colors.purple
                elseif item.lastCraftStatus == "no_materials" then
                    statusChar = "M"
                    statusColor = colors.yellow
                elseif (item.percent or 0) >= 50 then
                    statusChar = "~"
                    statusColor = colors.orange
                else
                    statusChar = "!"
                    statusColor = colors.red
                end
                
                -- Line 1: Name and amount with percentage
                local name = Utils.truncate(item.displayName or item.name or "?", colWidth - 18)
                local amtStr
                if isAlwaysCraft then
                    amtStr = "Auto"
                else
                    amtStr = Utils.formatNumber(item.current) .. "/" .. Utils.formatNumber(item.target) .. " (" .. (item.percent or 0) .. "%)"
                end
                self:writePadded(col2X, yPos, statusChar .. " " .. name, colWidth - #amtStr - 1, statusColor)
                self:writePadded(col2X + colWidth - #amtStr - 1, yPos, amtStr, #amtStr + 1, isAlwaysCraft and colors.purple or colors.white)
                
                -- Line 2: Detail info
                local detailStr = ""
                local detailColor = colors.gray
                if item.patternStatus == "no_pattern" then
                    detailStr = "  No pattern"
                    detailColor = colors.magenta
                elseif item.lastCraftStatus == "no_materials" and item.limitingItem then
                    detailStr = "  Need: " .. Utils.truncate(item.limitingItem.displayName or "?", colWidth - 10)
                    detailColor = colors.yellow
                elseif item.availableBatches and item.availableBatches > 0 then
                    detailStr = "  Avail: " .. item.availableBatches .. " batches"
                    detailColor = colors.cyan
                end
                if detailStr ~= "" then
                    self:writePadded(col2X, yPos + 1, detailStr, colWidth, detailColor)
                    return 2
                end
                return 1
            end
            
            -- Auto-scroll through low stock items if many
            local maxShow = math.floor((self.height - y - 1) / 2)  -- 2 lines per item
            local totalLow = #lowStock
            
            if self.config.monitorAutoScroll and totalLow > maxShow then
                local now = os.epoch("utc") / 1000
                local scrollSpeed = self.config.monitorScrollSpeed or 3
                if now - self.lastScrollTime >= scrollSpeed then
                    self.scrollOffset = (self.scrollOffset + 1) % math.max(1, totalLow - maxShow + 1)
                    self.lastScrollTime = now
                end
                
                for i = 1, maxShow do
                    local idx = self.scrollOffset + i
                    if idx <= totalLow then
                        local item = lowStock[idx]
                        if item then
                            local lines = drawLowStockItem(item, y)
                            y = y + lines
                        end
                    end
                end
            else
                for i = 1, math.min(maxShow, totalLow) do
                    local item = lowStock[i]
                    if item then
                        local lines = drawLowStockItem(item, y)
                        y = y + lines
                    end
                end
            end
        else
            self:writePadded(col2X, y, "All " .. status.total .. " items stocked!", colWidth, colors.green)
            y = y + 1
        end
    end
    
    -- Clear column 2
    while y < self.height do
        self:writePadded(col2X, y, "", colWidth, colors.black)
        y = y + 1
    end
    
    -- === COLUMN 3: System Stats ===
    local col3X = colWidth * 2 + 4
    y = 3
    
    self:writePadded(col3X, y, "=== System ===", colWidth, colors.yellow)
    y = y + 1
    
    -- Storage stats
    local items, totalItems = self:getItemData()
    local itemTypes = #items
    self:writePadded(col3X, y, "Items: " .. Utils.formatNumber(totalItems), colWidth, colors.cyan)
    y = y + 1
    self:writePadded(col3X, y, "Types: " .. itemTypes, colWidth, colors.white)
    y = y + 2
    
    -- Fluids
    local fluids = self.bridge:listFluids() or {}
    self:writePadded(col3X, y, "Fluids: " .. #fluids .. " types", colWidth, colors.lightBlue)
    y = y + 1
    local maxFluids = math.min(4, #fluids)
    for i = 1, maxFluids do
        local fluid = fluids[i]
        if fluid then
            local name = Utils.truncate(fluid.displayName or fluid.name or "?", colWidth - 8)
            self:writePadded(col3X + 1, y, name .. " " .. Utils.formatNumber(fluid.amount or 0), colWidth - 1, colors.gray)
            y = y + 1
        end
    end
    
    -- Clear column 3
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
