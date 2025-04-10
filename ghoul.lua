--[[

Ghoul

Делает отсчет от 1000 до 7

by https://t.me/billy_fresko, https://t.me/wavecat

--]]

require "utils"

local preferences = inline:getDefaultSharedPreferences()

local context
local contextQuery

local speed
local counter
local result

function worker()
    if counter > 7 then
        result = result .. counter .. " - 7 = " .. (counter - 7) .. "\n"
        contextQuery:answer(result)
        counter = counter - 7
        inline:getTimer():schedule(inline:timerTask(worker), speed)
    end
end

local function watcher(input)
    local text = input:getText()
    if text ~= nil and text.toString ~= nil then
        text = text:toString()
        if text:sub(#text) == "." then
            counter = 0
            context:unregisterWatcher(watcher)
        end
    end
end

local function ghoul(_, query)
    if query:getArgs() ~= "" then
        preferences:edit():putInt("ghoul", tonumber(query:getArgs())):apply()
        query:answer("Speed changed")
    else
        contextQuery = query
        context:registerWatcher(watcher)

        inline:toast "Counting started, to stop press «.»"

        speed = preferences:getInt("ghoul", 100)
        counter = 1000
        result = ""

        inline:getTimer():schedule(inline:timerTask(worker), speed)
    end
end

return function(module)
    module:setCategory "Ghoul"
    module:registerCommand("ghoul", ghoul, "Starts the countdown")

    context = module
end
