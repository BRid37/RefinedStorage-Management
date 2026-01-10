-- Storage info view for RS Manager
-- Shows what's using disk space and allows cleanup

local function showStorageInfo(storage, GUI, Utils)
    while true do
        GUI.clear()
        GUI.drawHeader("Storage Information")
        
        local stats = storage:getStats()
        
        -- Summary
        term.setCursorPos(2, 4)
        term.setTextColor(colors.yellow)
        term.write("Total Storage Used: ")
        term.setTextColor(colors.white)
        term.write(storage.formatBytes(stats.totalSize))
        
        -- Warnings
        if #stats.warnings > 0 then
            term.setCursorPos(2, 5)
            term.setTextColor(colors.red)
            term.write("Warnings: " .. #stats.warnings)
            
            local y = 7
            for i, warning in ipairs(stats.warnings) do
                if y > 18 then break end
                term.setCursorPos(4, y)
                term.setTextColor(colors.orange)
                term.write("! ")
                term.setTextColor(colors.white)
                term.write(warning.message)
                y = y + 1
            end
            y = y + 1
        else
            term.setCursorPos(2, 5)
            term.setTextColor(colors.green)
            term.write("No warnings")
        end
        
        -- Files by size
        local startY = #stats.warnings > 0 and (7 + math.min(#stats.warnings, 12) + 1) or 7
        if startY < 18 then
            term.setCursorPos(2, startY)
            term.setTextColor(colors.cyan)
            term.write("=== Files by Size ===")
            startY = startY + 1
            
            for i, file in ipairs(stats.files) do
                if startY > 16 then break end
                term.setCursorPos(2, startY)
                
                -- Color by category
                local color = colors.white
                if file.category == "config" then
                    color = colors.yellow
                elseif file.category == "logs" then
                    color = colors.gray
                elseif file.category == "data" then
                    color = colors.lightBlue
                end
                
                term.setTextColor(color)
                local name = file.name
                if #name > 20 then name = name:sub(1, 17) .. "..." end
                term.write(string.format("%-23s", name))
                
                term.setTextColor(colors.white)
                term.write(string.format("%10s", storage.formatBytes(file.size)))
                
                if file.items and file.items > 0 then
                    term.setTextColor(colors.gray)
                    term.write(" (" .. file.items .. " items)")
                end
                
                startY = startY + 1
            end
        end
        
        -- Footer
        term.setCursorPos(2, 19)
        term.setTextColor(colors.gray)
        term.write("[C] Clean Logs | [R] Refresh | [Backspace] Back")
        
        local event, key = os.pullEvent("key")
        if key == keys.backspace then
            return
        elseif key == keys.c then
            -- Clean logs
            term.setCursorPos(2, 18)
            term.setTextColor(colors.yellow)
            term.write("Cleaning old log files...                    ")
            local deleted = storage:cleanLogs(7)
            term.setCursorPos(2, 18)
            term.setTextColor(colors.green)
            term.write("Cleaned " .. deleted .. " log files. Press any key...")
            os.pullEvent("key")
        elseif key == keys.r then
            -- Refresh handled by loop
        end
    end
end

return showStorageInfo
