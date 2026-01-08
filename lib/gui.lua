-- GUI module for RS Manager
-- Terminal-based UI helpers

local GUI = {}

local width, height = term.getSize()

function GUI.clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    width, height = term.getSize()
end

function GUI.getSize()
    return term.getSize()
end

function GUI.drawHeader(title)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    
    local titleX = math.floor((width - #title) / 2) + 1
    term.setCursorPos(titleX, 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 2)
    term.setTextColor(colors.gray)
    term.write(string.rep("-", width))
end

function GUI.drawFooter(text)
    term.setCursorPos(1, height)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    term.clearLine()
    term.write(" " .. text)
    term.setBackgroundColor(colors.black)
end

function GUI.drawBox(x, y, w, h, title, borderColor)
    borderColor = borderColor or colors.gray
    
    term.setTextColor(borderColor)
    
    -- Top border
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", w - 2) .. "+")
    
    -- Title if provided
    if title then
        term.setCursorPos(x + 2, y)
        term.setTextColor(colors.white)
        term.write(" " .. title .. " ")
        term.setTextColor(borderColor)
    end
    
    -- Sides
    for i = 1, h - 2 do
        term.setCursorPos(x, y + i)
        term.write("|")
        term.setCursorPos(x + w - 1, y + i)
        term.write("|")
    end
    
    -- Bottom border
    term.setCursorPos(x, y + h - 1)
    term.write("+" .. string.rep("-", w - 2) .. "+")
    
    term.setTextColor(colors.white)
end

function GUI.drawProgressBar(x, y, w, percent, color)
    color = color or colors.green
    percent = math.max(0, math.min(100, percent))
    
    local filled = math.floor((w * percent) / 100)
    
    term.setCursorPos(x, y)
    term.setBackgroundColor(color)
    term.write(string.rep(" ", filled))
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", w - filled))
    term.setBackgroundColor(colors.black)
end

function GUI.drawButton(x, y, text, selected, color)
    term.setCursorPos(x, y)
    
    if selected then
        term.setBackgroundColor(color or colors.blue)
        term.setTextColor(colors.white)
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.lightGray)
    end
    
    term.write(" " .. text .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function GUI.drawMenu(x, y, options, selected)
    for i, option in ipairs(options) do
        term.setCursorPos(x, y + i - 1)
        
        if i == selected then
            term.setBackgroundColor(option.color or colors.blue)
            term.setTextColor(colors.white)
            term.write(" > " .. option.name .. " ")
        else
            term.setBackgroundColor(colors.black)
            term.setTextColor(option.color or colors.white)
            term.write("   " .. option.name .. " ")
        end
    end
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function GUI.showMessage(message, color, duration)
    duration = duration or 2
    
    local msgWidth = #message + 4
    local msgX = math.floor((width - msgWidth) / 2)
    local msgY = math.floor(height / 2)
    
    -- Save area
    term.setCursorPos(msgX, msgY - 1)
    term.setBackgroundColor(color or colors.blue)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", msgWidth))
    
    term.setCursorPos(msgX, msgY)
    term.write("  " .. message .. "  ")
    
    term.setCursorPos(msgX, msgY + 1)
    term.write(string.rep(" ", msgWidth))
    
    term.setBackgroundColor(colors.black)
    
    sleep(duration)
end

function GUI.confirm(message)
    local msgWidth = math.max(#message + 4, 20)
    local msgX = math.floor((width - msgWidth) / 2)
    local msgY = math.floor(height / 2) - 2
    
    -- Draw dialog box
    GUI.drawBox(msgX, msgY, msgWidth, 5, nil, colors.yellow)
    
    -- Message
    term.setCursorPos(msgX + 2, msgY + 1)
    term.setTextColor(colors.white)
    term.write(message)
    
    -- Buttons
    local btnY = msgY + 3
    local yesX = msgX + 3
    local noX = msgX + msgWidth - 7
    
    local selected = 1
    
    while true do
        GUI.drawButton(yesX, btnY, "Yes", selected == 1, colors.green)
        GUI.drawButton(noX, btnY, "No", selected == 2, colors.red)
        
        local event, key = os.pullEvent("key")
        if key == keys.left or key == keys.right or key == keys.tab then
            selected = selected == 1 and 2 or 1
        elseif key == keys.enter then
            return selected == 1
        elseif key == keys.y then
            return true
        elseif key == keys.n or key == keys.escape then
            return false
        end
    end
end

function GUI.input(prompt, default)
    local msgWidth = math.max(#prompt + 4, 30)
    local msgX = math.floor((width - msgWidth) / 2)
    local msgY = math.floor(height / 2) - 2
    
    -- Draw dialog box
    GUI.drawBox(msgX, msgY, msgWidth, 5, nil, colors.cyan)
    
    -- Prompt
    term.setCursorPos(msgX + 2, msgY + 1)
    term.setTextColor(colors.yellow)
    term.write(prompt)
    
    -- Input field
    term.setCursorPos(msgX + 2, msgY + 3)
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", msgWidth - 4))
    term.setCursorPos(msgX + 2, msgY + 3)
    term.setTextColor(colors.white)
    
    local input = default or ""
    term.write(input)
    term.setCursorBlink(true)
    
    while true do
        local event, key = os.pullEvent()
        if event == "key" then
            if key == keys.enter then
                term.setCursorBlink(false)
                term.setBackgroundColor(colors.black)
                return input
            elseif key == keys.escape then
                term.setCursorBlink(false)
                term.setBackgroundColor(colors.black)
                return nil
            elseif key == keys.backspace then
                input = input:sub(1, -2)
                term.setCursorPos(msgX + 2, msgY + 3)
                term.write(input .. " ")
                term.setCursorPos(msgX + 2 + #input, msgY + 3)
            end
        elseif event == "char" then
            if #input < msgWidth - 6 then
                input = input .. key
                term.write(key)
            end
        end
    end
end

function GUI.selectList(title, items, displayFunc)
    local selected = 1
    local scroll = 0
    local maxDisplay = height - 6
    
    displayFunc = displayFunc or function(item) return tostring(item) end
    
    while true do
        GUI.clear()
        GUI.drawHeader(title)
        
        local y = 4
        for i = scroll + 1, math.min(scroll + maxDisplay, #items) do
            term.setCursorPos(2, y)
            
            if i == selected then
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
                term.write(" > ")
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.lightGray)
                term.write("   ")
            end
            
            term.write(displayFunc(items[i]))
            term.setBackgroundColor(colors.black)
            y = y + 1
        end
        
        term.setCursorPos(2, height - 1)
        term.setTextColor(colors.gray)
        term.write("UP/DOWN: Navigate | ENTER: Select | ESC: Cancel")
        
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = math.max(1, selected - 1)
            if selected <= scroll then
                scroll = math.max(0, scroll - 1)
            end
        elseif key == keys.down then
            selected = math.min(#items, selected + 1)
            if selected > scroll + maxDisplay then
                scroll = scroll + 1
            end
        elseif key == keys.enter then
            return selected, items[selected]
        elseif key == keys.escape then
            return nil
        end
    end
end

function GUI.notification(message, color, y)
    y = y or 2
    color = color or colors.yellow
    
    term.setCursorPos(1, y)
    term.setBackgroundColor(color)
    term.setTextColor(colors.black)
    term.clearLine()
    
    local x = math.floor((width - #message) / 2) + 1
    term.setCursorPos(x, y)
    term.write(message)
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

return GUI
