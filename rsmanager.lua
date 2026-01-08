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
    monitor = Monitor.new(bridge, stockKeeper)
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
    {name = "Crafting Queue", action = "crafting", color = colors.purple},
    {name = "System Stats", action = "stats", color = colors.yellow},
    {name = "Settings", action = "settings", color = colors.lightGray},
    {name = "Exit", action = "exit", color = colors.red}
}

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
    while true do
        GUI.clear()
        GUI.drawHeader("Dashboard")
        
        -- Get RS data
        local energy = bridge:getEnergyStorage()
        local maxEnergy = bridge:getMaxEnergyStorage()
        local energyPercent = math.floor((energy / maxEnergy) * 100)
        
        local items = bridge:listItems()
        local totalItems = 0
        local uniqueItems = #items
        for _, item in ipairs(items) do
            totalItems = totalItems + item.amount
        end
        
        local craftingJobs = bridge:getCraftingTasks() or {}
        
        -- Display stats
        term.setCursorPos(2, 4)
        term.setTextColor(colors.yellow)
        term.write("Energy: ")
        
        local energyColor = colors.green
        if energyPercent < 25 then energyColor = colors.red
        elseif energyPercent < 50 then energyColor = colors.orange end
        
        GUI.drawProgressBar(10, 4, 25, energyPercent, energyColor)
        term.setCursorPos(36, 4)
        term.setTextColor(colors.white)
        term.write(energyPercent .. "%")
        
        term.setCursorPos(2, 6)
        term.setTextColor(colors.cyan)
        term.write("Total Items: ")
        term.setTextColor(colors.white)
        term.write(Utils.formatNumber(totalItems))
        
        term.setCursorPos(2, 7)
        term.setTextColor(colors.cyan)
        term.write("Unique Types: ")
        term.setTextColor(colors.white)
        term.write(tostring(uniqueItems))
        
        term.setCursorPos(2, 8)
        term.setTextColor(colors.purple)
        term.write("Crafting Jobs: ")
        term.setTextColor(colors.white)
        term.write(tostring(#craftingJobs))
        
        -- Stock keeper status
        term.setCursorPos(2, 10)
        term.setTextColor(colors.orange)
        term.write("Stock Keeper: ")
        if stockKeeper:isEnabled() then
            term.setTextColor(colors.green)
            term.write("ACTIVE")
            term.setTextColor(colors.gray)
            term.write(" (" .. stockKeeper:getActiveCount() .. " items)")
        else
            term.setTextColor(colors.red)
            term.write("DISABLED")
        end
        
        -- Low stock alerts
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
        
        term.setCursorPos(2, 19)
        term.setTextColor(colors.gray)
        term.write("[Q] Back  [R] Refresh")
        
        -- Wait for input or timeout
        local timer = os.startTimer(config.refreshRate or 5)
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
                term.write(Utils.formatNumber(item.amount))
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
            
            -- Status indicator
            local current = bridge:getItemAmount(item.name)
            if current >= item.amount then
                term.setTextColor(colors.green)
                term.write("+")
            elseif current >= item.amount * 0.5 then
                term.setTextColor(colors.orange)
                term.write("~")
            else
                term.setTextColor(colors.red)
                term.write("!")
            end
            
            term.setTextColor(colors.white)
            term.write(" " .. Utils.truncate(item.displayName or item.name, 25))
            term.setCursorPos(32, y)
            term.setTextColor(colors.cyan)
            term.write(Utils.formatNumber(current) .. "/" .. Utils.formatNumber(item.amount))
            
            term.setBackgroundColor(colors.black)
            y = y + 1
        end
        
        term.setCursorPos(2, 18)
        term.setTextColor(colors.gray)
        term.write("[A]dd [E]dit [D]elete [C]raft Now")
        term.setCursorPos(2, 19)
        term.write("[Q]Back [T]oggle [S]ave")
        
        local event, key = os.pullEvent()
        if event == "key" then
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
                -- Add new item
                showAddStockItem()
                items = stockKeeper:getItems()
            elseif key == keys.e and #items > 0 then
                -- Edit selected item
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
                local current = bridge:getItemAmount(item.name)
                local needed = item.amount - current
                if needed > 0 then
                    bridge:craftItem(item.name, needed)
                end
            elseif key == keys.s then
                stockKeeper:save()
            end
        end
    end
end

-- Add stock item dialog
local function showAddStockItem()
    local searchTerm = ""
    local results = {}
    local selectedResult = 1
    local amount = 64
    local phase = "search" -- search, amount
    
    while true do
        GUI.clear()
        GUI.drawHeader("Add Stock Item")
        
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
            term.write("[Q] Cancel | [ENTER] Select | UP/DOWN Navigate")
            
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
            term.write(Utils.formatNumber(item.amount))
            
            term.setCursorPos(2, 8)
            term.setTextColor(colors.yellow)
            term.write("Target amount: ")
            term.setTextColor(colors.white)
            term.write(tostring(amount) .. "_")
            
            term.setCursorPos(2, 10)
            term.setTextColor(colors.gray)
            term.write("+/- to adjust by 1")
            term.setCursorPos(2, 11)
            term.write("PgUp/PgDn to adjust by 64")
            
            term.setCursorPos(2, 19)
            term.setTextColor(colors.gray)
            term.write("[Q] Back | [ENTER] Confirm")
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
                        results = bridge:findItem(searchTerm)
                    else
                        results = {}
                    end
                elseif key == keys.up then
                    selectedResult = math.max(1, selectedResult - 1)
                elseif key == keys.down then
                    selectedResult = math.min(#results, selectedResult + 1)
                elseif key == keys.enter and #results > 0 then
                    phase = "amount"
                    amount = results[selectedResult].amount > 0 and results[selectedResult].amount or 64
                end
            else -- amount phase
                if key == keys.up or key == keys.equals then
                    amount = amount + 1
                elseif key == keys.down or key == keys.minus then
                    amount = math.max(1, amount - 1)
                elseif key == keys.pageUp then
                    amount = amount + 64
                elseif key == keys.pageDown then
                    amount = math.max(1, amount - 64)
                elseif key == keys.backspace then
                    amount = math.floor(amount / 10)
                    if amount < 1 then amount = 1 end
                elseif key == keys.enter then
                    local item = results[selectedResult]
                    stockKeeper:addItem(item.name, amount, item.displayName)
                    return
                end
            end
        elseif event == "char" and phase == "search" then
            searchTerm = searchTerm .. key
            selectedResult = 1
            results = bridge:findItem(searchTerm)
        elseif event == "char" and phase == "amount" then
            local digit = tonumber(key)
            if digit then
                amount = amount * 10 + digit
                if amount > 999999 then amount = 999999 end
            end
        end
    end
end

-- Edit stock item dialog
local function showEditStockItem(item)
    local amount = item.amount
    
    while true do
        GUI.clear()
        GUI.drawHeader("Edit Stock Item")
        
        term.setCursorPos(2, 4)
        term.setTextColor(colors.yellow)
        term.write("Item: ")
        term.setTextColor(colors.cyan)
        term.write(item.displayName or item.name)
        
        term.setCursorPos(2, 6)
        term.setTextColor(colors.yellow)
        term.write("Current target: ")
        term.setTextColor(colors.white)
        term.write(tostring(item.amount))
        
        term.setCursorPos(2, 8)
        term.setTextColor(colors.yellow)
        term.write("New target: ")
        term.setTextColor(colors.white)
        term.write(tostring(amount) .. "_")
        
        term.setCursorPos(2, 10)
        term.setTextColor(colors.gray)
        term.write("+/- to adjust by 1")
        term.setCursorPos(2, 11)
        term.write("PgUp/PgDn to adjust by 64")
        
        term.setCursorPos(2, 19)
        term.setTextColor(colors.gray)
        term.write("[Q] Cancel | [ENTER] Save")
        
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.q or key == keys.backspace then
                return
            elseif key == keys.up or key == keys.equals then
                amount = amount + 1
            elseif key == keys.down or key == keys.minus then
                amount = math.max(1, amount - 1)
            elseif key == keys.pageUp then
                amount = amount + 64
            elseif key == keys.pageDown then
                amount = math.max(1, amount - 64)
            elseif key == keys.backspace then
                amount = math.floor(amount / 10)
                if amount < 1 then amount = 1 end
            elseif key == keys.enter then
                stockKeeper:updateItem(item.name, amount)
                return
            end
        elseif event == "char" then
            local digit = tonumber(key)
            if digit then
                amount = amount * 10 + digit
                if amount > 999999 then amount = 999999 end
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
                term.write(Utils.truncate(task.name or "Unknown", 25))
                
                term.setCursorPos(30, y)
                term.setTextColor(colors.white)
                term.write(Utils.formatNumber(task.amount or 0))
                
                -- Progress if available
                if task.progress then
                    term.setCursorPos(40, y)
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
local function showNewCraft()
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
            totalItems = totalItems + item.amount
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
            term.write(Utils.truncate(fluids[i].displayName or fluids[i].name, 20))
            term.setTextColor(colors.white)
            term.write(": " .. Utils.formatNumber(fluids[i].amount) .. " mB")
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

-- Background stock keeper task
local function stockKeeperTask()
    while running do
        if stockKeeper and stockKeeper:isEnabled() then
            stockKeeper:check()
        end
        sleep(config.craftDelay or 10)
    end
end

-- Background monitor update task
local function monitorTask()
    while running do
        if monitor and monitor:hasMonitor() and config.useMonitor then
            monitor:update()
        end
        sleep(config.refreshRate or 5)
    end
end

-- Main menu loop
local function mainMenu()
    local selected = 1
    
    while running do
        drawMainMenu(selected)
        
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = #menuOptions end
        elseif key == keys.down then
            selected = selected + 1
            if selected > #menuOptions then selected = 1 end
        elseif key == keys.enter then
            local action = menuOptions[selected].action
            if action == "exit" then
                running = false
            elseif action == "dashboard" then
                showDashboard()
            elseif action == "search" then
                showItemSearch()
            elseif action == "stockkeeper" then
                showStockKeeper()
            elseif action == "crafting" then
                showCraftingQueue()
            elseif action == "stats" then
                showSystemStats()
            elseif action == "settings" then
                showSettings()
            end
        elseif key == keys.q then
            running = false
        end
    end
end

-- Main entry point
local function main()
    if not init() then
        return
    end
    
    -- Run main menu and background tasks in parallel
    parallel.waitForAny(
        mainMenu,
        stockKeeperTask,
        monitorTask
    )
    
    -- Cleanup
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("RS Manager shutdown complete.")
end

-- Run
main()
