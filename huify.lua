--[[

Huify

Модуль который хуефицирует текст, заменяя первые три буквы каждого слова

by https://t.me/aye_ya, https://t.me/Svatosh, https://t.me/wavecat

--]]

require "iutf8"

local pattern = luajava.bindClass("java.util.regex.Pattern"):compile("([еуаоэяию])")

local replacements = { "хуе", "хуи", "хую", "хуя" }

local function huify(input, query)
    local result = ""
    for word in string.gmatch(query:replaceExpression(""), "(%S+)") do
        if utf8.len(word) > 4 then
            local matcher = pattern:matcher(utf8.sub(word, 2, 3))
            local replacement = matcher:find() and math.random(1, 2) or math.random(3, 4)
            result = result .. replacements[replacement] .. utf8.sub(word, 3, utf8.len(word)) .. " "
        else
            result = result .. word .. " "
        end
    end
    inline:setText(input, result)
end

return function(module)
    module:registerCommand("huify", huify, "Makes text dick-like")
end
