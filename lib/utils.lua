-- Utility functions for RS Manager

local Utils = {}

function Utils.printC(text, color)
    local old = term.getTextColor()
    term.setTextColor(color or colors.white)
    print(text)
    term.setTextColor(old)
end

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

function Utils.padRight(str, len)
    str = str or ""
    if #str >= len then return str:sub(1, len) end
    return str .. string.rep(" ", len - #str)
end

function Utils.padLeft(str, len)
    str = str or ""
    if #str >= len then return str:sub(1, len) end
    return string.rep(" ", len - #str) .. str
end

function Utils.center(str, len)
    str = str or ""
    if #str >= len then return str:sub(1, len) end
    local pad = len - #str
    local left = math.floor(pad / 2)
    local right = pad - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

function Utils.split(str, sep)
    local result = {}
    local pattern = "([^" .. sep .. "]+)"
    for match in str:gmatch(pattern) do
        table.insert(result, match)
    end
    return result
end

function Utils.trim(str)
    return str:match("^%s*(.-)%s*$")
end

function Utils.startsWith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function Utils.endsWith(str, suffix)
    return str:sub(-#suffix) == suffix
end

function Utils.contains(str, substr)
    return str:find(substr, 1, true) ~= nil
end

function Utils.tableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

function Utils.tableFind(tbl, predicate)
    for i, v in ipairs(tbl) do
        if predicate(v) then
            return i, v
        end
    end
    return nil
end

function Utils.tableFilter(tbl, predicate)
    local result = {}
    for _, v in ipairs(tbl) do
        if predicate(v) then
            table.insert(result, v)
        end
    end
    return result
end

function Utils.tableMap(tbl, func)
    local result = {}
    for i, v in ipairs(tbl) do
        result[i] = func(v, i)
    end
    return result
end

function Utils.deepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = Utils.deepCopy(v)
    end
    return copy
end

function Utils.merge(base, override)
    local result = Utils.deepCopy(base)
    for k, v in pairs(override) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = Utils.merge(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

function Utils.fileExists(path)
    return fs.exists(path)
end

function Utils.readFile(path)
    if not fs.exists(path) then return nil end
    local file = fs.open(path, "r")
    if not file then return nil end
    local content = file.readAll()
    file.close()
    return content
end

function Utils.writeFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local file = fs.open(path, "w")
    if not file then return false end
    file.write(content)
    file.close()
    return true
end

function Utils.loadTable(path)
    local content = Utils.readFile(path)
    if not content then return nil end
    return textutils.unserialise(content)
end

function Utils.saveTable(path, tbl)
    return Utils.writeFile(path, textutils.serialise(tbl))
end

function Utils.getItemDisplayName(item)
    if item.displayName then
        return item.displayName
    end
    -- Convert minecraft:iron_ingot to Iron Ingot
    local name = item.name
    name = name:gsub("^[^:]+:", "") -- Remove mod prefix
    name = name:gsub("_", " ")       -- Replace underscores
    name = name:gsub("(%a)([%w]*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return name
end

function Utils.log(message, level)
    level = level or "INFO"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logLine = string.format("[%s] [%s] %s\n", timestamp, level, message)
    
    local logFile = fs.open("/rsmanager/logs/rsmanager.log", "a")
    if logFile then
        logFile.write(logLine)
        logFile.close()
    end
end

function Utils.clearLog()
    if fs.exists("/rsmanager/logs/rsmanager.log") then
        fs.delete("/rsmanager/logs/rsmanager.log")
    end
end

return Utils
