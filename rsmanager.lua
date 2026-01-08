-- RS Manager - Refined Storage Management System
-- Version 1.0.0
-- For CC:Tweaked 1.116.2+ and Advanced Peripherals 0.7.57b+

-- Determine install directory
local programPath = shell.getRunningProgram()
local BASE_DIR = fs.getDir(programPath)
if BASE_DIR == "" or BASE_DIR == "." then 
    BASE_DIR = "/rsmanager" 
end

-- Load modules using dofile for CC:Tweaked compatibility
local function loadModule(name)
    local path = BASE_DIR .. "/lib/" .. name .. ".lua"
    if fs.exists(path) then
        return dofile(path)
    else
        error("Module not found: " .. path)
    end
end

local Config = loadModule("config")
local RSBridge = loadModule("rsbridge")
local StockKeeper = loadModule("stockkeeper")
local Monitor = loadModule("monitor")
local GUI = loadModule("gui")
local Utils = loadModule("utils")
local Updater = loadModule("updater")

-- Global state
local running = true
local currentView = "main"
local config = nil
local bridge = nil
local stockKeeper = nil
local monitor = nil
local updater = nil

-- Check for updates at startup
local function checkUpdates()
    term.clear()
    term.setCursorPos(1, 1)
    
    Utils.printC("================================", colors.cyan)
    Utils.printC("   RS Manager v" .. Updater.VERSION, colors.cyan)
    Utils.printC("================================", colors.cyan)
    print()
    
    -- Load config first to check autoUpdate setting
    local tempConfig = Config.load(BASE_DIR .. "/config/settings.lua")
    
    if tempConfig.autoUpdate == false then
        Utils.printC("Auto-update disabled, skipping...", colors.gray)
        sleep(0.5)
        return
    end
    
    if not http then
        Utils.printC("HTTP disabled, skipping update check...", colors.gray)
        sleep(0.5)
        return
    end
    
    updater = Updater.new()
    Utils.printC("Checking for updates...", colors.yellow)
    
    local hasUpdate, info = updater:checkForUpdates()
    
    if hasUpdate then
        Utils.printC("[!] Update available: v" .. info, colors.lime)
        Utils.printC("Downloading update...", colors.yellow)
        
        local success, result = updater:downloadUpdate(function(file, current, total)
            if file ~= "complete" then
                term.clearLine()
                term.setCursorPos(1, select(2, term.getCursorPos()))
                Utils.printC("  " .. file, colors.gray)
            end
        end)
        
        if success then
            Utils.printC("[OK] Update complete!", colors.green)
            Utils.printC("Restarting...", colors.yellow)
            sleep(1)
            os.reboot()
        else
            Utils.printC("[!] Update failed: " .. result, colors.orange)
            Utils.printC("Continuing with current version...", colors.gray)
            sleep(1)
        end
    else
        Utils.printC("[OK] Up to date (v" .. Updater.VERSION .. ")", colors.green)
    end
    
    sleep(0.5)
end

-- Initialize system
local function init()
    -- Check for updates first
    checkUpdates()
    
    term.clear()
    term.setCursorPos(1, 1)
    
    Utils.printC("================================", colors.cyan)
    Utils.printC("   RS Manager v" .. Updater.VERSION, colors.cyan)
    Utils.printC("================================", colors.cyan)
    print()
    
    -- Load configuration
    Utils.printC("Loading configuration...", colors.yellow)
    config = Config.load(BASE_DIR .. "/config/settings.lua")
    Utils.printC("[OK] Configuration loaded", colors.green)
    
    -- Initialize RS Bridge
    Utils.printC("Connecting to RS Bridge...", colors.yellow)
    bridge = RSBridge.new()
    if not bridge:connect() then
        Utils.printC("[ERROR] Could not connect to RS Bridge!", colors.red)
        Utils.printC("Please ensure an RS Bridge is connected.", colors.gray)
        print()
        Utils.printC("Press any key to exit...", colors.yellow)
        os.pullEvent("key")
        return false
    end
    Utils.printC("[OK] RS Bridge connected", colors.green)
    
    -- Initialize Stock Keeper
    Utils.printC("Initializing Stock Keeper...", colors.yellow)
    stockKeeper = StockKeeper.new(bridge, BASE_DIR .. "/config/stocklist.lua")
    Utils.printC("[OK] Stock Keeper ready", colors.green)
    
    -- Initialize external monitor if available
    Utils.printC("Checking for external monitor...", colors.yellow)
    monitor = Monitor.new(bridge, stockKeeper, monitoredItems, config)
    if monitor:hasMonitor() then
        Utils.printC("[OK] External monitor found", colors.green)
    else
        Utils.printC("[--] No external monitor (optional)", colors.gray)
    end
    
    print()
    Utils.printC("System ready! Press any key to continue...", colors.lime)
    os.pullEvent("key")
    
    return true
end

-- Main menu options
local menuOptions = {
    {name = "Dashboard", action = "dashboard", color = colors.lime},
    {name = "Item Search", action = "search", color = colors.cyan},
    {name = "Stock Keeper", action = "stockkeeper", color = colors.orange},
    {name = "Item Monitor", action = "itemmonitor", color = colors.lightBlue},
    {name = "Crafting Queue", action = "crafting", color = colors.purple},
    {name = "System Stats", action = "stats", color = colors.yellow},
    {name = "Logs", action = "logs", color = colors.brown},
    {name = "Settings", action = "settings", color = colors.lightGray},
    {name = "Exit", action = "exit", color = colors.red}
}

-- Forward declarations for functions called before definition
local showAddStockItem
local showEditStockItem
local showNewCraft
local showItemMonitor
local showAddMonitorItem
local showLogs

