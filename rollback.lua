--[[

Rollback

Модуль для поиска фраз написанных за день

Представляет из себя буфер который хранит написанный текст, максимум 750 изменений (в качестве оптимизации запись строки с конца записывается в последнее изменение или это создает новое событие)

{rollback текст} - открывает терминал для поиск по логу, принимает данные команды:

w - следующая фраза
s - предыдущая фраза
l - переход к концу
f - переход к началу
e - выход без выбора
r - выбор текущей фразы и выход
0..9 - изменение шага для команд w | s

--]]

local lastString
local results = {}
local cursor = 1
local offset = 1
local lastState = ""

local buffer = {}
local viewer = false

local function startsWith(text, start)
    return text:sub(1, #start) == start
end

local function shell(input)
    inline:setText(input, results[cursor] .. "\n" .. cursor .. " >")
end

local function watcher(input)
    local text = input:getText()
    if text == nil or text.toString == nil then
        return
    end
    text = text:toString()
    if viewer then
        local command = text:sub(#text)
        if command == "w" then
            cursor = cursor - offset
        elseif command == "s" then
            cursor = cursor + offset
        elseif command == "l" then
            cursor = #results
        elseif command == "f" then
            cursor = 1
        elseif tonumber(command) ~= nil then
            offset = tonumber(command)
            if offset == 0 then
                offset = 10
            end
        elseif command == "e" then
            viewer = false
            inline:setText(input, lastState)
        elseif command == "r" then
            viewer = false
            inline:setText(input, results[cursor])
        end
        if cursor > #results then
            cursor = 1
        elseif cursor < 1 then
            cursor = #results
        end
        if viewer then
            shell(input)
        end
    else
        if lastString ~= nil and startsWith(text, lastString) then
            text = text:sub(#lastString + 1, #text)
            lastString = lastString .. text
            buffer[#buffer] = buffer[#buffer] .. text
        else
            lastString = text
            buffer[#buffer + 1] = text
            if #buffer > 750 then
                table.remove(buffer, 1)
            end
        end
    end
end

local function rollback(input, query)
    table.remove(buffer, #buffer)
    results = {}
    for _, v in ipairs(buffer) do
        if query:getArgs() == "" or v:find(query:getArgs()) ~= nil then
            results[#results + 1] = v
        end
    end
    if #results == 0 then
        query:answer("Not found")
        return
    end
    viewer = true
    cursor = #results
    lastState = query:replaceExpression("")
    shell(input)
end

local function finder()
    if viewer then
        return function()
        end
    end
end

return function(module)
    module:registerWatcher(watcher)
    module:registerCommandFinder(finder)
    module:registerCommand("rollback", rollback)
end
