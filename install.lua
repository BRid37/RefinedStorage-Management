-- RS Manager Installer v1.0
-- Refined Storage Management System for CC:Tweaked + Advanced Peripherals
-- Run: pastebin run <CODE>
-- 
-- Compatible with:
--   CC:Tweaked 1.116.2+
--   Advanced Peripherals 0.7.57b+
--   Minecraft 1.21.1

local GITHUB_USER = "BRid37"  -- Change this to your GitHub username
local GITHUB_REPO = "RefinedStorage-Management"
local GITHUB_BRANCH = "main"
local GITHUB_RAW = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"
local INSTALL_DIR = "/rsmanager"

local files = {
    "rsmanager.lua",
    "lib/config.lua",
    "lib/rsbridge.lua",
    "lib/stockkeeper.lua",
    "lib/monitor.lua",
    "lib/gui.lua",
    "lib/utils.lua",
    "lib/updater.lua",
    "version.txt",
}

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function printC(text, color)
    local old = term.getTextColor()
    term.setTextColor(color or colors.white)
    print(text)
    term.setTextColor(old)
end

local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local file = fs.open(path, "w")
    if file then
        file.write(content)
        file.close()
        return true
    end
    return false
end

local function downloadFile(url, path)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        return writeFile(path, content)
    end
    return false
end

-- Embedded default configs
local defaultSettings = [[{
    refreshRate = 5,
    craftDelay = 10,
    lowStockPercent = 50,
    useMonitor = true,
    monitorScale = 1,
    stockKeeperEnabled = true,
    maxCraftingJobs = 5,
}]]

local defaultStocklist = [[{
    items = {},
    enabled = true,
}]]

local function install()
    clear()
    printC("========================================", colors.cyan)
    printC("     RS Manager Installer v1.0", colors.cyan)
    printC("  Refined Storage Management System", colors.cyan)
    printC("========================================", colors.cyan)
    print()
    
    -- Check HTTP
    if not http then
        printC("[ERROR] HTTP API is disabled!", colors.red)
        printC("Enable it in ComputerCraft config.", colors.gray)
        return
    end
    
    -- Check for RS Bridge
    printC("Checking for RS Bridge...", colors.yellow)
    local bridge = peripheral.find("rsBridge")
    if not bridge then
        printC("[!] No RS Bridge found!", colors.orange)
        printC("    Connect an RS Bridge for full functionality.", colors.gray)
        print()
        printC("Continue anyway? (y/n)", colors.yellow)
        local input = read()
        if input:lower() ~= "y" then
            return
        end
    else
        printC("[OK] RS Bridge detected!", colors.green)
    end
    print()
    
    -- Check for existing installation
    if fs.exists(INSTALL_DIR) then
        printC("Existing installation found.", colors.orange)
        printC("Overwrite? (y/n)", colors.yellow)
        local input = read()
        if input:lower() ~= "y" then
            printC("Installation cancelled.", colors.red)
            return
        end
        fs.delete(INSTALL_DIR)
    end
    
    -- Create directories
    printC("Creating directories...", colors.yellow)
    fs.makeDir(INSTALL_DIR)
    fs.makeDir(INSTALL_DIR .. "/lib")
    fs.makeDir(INSTALL_DIR .. "/config")
    fs.makeDir(INSTALL_DIR .. "/logs")
    printC("[OK] Directories created", colors.green)
    print()
    
    -- Download files from GitHub
    printC("Downloading from GitHub...", colors.yellow)
    local allSuccess = true
    
    for _, file in ipairs(files) do
        local url = GITHUB_RAW .. file
        local path = INSTALL_DIR .. "/" .. file
        write("  " .. file .. "... ")
        
        if downloadFile(url, path) then
            printC("OK", colors.green)
        else
            printC("FAILED", colors.red)
            allSuccess = false
        end
    end
    print()
    
    if not allSuccess then
        printC("[!] Some downloads failed.", colors.red)
        printC("Check your GitHub settings or internet connection.", colors.gray)
        printC("You may need to update GITHUB_USER in the installer.", colors.gray)
        print()
        printC("Continue with partial install? (y/n)", colors.yellow)
        local input = read()
        if input:lower() ~= "y" then
            fs.delete(INSTALL_DIR)
            return
        end
    end
    
    -- Create default config files
    printC("Creating configuration files...", colors.yellow)
    writeFile(INSTALL_DIR .. "/config/settings.lua", defaultSettings)
    writeFile(INSTALL_DIR .. "/config/stocklist.lua", defaultStocklist)
    printC("[OK] Config files created", colors.green)
    print()
    
    -- Create startup file
    printC("Setting up auto-start...", colors.yellow)
    if not fs.exists("/startup") then
        fs.makeDir("/startup")
    end
    
    local startupContent = [[-- RS Manager Auto-start
-- Delete this file to disable auto-start
shell.run("/rsmanager/rsmanager.lua")
]]
    writeFile("/startup/rsmanager.lua", startupContent)
    printC("[OK] Auto-start configured", colors.green)
    print()
    
    -- Set up alias
    shell.setAlias("rsmanager", INSTALL_DIR .. "/rsmanager.lua")
    
    -- Complete
    printC("========================================", colors.green)
    printC("     Installation Complete!", colors.green)
    printC("========================================", colors.green)
    print()
    printC("Commands:", colors.yellow)
    printC("  rsmanager    - Start the program", colors.white)
    printC("  reboot       - Auto-start on boot", colors.white)
    print()
    printC("Features:", colors.cyan)
    printC("  - Dashboard with system overview", colors.lightGray)
    printC("  - Item search and browsing", colors.lightGray)
    printC("  - Stock Keeper (auto-craft to maintain stock)", colors.lightGray)
    printC("  - Crafting queue management", colors.lightGray)
    printC("  - External monitor support", colors.lightGray)
    printC("  - Energy and storage monitoring", colors.lightGray)
    print()
    printC("Press any key to start RS Manager...", colors.yellow)
    os.pullEvent("key")
    
    shell.run(INSTALL_DIR .. "/rsmanager.lua")
end

-- Run installer
install()