-- Draw main menu
local function drawMainMenu(selected)
    GUI.clear()
    GUI.drawHeader("RS Manager - Main Menu")
    
    local y = 4
    for i, option in ipairs(menuOptions) do
        term.setCursorPos(3, y)
        if i == selected then
            term.setBackgroundColor(option.color)
            term.setTextColor(colors.black)
            term.write(" > " .. option.name .. string.rep(" ", 20 - #option.name))
            term.setBackgroundColor(colors.black)
        else
            term.setTextColor(option.color)
            term.write("   " .. option.name)
        end
        y = y + 2
    end
    
    term.setTextColor(colors.gray)
    term.setCursorPos(2, 19)
    term.write("Use UP/DOWN arrows, ENTER to select")
end

-- Dashboard view
local function showDashboard()
    local needsFullRedraw = true
    
    while true do
        -- Only do full clear on first draw or manual refresh
        if needsFullRedraw then
            GUI.clear()
            GUI.drawHeader("Dashboard")
            
            -- Static labels (only drawn once)
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Energy: ")
            
            term.setCursorPos(2, 6)
            term.setTextColor(colors.cyan)
            term.write("Total Items: ")
            
            term.setCursorPos(2, 7)
            term.setTextColor(colors.cyan)
            term.write("Unique Types: ")
            
            term.setCursorPos(2, 8)
            term.setTextColor(colors.purple)
            term.write("Crafting Jobs: ")
            
            term.setCursorPos(2, 10)
            term.setTextColor(colors.orange)
            term.write("Stock Keeper: ")
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Back  [R] Refresh")
            
            needsFullRedraw = false
        end
        
        -- Get RS data
        local energy = bridge:getEnergyStorage() or 0
        local maxEnergy = bridge:getMaxEnergyStorage() or 1
        local energyPercent = maxEnergy > 0 and math.floor((energy / maxEnergy) * 100) or 0
        
        local items = bridge:listItems() or {}
        local totalItems = 0
        local uniqueItems = #items
        for _, item in ipairs(items) do
            totalItems = totalItems + (item.amount or item.count or 0)
        end
        
        local craftingJobs = bridge:getCraftingTasks() or {}
        
        -- Update dynamic values (clear specific areas first)
        local energyColor = colors.green
        if energyPercent < 25 then energyColor = colors.red
        elseif energyPercent < 50 then energyColor = colors.orange end
        
        GUI.drawProgressBar(10, 4, 25, energyPercent, energyColor)
        term.setCursorPos(36, 4)
        term.setTextColor(colors.white)
        term.write(energyPercent .. "%  ")
        
        term.setCursorPos(15, 6)
        term.setTextColor(colors.white)
        term.write(Utils.formatNumber(totalItems) .. "      ")
        
        term.setCursorPos(16, 7)
        term.setTextColor(colors.white)
        term.write(tostring(uniqueItems) .. "      ")
        
        term.setCursorPos(17, 8)
        term.setTextColor(colors.white)
        term.write(tostring(#craftingJobs) .. "      ")
        
        -- Stock keeper status
        term.setCursorPos(16, 10)
        if stockKeeper:isEnabled() then
            term.setTextColor(colors.green)
            term.write("ACTIVE ")
            term.setTextColor(colors.gray)
            term.write("(" .. stockKeeper:getActiveCount() .. " items)  ")
        else
            term.setTextColor(colors.red)
            term.write("DISABLED          ")
        end
        
        -- Low stock alerts (clear area first)
        for clearY = 12, 17 do
            term.setCursorPos(2, clearY)
            term.write(string.rep(" ", 45))
        end
        
        local lowStock = stockKeeper:getLowStock()
        if #lowStock > 0 then
            term.setCursorPos(2, 12)
            term.setTextColor(colors.red)
            term.write("! LOW STOCK ALERTS:")
            local y = 13
            for i = 1, math.min(4, #lowStock) do
                term.setCursorPos(4, y)
                term.setTextColor(colors.orange)
                local item = lowStock[i]
                term.write(Utils.truncate(item.displayName, 25))
                term.setTextColor(colors.gray)
                term.write(" " .. item.current .. "/" .. item.target)
                y = y + 1
            end
        end
        
        -- Wait for input or timeout
        local timer = os.startTimer(config.refreshRate or 5)
        while true do
            local event, key = os.pullEvent()
            if event == "key" then
                if key == keys.q then
                    return
                elseif key == keys.r then
                    needsFullRedraw = true
                    break
                end
            elseif event == "timer" and key == timer then
                break
            end
        end
    end
end

-- Item search view
local function showItemSearch()
    local searchTerm = ""
    local results = {}
    local scroll = 0
    local maxDisplay = 10
    
    while true do
        GUI.clear()
        GUI.drawHeader("Item Search")
        
        term.setCursorPos(2, 4)
        term.setTextColor(colors.yellow)
        term.write("Search: ")
        term.setTextColor(colors.white)
        term.write(searchTerm .. "_")
        
        -- Show results
        if #results > 0 then
            term.setCursorPos(2, 6)
            term.setTextColor(colors.gray)
            term.write("Found " .. #results .. " items:")
            
            local y = 7
            for i = scroll + 1, math.min(scroll + maxDisplay, #results) do
                local item = results[i]
                term.setCursorPos(2, y)
                term.setTextColor(colors.cyan)
                term.write(Utils.truncate(item.displayName or item.name, 30))
                term.setCursorPos(35, y)
                term.setTextColor(colors.white)
                term.write(Utils.formatNumber(item.amount or item.count or 0))
                y = y + 1
            end
            
            if #results > maxDisplay then
                term.setCursorPos(2, 18)
                term.setTextColor(colors.gray)
                term.write("Scroll: UP/DOWN | Page: PgUp/PgDn")
            end
        elseif searchTerm ~= "" then
            term.setCursorPos(2, 6)
            term.setTextColor(colors.red)
            term.write("No items found.")
        end
        
        term.setCursorPos(2, 19)
        term.setTextColor(colors.gray)
        term.write("[Q] Back | Type to search")
        
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.q or key == keys.backspace then
                return
            elseif key == keys.backspace then
                searchTerm = searchTerm:sub(1, -2)
                scroll = 0
                if searchTerm ~= "" then
                    results = bridge:findItem(searchTerm)
                else
                    results = {}
                end
            elseif key == keys.up then
                scroll = math.max(0, scroll - 1)
            elseif key == keys.down then
                scroll = math.min(math.max(0, #results - maxDisplay), scroll + 1)
            elseif key == keys.pageUp then
                scroll = math.max(0, scroll - maxDisplay)
            elseif key == keys.pageDown then
                scroll = math.min(math.max(0, #results - maxDisplay), scroll + maxDisplay)
            elseif key == keys.enter then
                -- Could add item details view here
            end
        elseif event == "char" then
            searchTerm = searchTerm .. key
            scroll = 0
            results = bridge:findItem(searchTerm)
        end
    end
end

-- Stock Keeper management view
local function showStockKeeper()
    local items = stockKeeper:getItems()
    local selected = 1
    local scroll = 0
    local maxDisplay = 10
    
    while true do
        GUI.clear()
        GUI.drawHeader("Stock Keeper")
        
        -- Status toggle
        term.setCursorPos(2, 4)
        term.setTextColor(colors.yellow)
        term.write("Status: ")
        if stockKeeper:isEnabled() then
            term.setTextColor(colors.green)
            term.write("[ENABLED]")
        else
            term.setTextColor(colors.red)
            term.write("[DISABLED]")
        end
        term.setTextColor(colors.gray)
        term.write(" (Press T to toggle)")
        
        -- Item list
        term.setCursorPos(2, 6)
        term.setTextColor(colors.gray)
        term.write("Tracked Items: " .. #items)
        
        local y = 7
        for i = scroll + 1, math.min(scroll + maxDisplay, #items) do
            local item = items[i]
            term.setCursorPos(2, y)
            
            if i == selected then
                term.setBackgroundColor(colors.gray)
            end
            
            -- Status indicator - prioritize actual stock level
            local current = bridge:getItemAmount(item.name) or 0
            local target = item.amount or 1
            
            -- Clear stale craft status if item is now stocked
            if current >= target and (item.lastCraftStatus == "no_materials" or item.lastCraftStatus == "crafting") then
                item.lastCraftStatus = nil
            end
            
            if item.patternStatus == "no_pattern" then
                term.setTextColor(colors.magenta)
                term.write("X")  -- Pattern missing
            elseif current < target and item.lastCraftStatus == "no_materials" then
                term.setTextColor(colors.yellow)
                term.write("M")  -- Missing materials
            elseif current >= target then
                term.setTextColor(colors.green)
                term.write("+")
            elseif current >= target * 0.5 then
                term.setTextColor(colors.orange)
                term.write("~")
            else
                term.setTextColor(colors.red)
                term.write("!")
            end
            
            term.setTextColor(colors.white)
            term.write(" " .. Utils.truncate(item.displayName or item.name or "Unknown", 22))
            term.setCursorPos(28, y)
            term.setTextColor(colors.cyan)
            term.write(Utils.formatNumber(current) .. "/" .. Utils.formatNumber(target))
            
            -- Show status suffix
            if item.patternStatus == "no_pattern" then
                term.setTextColor(colors.magenta)
                term.write(" [NO PAT]")
            elseif item.lastCraftStatus == "no_materials" then
                term.setTextColor(colors.yellow)
                term.write(" [NO MAT]")
            end
            
            term.setBackgroundColor(colors.black)
            y = y + 1
        end
        
        term.setCursorPos(2, 17)
        term.setTextColor(colors.gray)
        term.write("+ OK  ~ Low  ! Crit  X NoPat  M NoMat")
        term.setCursorPos(2, 18)
        term.write("[A]dd [E]dit [D]el [C]raft [R]efresh")
        term.setCursorPos(2, 19)
        term.write("[Q]Back [T]oggle [S]ave")
        
        -- Use key event only to avoid char event bleeding into dialogs
        local event, key = os.pullEvent("key")
        if key == keys.q then
            return
        elseif key == keys.t then
            stockKeeper:toggle()
        elseif key == keys.up then
            selected = math.max(1, selected - 1)
            if selected <= scroll then
                scroll = math.max(0, scroll - 1)
            end
        elseif key == keys.down then
            selected = math.min(#items, selected + 1)
            if selected > scroll + maxDisplay then
                scroll = scroll + 1
            end
        elseif key == keys.a then
            -- Add new item - sleep briefly to let char event pass
            sleep(0.05)
            showAddStockItem()
            items = stockKeeper:getItems()
        elseif key == keys.e and #items > 0 then
            -- Edit selected item
            sleep(0.05)
            showEditStockItem(items[selected])
            items = stockKeeper:getItems()
        elseif key == keys.d and #items > 0 then
            -- Delete selected item
            stockKeeper:removeItem(items[selected].name)
            items = stockKeeper:getItems()
            selected = math.min(selected, #items)
        elseif key == keys.c and #items > 0 then
            -- Craft selected item now
            local item = items[selected]
            local current = bridge:getItemAmount(item.name) or 0
            local target = item.amount or 1
            local needed = target - current
            if needed > 0 then
                local success, reason = bridge:craftItem(item.name, needed)
                if success then
                    -- Refresh monitor immediately to show crafting job
                    if monitor and monitor:hasMonitor() and config.useMonitor then
                        monitor:update()
                    end
                else
                    -- Show brief error
                    term.setCursorPos(2, 16)
                    term.setTextColor(colors.red)
                    if reason == "no_pattern" then
                        term.write("Error: Pattern missing!")
                    elseif reason == "no_materials" then
                        term.write("Error: Missing materials!")
                    else
                        term.write("Error: Could not craft")
                    end
                    sleep(1)
                end
            end
            items = stockKeeper:getItems()
        elseif key == keys.r then
            -- Refresh patterns
            term.setCursorPos(2, 16)
            term.setTextColor(colors.yellow)
            term.write("Refreshing patterns...")
            bridge:refreshCraftables()
            stockKeeper:validatePatterns(true)
            items = stockKeeper:getItems()
        elseif key == keys.s then
            stockKeeper:save()
        end
    end
end

-- Add stock item dialog
showAddStockItem = function()
    local searchTerm = ""
    local results = {}
    local selectedResult = 1
    local amount = ""  -- Changed to string for direct input
    local phase = "search" -- search, amount
    local refreshed = false  -- Track if we've refreshed craftables
    local needsRedraw = true
    
    local function draw()
        GUI.clear()
        GUI.drawHeader("Add Stock Item")
        
        if phase == "search" then
            -- Refresh craftables on first entry (lazy load)
            if not refreshed then
                term.setCursorPos(2, 4)
                term.setTextColor(colors.yellow)
                term.write("Loading craftable items...")
                bridge:refreshCraftables()
                refreshed = true
                GUI.clear()
                GUI.drawHeader("Add Stock Item")
            end
            
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Search item: ")
            term.setTextColor(colors.white)
            term.write(searchTerm .. "_")
            
            if #results > 0 then
                local y = 6
                for i = 1, math.min(8, #results) do
                    term.setCursorPos(2, y)
                    if i == selectedResult then
                        term.setBackgroundColor(colors.gray)
                    end
                    term.setTextColor(colors.cyan)
                    term.write(Utils.truncate(results[i].displayName or results[i].name, 35))
                    term.setBackgroundColor(colors.black)
                    y = y + 1
                end
            end
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Cancel | [ENTER] Select | UP/DOWN")
            
        else -- amount phase
            local item = results[selectedResult]
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Item: ")
            term.setTextColor(colors.cyan)
            term.write(item.displayName or item.name)
            
            term.setCursorPos(2, 6)
            term.setTextColor(colors.yellow)
            term.write("Current in system: ")
            term.setTextColor(colors.white)
            -- Get actual current amount from storage, not from craftable item
            local currentAmount = bridge:getItemAmount(item.name) or 0
            term.write(Utils.formatNumber(currentAmount))
            
            term.setCursorPos(2, 8)
            term.setTextColor(colors.yellow)
            term.write("Target amount: ")
            term.setTextColor(colors.white)
            if amount == "" then
                term.setTextColor(colors.gray)
                term.write("(type number)")
            else
                term.write(tostring(amount) .. "_")
            end
            
            term.setCursorPos(2, 10)
            term.setTextColor(colors.gray)
            term.write("Type number | Backspace to delete")
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Back | [ENTER] Confirm")
        end
    end
    
    while true do
        if needsRedraw then
            draw()
            needsRedraw = false
        end
        
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.q then
                if phase == "amount" then
                    phase = "search"
                    needsRedraw = true
                else
                    return
                end
            elseif phase == "search" then
                if key == keys.backspace then
                    searchTerm = searchTerm:sub(1, -2)
                    selectedResult = 1
                    if searchTerm ~= "" then
                        results = bridge:findCraftable(searchTerm)
                    else
                        results = {}
                    end
                    needsRedraw = true
                elseif key == keys.up then
                    selectedResult = math.max(1, selectedResult - 1)
                    needsRedraw = true
                elseif key == keys.down then
                    selectedResult = math.min(#results, selectedResult + 1)
                    needsRedraw = true
                elseif key == keys.enter and #results > 0 then
                    phase = "amount"
                    amount = ""  -- Start with empty string for typing
                    needsRedraw = true
                end
            else -- amount phase
                if key == keys.backspace then
                    if #amount > 0 then
                        amount = amount:sub(1, -2)
                        needsRedraw = true
                    end
                elseif key == keys.enter then
                    local amountNum = tonumber(amount)
                    if amountNum and amountNum >= 1 and amountNum <= 999999 then
                        local item = results[selectedResult]
                        stockKeeper:addItem(item.name, amountNum, item.displayName)
                        return
                    else
                        needsRedraw = true
                    end
                end
            end
        elseif event == "char" and phase == "search" then
            searchTerm = searchTerm .. key
            selectedResult = 1
            results = bridge:findCraftable(searchTerm)
            needsRedraw = true
        elseif event == "char" and phase == "amount" then
            local digit = tonumber(key)
            if digit ~= nil then
                amount = amount .. key
                local testNum = tonumber(amount)
                if testNum and testNum <= 999999 then
                    needsRedraw = true
                else
                    amount = amount:sub(1, -2)
                end
            end
        end
    end
end

-- Edit stock item dialog
showEditStockItem = function(item)
    if not item then return end
    local inputStr = ""
    local needsRedraw = true
    
    local function draw()
        GUI.clear()
        GUI.drawHeader("Edit Stock Item")
        
        term.setCursorPos(2, 4)
        term.setTextColor(colors.yellow)
        term.write("Item: ")
        term.setTextColor(colors.cyan)
        term.write(item.displayName or item.name or "Unknown")
        
        term.setCursorPos(2, 6)
        term.setTextColor(colors.yellow)
        term.write("Previous target: ")
        term.setTextColor(colors.white)
        term.write(tostring(item.amount or 0))
        
        term.setCursorPos(2, 8)
        term.setTextColor(colors.yellow)
        term.write("New target: ")
        term.setTextColor(colors.white)
        if inputStr == "" then
            term.setTextColor(colors.gray)
            term.write("(type number)")
        else
            term.write(inputStr .. "_")
        end
        
        term.setCursorPos(2, 10)
        term.setTextColor(colors.gray)
        term.write("Type number | Backspace to delete")
        
        term.setCursorPos(2, 19)
        term.setTextColor(colors.gray)
        term.write("[Q] Cancel | [ENTER] Save")
    end
    
    while true do
        if needsRedraw then
            draw()
            needsRedraw = false
        end
        
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.q then
                return
            elseif key == keys.backspace then
                if #inputStr > 0 then
                    inputStr = inputStr:sub(1, -2)
                    needsRedraw = true
                end
            elseif key == keys.enter then
                local amount = tonumber(inputStr)
                if amount and amount >= 1 and amount <= 999999 then
                    stockKeeper:updateItem(item.name, amount)
                    return
                else
                    needsRedraw = true
                end
            end
        elseif event == "char" then
            local digit = tonumber(key)
            if digit ~= nil then
                inputStr = inputStr .. key
                local testNum = tonumber(inputStr)
                if testNum and testNum <= 999999 then
                    needsRedraw = true
                else
                    inputStr = inputStr:sub(1, -2)
                end
            end
        end
    end
end

-- Item Monitor data (stored separately from stock keeper)
local monitoredItems = {}
local MONITOR_FILE = BASE_DIR .. "/config/monitored.lua"

local function loadMonitoredItems()
    if fs.exists(MONITOR_FILE) then
        local file = fs.open(MONITOR_FILE, "r")
        if file then
            local content = file.readAll()
            file.close()
            local data = textutils.unserialise(content)
            if data then
                monitoredItems = data
            end
        end
    end
end

local function saveMonitoredItems()
    local dir = fs.getDir(MONITOR_FILE)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local file = fs.open(MONITOR_FILE, "w")
    if file then
        file.write(textutils.serialise(monitoredItems))
        file.close()
    end
    -- Update external monitor reference
    if monitor then
        monitor:setMonitoredItems(monitoredItems)
    end
end

-- Initialize monitored items on load
loadMonitoredItems()

-- Item Monitor view (monitoring only, no auto-crafting)
showItemMonitor = function()
    local selected = 1
    local scroll = 0
    local maxDisplay = 10
    
    while true do
        GUI.clear()
        GUI.drawHeader("Item Monitor")
        
        term.setCursorPos(2, 3)
        term.setTextColor(colors.lightBlue)
        term.write("Track items with low-stock alerts (no auto-craft)")
        
        local y = 5
        local items = monitoredItems
        
        if #items == 0 then
            term.setCursorPos(2, y)
            term.setTextColor(colors.gray)
            term.write("No items being monitored.")
            term.setCursorPos(2, y + 1)
            term.write("Press [A] to add an item to monitor.")
        else
            for i = scroll + 1, math.min(scroll + maxDisplay, #items) do
                local item = items[i]
                local current = bridge:getItemAmount(item.name) or 0
                local threshold = item.threshold or 0
                local percent = threshold > 0 and (current / threshold * 100) or 100
                
                term.setCursorPos(2, y)
                if i == selected then
                    term.setBackgroundColor(colors.gray)
                end
                
                -- Color based on status
                if current < threshold then
                    term.setTextColor(colors.red)
                    term.write("!")
                elseif current < threshold * 1.5 then
                    term.setTextColor(colors.orange)
                    term.write("~")
                else
                    term.setTextColor(colors.green)
                    term.write(" ")
                end
                
                term.setTextColor(colors.white)
                term.write(" " .. Utils.truncate(item.displayName or item.name, 22))
                term.setCursorPos(28, y)
                term.setTextColor(colors.cyan)
                term.write(Utils.formatNumber(current))
                term.setTextColor(colors.gray)
                term.write("/")
                term.setTextColor(colors.yellow)
                term.write(Utils.formatNumber(threshold))
                
                term.setBackgroundColor(colors.black)
                y = y + 1
            end
        end
        
        term.setCursorPos(2, 18)
        term.setTextColor(colors.gray)
        term.write("[A]dd [E]dit [D]el [S]ave")
        term.setCursorPos(2, 19)
        term.write("[Q]Back  UP/DOWN scroll")
        
        local event, key = os.pullEvent("key")
        if key == keys.q then
            return
        elseif key == keys.up then
            selected = math.max(1, selected - 1)
            if selected <= scroll then
                scroll = math.max(0, scroll - 1)
            end
        elseif key == keys.down then
            selected = math.min(#items, selected + 1)
            if selected > scroll + maxDisplay then
                scroll = scroll + 1
            end
        elseif key == keys.a then
            sleep(0.05)
            showAddMonitorItem()
        elseif key == keys.e and #items > 0 then
            sleep(0.05)
            -- Edit threshold
            local item = items[selected]
            local inputStr = ""
            local needsRedraw = true
            
            local function drawThreshold()
                GUI.clear()
                GUI.drawHeader("Edit Monitor Threshold")
                
                term.setCursorPos(2, 4)
                term.setTextColor(colors.yellow)
                term.write("Item: ")
                term.setTextColor(colors.cyan)
                term.write(item.displayName or item.name)
                
                term.setCursorPos(2, 6)
                term.setTextColor(colors.yellow)
                term.write("Current in system: ")
                term.setTextColor(colors.white)
                term.write(Utils.formatNumber(bridge:getItemAmount(item.name) or 0))
                
                term.setCursorPos(2, 8)
                term.setTextColor(colors.yellow)
                term.write("Previous threshold: ")
                term.setTextColor(colors.white)
                term.write(tostring(item.threshold or 0))
                
                term.setCursorPos(2, 10)
                term.setTextColor(colors.yellow)
                term.write("New threshold: ")
                term.setTextColor(colors.white)
                if inputStr == "" then
                    term.setTextColor(colors.gray)
                    term.write("(type number)")
                else
                    term.write(inputStr .. "_")
                end
                
                term.setCursorPos(2, 12)
                term.setTextColor(colors.gray)
                term.write("Type number | Backspace to delete")
                
                term.setCursorPos(2, 19)
                term.write("[Q] Cancel | [ENTER] Save")
            end
            
            while true do
                if needsRedraw then
                    drawThreshold()
                    needsRedraw = false
                end
                
                local ev, k = os.pullEvent()
                if ev == "key" then
                    if k == keys.q then
                        break
                    elseif k == keys.backspace then
                        if #inputStr > 0 then
                            inputStr = inputStr:sub(1, -2)
                            needsRedraw = true
                        end
                    elseif k == keys.enter then
                        local threshold = tonumber(inputStr)
                        if threshold and threshold >= 1 and threshold <= 999999 then
                            item.threshold = threshold
                            saveMonitoredItems()
                            break
                        else
                            needsRedraw = true
                        end
                    end
                elseif ev == "char" then
                    local digit = tonumber(k)
                    if digit ~= nil then
                        inputStr = inputStr .. k
                        local testNum = tonumber(inputStr)
                        if testNum and testNum <= 999999 then
                            needsRedraw = true
                        else
                            inputStr = inputStr:sub(1, -2)
                        end
                    end
                end
            end
        elseif key == keys.d and #items > 0 then
            table.remove(monitoredItems, selected)
            saveMonitoredItems()
            selected = math.min(selected, #items)
        elseif key == keys.s then
            saveMonitoredItems()
        end
    end
end

-- Add item to monitor
showAddMonitorItem = function()
    local searchTerm = ""
    local results = {}
    local selectedResult = 1
    local threshold = 64
    local phase = "search"
    
    while true do
        GUI.clear()
        GUI.drawHeader("Add Monitored Item")
        
        if phase == "search" then
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Search item: ")
            term.setTextColor(colors.white)
            term.write(searchTerm .. "_")
            
            if #results > 0 then
                local y = 6
                for i = 1, math.min(8, #results) do
                    term.setCursorPos(2, y)
                    if i == selectedResult then
                        term.setBackgroundColor(colors.gray)
                    end
                    term.setTextColor(colors.cyan)
                    term.write(Utils.truncate(results[i].displayName or results[i].name, 35))
                    term.setBackgroundColor(colors.black)
                    y = y + 1
                end
            end
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Cancel | [ENTER] Select")
        else
            local item = results[selectedResult]
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Item: ")
            term.setTextColor(colors.cyan)
            term.write(item.displayName or item.name)
            
            term.setCursorPos(2, 6)
            term.setTextColor(colors.yellow)
            term.write("Current in system: ")
            term.setTextColor(colors.white)
            term.write(Utils.formatNumber(item.amount or item.count or 0))
            
            term.setCursorPos(2, 8)
            term.setTextColor(colors.yellow)
            term.write("Low threshold: ")
            term.setTextColor(colors.white)
            term.write(tostring(threshold) .. "_")
            
            term.setCursorPos(2, 10)
            term.setTextColor(colors.gray)
            term.write("Alert when stock falls below this")
            
            term.setCursorPos(2, 19)
            term.write("[Q] Back | [ENTER] Add")
        end
        
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.q then
                if phase == "threshold" then
                    phase = "search"
                else
                    return
                end
            elseif phase == "search" then
                if key == keys.backspace then
                    searchTerm = searchTerm:sub(1, -2)
                    selectedResult = 1
                    if searchTerm ~= "" then
                        results = bridge:findItem(searchTerm)
                    else
                        results = {}
                    end
                elseif key == keys.up then
                    selectedResult = math.max(1, selectedResult - 1)
                elseif key == keys.down then
                    selectedResult = math.min(#results, selectedResult + 1)
                elseif key == keys.enter and #results > 0 then
                    phase = "threshold"
                    threshold = results[selectedResult].amount or 64
                end
            else
                if key == keys.up or key == keys.equals then
                    threshold = threshold + 1
                elseif key == keys.down or key == keys.minus then
                    threshold = math.max(1, threshold - 1)
                elseif key == keys.backspace then
                    threshold = math.floor(threshold / 10)
                    if threshold < 1 then threshold = 1 end
                elseif key == keys.enter then
                    local item = results[selectedResult]
                    -- Check if already monitored
                    local exists = false
                    for i, m in ipairs(monitoredItems) do
                        if m.name == item.name then
                            monitoredItems[i].threshold = threshold
                            exists = true
                            break
                        end
                    end
                    if not exists then
                        table.insert(monitoredItems, {
                            name = item.name,
                            displayName = item.displayName or item.name,
                            threshold = threshold
                        })
                    end
                    saveMonitoredItems()
                    return
                end
            end
        elseif event == "char" and phase == "search" then
            searchTerm = searchTerm .. key
            selectedResult = 1
            results = bridge:findItem(searchTerm)
        elseif event == "char" and phase == "threshold" then
            local digit = tonumber(key)
            if digit then
                threshold = threshold * 10 + digit
                if threshold > 999999 then threshold = 999999 end
            end
        end
    end
end

-- Crafting queue view
local function showCraftingQueue()
    while true do
        GUI.clear()
        GUI.drawHeader("Crafting Queue")
        
        local tasks = bridge:getCraftingTasks() or {}
        
        if #tasks == 0 then
            term.setCursorPos(2, 6)
            term.setTextColor(colors.gray)
            term.write("No active crafting tasks.")
        else
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Active Tasks: " .. #tasks)
            
            local y = 6
            for i, task in ipairs(tasks) do
                if y > 17 then break end
                
                term.setCursorPos(2, y)
                term.setTextColor(colors.cyan)
                -- Use displayName first, fall back to name
                local taskName = task.displayName or task.name or "Unknown"
                term.write(Utils.truncate(taskName, 25))
                
                term.setCursorPos(30, y)
                term.setTextColor(colors.white)
                term.write("x" .. Utils.formatNumber(task.amount or 0))
                
                -- Progress if available
                if task.progress then
                    term.setCursorPos(42, y)
                    term.setTextColor(colors.green)
                    term.write(math.floor(task.progress * 100) .. "%")
                end
                
                y = y + 1
            end
        end
        
        term.setCursorPos(2, 19)
        term.setTextColor(colors.gray)
        term.write("[Q] Back  [R] Refresh  [N] New Craft")
        
        local timer = os.startTimer(2)
        while true do
            local event, key = os.pullEvent()
            if event == "key" then
                if key == keys.q then
                    return
                elseif key == keys.r then
                    break
                elseif key == keys.n then
                    showNewCraft()
                    break
                end
            elseif event == "timer" and key == timer then
                break
            end
        end
    end
end

-- New craft dialog
showNewCraft = function()
    local searchTerm = ""
    local results = {}
    local selectedResult = 1
    local amount = 1
    local phase = "search"
    
    while true do
        GUI.clear()
        GUI.drawHeader("Request Craft")
        
        if phase == "search" then
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Search craftable: ")
            term.setTextColor(colors.white)
            term.write(searchTerm .. "_")
            
            if #results > 0 then
                local y = 6
                for i = 1, math.min(8, #results) do
                    term.setCursorPos(2, y)
                    if i == selectedResult then
                        term.setBackgroundColor(colors.gray)
                    end
                    term.setTextColor(colors.cyan)
                    term.write(Utils.truncate(results[i].displayName or results[i].name, 35))
                    term.setBackgroundColor(colors.black)
                    y = y + 1
                end
            end
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Cancel | [ENTER] Select")
            
        else
            local item = results[selectedResult]
            term.setCursorPos(2, 4)
            term.setTextColor(colors.yellow)
            term.write("Item: ")
            term.setTextColor(colors.cyan)
            term.write(item.displayName or item.name)
            
            term.setCursorPos(2, 6)
            term.setTextColor(colors.yellow)
            term.write("Amount to craft: ")
            term.setTextColor(colors.white)
            term.write(tostring(amount) .. "_")
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Back | [ENTER] Start Craft")
        end
        
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.q or key == keys.backspace then
                if phase == "amount" then
                    phase = "search"
                else
                    return
                end
            elseif phase == "search" then
                if key == keys.backspace then
                    searchTerm = searchTerm:sub(1, -2)
                    selectedResult = 1
                    if searchTerm ~= "" then
                        results = bridge:findCraftable(searchTerm)
                    else
                        results = {}
                    end
                elseif key == keys.up then
                    selectedResult = math.max(1, selectedResult - 1)
                elseif key == keys.down then
                    selectedResult = math.min(#results, selectedResult + 1)
                elseif key == keys.enter and #results > 0 then
                    phase = "amount"
                end
            else
                if key == keys.up then
                    amount = amount + 1
                elseif key == keys.down then
                    amount = math.max(1, amount - 1)
                elseif key == keys.pageUp then
                    amount = amount + 64
                elseif key == keys.pageDown then
                    amount = math.max(1, amount - 64)
                elseif key == keys.backspace then
                    amount = math.floor(amount / 10)
                    if amount < 1 then amount = 1 end
                elseif key == keys.enter then
                    bridge:craftItem(results[selectedResult].name, amount)
                    return
                end
            end
        elseif event == "char" and phase == "search" then
            searchTerm = searchTerm .. key
            selectedResult = 1
            results = bridge:findCraftable(searchTerm)
        elseif event == "char" and phase == "amount" then
            local digit = tonumber(key)
            if digit then
                amount = amount * 10 + digit
            end
        end
    end
end

-- Logs viewer
showLogs = function()
    local LOG_DIR = BASE_DIR .. "/logs"
    local logFiles = {}
    local selectedFile = 1
    local scroll = 0
    local lines = {}
    local viewingFile = false
    
    -- Get list of log files
    local function refreshFiles()
        logFiles = {}
        if fs.exists(LOG_DIR) and fs.isDir(LOG_DIR) then
            for _, file in ipairs(fs.list(LOG_DIR)) do
                if file:match("%.log") or file:match("%.log%.old") then
                    table.insert(logFiles, file)
                end
            end
        end
        table.sort(logFiles)
    end
    
    -- Load a log file
    local function loadFile(filename)
        lines = {}
        local path = LOG_DIR .. "/" .. filename
        if fs.exists(path) then
            local file = fs.open(path, "r")
            if file then
                local content = file.readAll()
                file.close()
                for line in content:gmatch("[^\r\n]+") do
                    table.insert(lines, line)
                end
            end
        end
        -- Show most recent lines first (reverse order)
        local reversed = {}
        for i = #lines, 1, -1 do
            table.insert(reversed, lines[i])
        end
        lines = reversed
    end
    
    refreshFiles()
    
    while true do
        GUI.clear()
        
        if not viewingFile then
            -- File list view
            GUI.drawHeader("Logs")
            
            if #logFiles == 0 then
                term.setCursorPos(2, 5)
                term.setTextColor(colors.gray)
                term.write("No log files found.")
                term.setCursorPos(2, 7)
                term.write("Logs are stored in: " .. LOG_DIR)
            else
                term.setCursorPos(2, 3)
                term.setTextColor(colors.yellow)
                term.write("Select a log file:")
                
                local y = 5
                for i, file in ipairs(logFiles) do
                    if y > 16 then break end
                    term.setCursorPos(2, y)
                    if i == selectedFile then
                        term.setBackgroundColor(colors.gray)
                    end
                    term.setTextColor(colors.cyan)
                    
                    -- Show file size
                    local path = LOG_DIR .. "/" .. file
                    local size = fs.exists(path) and fs.getSize(path) or 0
                    local sizeStr = size > 1024 and string.format("%.1fKB", size/1024) or size .. "B"
                    
                    term.write(" " .. file .. " (" .. sizeStr .. ")")
                    term.setBackgroundColor(colors.black)
                    y = y + 1
                end
            end
            
            term.setCursorPos(2, 18)
            term.setTextColor(colors.gray)
            term.write("[ENTER] View  [D] Delete  [C] Clear All")
            term.setCursorPos(2, 19)
            term.write("[Q] Back  [R] Refresh")
        else
            -- File content view
            GUI.drawHeader("Log: " .. logFiles[selectedFile])
            
            local maxLines = 14
            local y = 3
            
            if #lines == 0 then
                term.setCursorPos(2, 5)
                term.setTextColor(colors.gray)
                term.write("Log file is empty.")
            else
                term.setCursorPos(2, 3)
                term.setTextColor(colors.gray)
                term.write("Showing " .. math.min(#lines, maxLines) .. " of " .. #lines .. " lines (newest first)")
                y = 5
                
                for i = scroll + 1, math.min(scroll + maxLines, #lines) do
                    term.setCursorPos(2, y)
                    local line = lines[i] or ""
                    -- Color based on content
                    if line:find("Error") or line:find("ERROR") then
                        term.setTextColor(colors.red)
                    elseif line:find("Warning") or line:find("WARN") then
                        term.setTextColor(colors.orange)
                    else
                        term.setTextColor(colors.lightGray)
                    end
                    term.write(Utils.truncate(line, 48))
                    y = y + 1
                end
            end
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Back  UP/DOWN Scroll  [R] Refresh")
        end
        
        local event, key = os.pullEvent("key")
        
        if not viewingFile then
            -- File list navigation
            if key == keys.q then
                return
            elseif key == keys.up and #logFiles > 0 then
                selectedFile = math.max(1, selectedFile - 1)
            elseif key == keys.down and #logFiles > 0 then
                selectedFile = math.min(#logFiles, selectedFile + 1)
            elseif key == keys.enter and #logFiles > 0 then
                loadFile(logFiles[selectedFile])
                scroll = 0
                viewingFile = true
            elseif key == keys.r then
                refreshFiles()
            elseif key == keys.d and #logFiles > 0 then
                -- Delete selected log
                local path = LOG_DIR .. "/" .. logFiles[selectedFile]
                if fs.exists(path) then
                    fs.delete(path)
                end
                refreshFiles()
                selectedFile = math.min(selectedFile, #logFiles)
            elseif key == keys.c then
                -- Clear all logs
                if fs.exists(LOG_DIR) then
                    for _, file in ipairs(fs.list(LOG_DIR)) do
                        fs.delete(LOG_DIR .. "/" .. file)
                    end
                end
                refreshFiles()
                selectedFile = 1
            end
        else
            -- File content navigation
            if key == keys.q then
                viewingFile = false
            elseif key == keys.up then
                scroll = math.max(0, scroll - 1)
            elseif key == keys.down then
                scroll = math.min(math.max(0, #lines - 14), scroll + 1)
            elseif key == keys.pageUp then
                scroll = math.max(0, scroll - 10)
            elseif key == keys.pageDown then
                scroll = math.min(math.max(0, #lines - 14), scroll + 10)
            elseif key == keys.r then
                loadFile(logFiles[selectedFile])
            end
        end
    end
end

-- System stats view
local function showSystemStats()
    while true do
        GUI.clear()
        GUI.drawHeader("System Statistics")
        
        local y = 4
        
        -- Energy stats
        term.setCursorPos(2, y)
        term.setTextColor(colors.yellow)
        term.write("=== Energy ===")
        y = y + 1
        
        local energy = bridge:getEnergyStorage()
        local maxEnergy = bridge:getMaxEnergyStorage()
        local usage = bridge:getEnergyUsage()
        
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        term.write("Stored: ")
        term.setTextColor(colors.white)
        term.write(Utils.formatNumber(energy) .. " / " .. Utils.formatNumber(maxEnergy) .. " FE")
        y = y + 1
        
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        term.write("Usage: ")
        term.setTextColor(colors.white)
        term.write(Utils.formatNumber(usage) .. " FE/t")
        y = y + 2
        
        -- Storage stats
        term.setCursorPos(2, y)
        term.setTextColor(colors.yellow)
        term.write("=== Storage ===")
        y = y + 1
        
        local items = bridge:listItems()
        local totalItems = 0
        for _, item in ipairs(items) do
            totalItems = totalItems + (item.amount or item.count or 0)
        end
        
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        term.write("Total Items: ")
        term.setTextColor(colors.white)
        term.write(Utils.formatNumber(totalItems))
        y = y + 1
        
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        term.write("Unique Types: ")
        term.setTextColor(colors.white)
        term.write(tostring(#items))
        y = y + 2
        
        -- Fluids
        term.setCursorPos(2, y)
        term.setTextColor(colors.yellow)
        term.write("=== Fluids ===")
        y = y + 1
        
        local fluids = bridge:listFluids() or {}
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        term.write("Fluid Types: ")
        term.setTextColor(colors.white)
        term.write(tostring(#fluids))
        y = y + 1
        
        for i = 1, math.min(3, #fluids) do
            term.setCursorPos(4, y)
            term.setTextColor(colors.cyan)
            local fluid = fluids[i]
            -- Data is already normalized by rsbridge
            term.write(Utils.truncate(fluid.displayName or fluid.name or "Unknown", 20))
            term.setTextColor(colors.white)
            term.write(": " .. Utils.formatNumber(fluid.amount or 0) .. " mB")
            y = y + 1
        end
        
        term.setCursorPos(2, 19)
        term.setTextColor(colors.gray)
        term.write("[Q] Back  [R] Refresh")
        
        local timer = os.startTimer(5)
        while true do
            local event, key = os.pullEvent()
            if event == "key" then
                if key == keys.q then
                    return
                elseif key == keys.r then
                    break
                end
            elseif event == "timer" and key == timer then
                break
            end
        end
    end
end

-- Settings view
local function showSettings()
    local options = {
        {name = "Auto Update", key = "autoUpdate", value = config.autoUpdate, type = "boolean"},
        {name = "Refresh Rate", key = "refreshRate", value = config.refreshRate, type = "number", min = 1, max = 60},
        {name = "Auto-craft Delay", key = "craftDelay", value = config.craftDelay, type = "number", min = 1, max = 300},
        {name = "Low Stock Threshold", key = "lowStockPercent", value = config.lowStockPercent, type = "number", min = 10, max = 90},
        {name = "External Monitor", key = "useMonitor", value = config.useMonitor, type = "boolean"},
        {name = "Monitor Scale", key = "monitorScale", value = config.monitorScale, type = "number", min = 0.5, max = 2},
    }
    local selected = 1
    
    while true do
        GUI.clear()
        GUI.drawHeader("Settings")
        
        local y = 4
        for i, opt in ipairs(options) do
            term.setCursorPos(2, y)
            
            if i == selected then
                term.setBackgroundColor(colors.gray)
            end
            
            term.setTextColor(colors.yellow)
            term.write(opt.name .. ": ")
            
            if opt.type == "boolean" then
                if opt.value then
                    term.setTextColor(colors.green)
                    term.write("Enabled")
                else
                    term.setTextColor(colors.red)
                    term.write("Disabled")
                end
            else
                term.setTextColor(colors.white)
                term.write(tostring(opt.value))
            end
            
            term.setBackgroundColor(colors.black)
            y = y + 2
        end
        
        term.setCursorPos(2, 18)
        term.setTextColor(colors.gray)
        term.write("UP/DOWN: Select | LEFT/RIGHT: Change")
        term.setCursorPos(2, 19)
        term.write("[Q] Back | [S] Save | [R] Reset")
        
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.q then
                return
            elseif key == keys.up then
                selected = math.max(1, selected - 1)
            elseif key == keys.down then
                selected = math.min(#options, selected + 1)
            elseif key == keys.left then
                local opt = options[selected]
                if opt.type == "boolean" then
                    opt.value = not opt.value
                elseif opt.type == "number" then
                    opt.value = math.max(opt.min, opt.value - 1)
                end
                config[opt.key] = opt.value
            elseif key == keys.right then
                local opt = options[selected]
                if opt.type == "boolean" then
                    opt.value = not opt.value
                elseif opt.type == "number" then
                    opt.value = math.min(opt.max, opt.value + 1)
                end
                config[opt.key] = opt.value
            elseif key == keys.s then
                Config.save(BASE_DIR .. "/config/settings.lua", config)
                GUI.showMessage("Settings saved!", colors.green)
            elseif key == keys.r then
                config = Config.getDefaults()
                for _, opt in ipairs(options) do
                    opt.value = config[opt.key]
                end
            end
        end
    end
end

-- Background stock keeper task (wrapped in error handler)
local function stockKeeperTask()
    while running do
        local ok, err = pcall(function()
            if stockKeeper and stockKeeper:isEnabled() then
                local craftedAny = stockKeeper:check()
                -- If we initiated any crafting jobs, refresh monitor immediately
                if craftedAny and monitor and monitor:hasMonitor() and config.useMonitor then
                    monitor:update()
                end
            end
        end)
        if not ok then
            Utils.log("StockKeeper error: " .. tostring(err), "ERROR")
        end
        sleep(config.craftDelay or 10)
    end
end

-- Background monitor update task (wrapped in error handler)
-- Only updates external monitor, not main terminal
local function monitorTask()
    while running do
        local ok, err = pcall(function()
            if monitor and monitor:hasMonitor() and config.useMonitor then
                monitor:update()
            end
        end)
        if not ok then
            Utils.log("Monitor error: " .. tostring(err), "ERROR")
        end
        sleep(config.refreshRate or 5)
    end
end

-- Safe function wrapper for menu actions
local function safeCall(func, ...)
    local args = {...}
    local ok, err = pcall(function()
        func(table.unpack(args))
    end)
    if not ok then
        -- Show error on screen briefly
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("Error occurred:")
        term.setTextColor(colors.white)
        print(tostring(err))
        print()
        term.setTextColor(colors.gray)
        print("Press any key to continue...")
        os.pullEvent("key")
        Utils.log("Menu error: " .. tostring(err), "ERROR")
    end
end

-- Main menu loop
local function mainMenu()
    local selected = 1
    local needsRedraw = true
    
    while running do
        -- Only redraw when needed to prevent flickering
        if needsRedraw then
            drawMainMenu(selected)
            needsRedraw = false
        end
        
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = #menuOptions end
            needsRedraw = true
        elseif key == keys.down then
            selected = selected + 1
            if selected > #menuOptions then selected = 1 end
            needsRedraw = true
        elseif key == keys.enter then
            local action = menuOptions[selected].action
            if action == "exit" then
                running = false
            elseif action == "dashboard" then
                safeCall(showDashboard)
                needsRedraw = true
            elseif action == "search" then
                safeCall(showItemSearch)
                needsRedraw = true
            elseif action == "stockkeeper" then
                safeCall(showStockKeeper)
                needsRedraw = true
            elseif action == "itemmonitor" then
                safeCall(showItemMonitor)
                needsRedraw = true
            elseif action == "crafting" then
                safeCall(showCraftingQueue)
                needsRedraw = true
            elseif action == "stats" then
                safeCall(showSystemStats)
                needsRedraw = true
            elseif action == "logs" then
                safeCall(showLogs)
                needsRedraw = true
            elseif action == "settings" then
                safeCall(showSettings)
                needsRedraw = true
            end
        elseif key == keys.q then
            running = false
        end
    end
end

-- Main entry point with global error handling
local function main()
    local ok, err = pcall(function()
        if not init() then
            return
        end
        
        -- Run main menu and background tasks in parallel
        parallel.waitForAny(
            mainMenu,
            stockKeeperTask,
            monitorTask
        )
    end)
    
    -- Cleanup
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    
    if not ok then
        term.setTextColor(colors.red)
        print("RS Manager crashed!")
        term.setTextColor(colors.white)
        print(tostring(err))
        print()
        print("Check /rsmanager/logs/ for details.")
        Utils.log("CRASH: " .. tostring(err), "ERROR")
    else
        print("RS Manager shutdown complete.")
    end
end

-- Run with top-level error protection
local ok, err = pcall(main)
if not ok then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("Fatal error:")
    term.setTextColor(colors.white)
    print(tostring(err))
end
