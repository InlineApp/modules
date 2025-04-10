--[[

Filter

Автоматически цензурирует все матные слова

filterctl on -- включить фильтр
filterctl -- выключить

--]]

require "iutf8"
require "utils"

local preferences = inline:getDefaultSharedPreferences()

local pattern = luajava.bindClass("java.util.regex.Pattern"):compile("(?iu)\\b(([уyu]|[нзnz3][аa]|(хитро|не)?[вvwb][зz3]?[ыьъi]|[сsc][ьъ']|(и|[рpr][аa4])[зсzs]ъ?|([оo0][тбtb6]|[пp][оo0][дd9])[ьъ']?|(.\B)+?[оаеиeo])?-?([еёe][бb6](?!о[рй])|и[пб][ае][тц]).*?|([нn][иеаaie]|([дпdp]|[вv][еe3][рpr][тt])[оo0]|[рpr][аa][зсzc3]|[з3z]?[аa]|с(ме)?|[оo0]([тt]|дно)?|апч)?-?[хxh][уuy]([яйиеёюuie]|ли(?!ган)).*?|([вvw][зы3z]|(три|два|четыре)жды|(н|[сc][уuy][кk])[аa])?-?[бb6][лl]([яy](?!(х|ш[кн]|мб)[ауеыио]).*?|[еэe][дтdt][ь']?)|([рp][аa][сзc3z]|[знzn][аa]|[соsc]|[вv][ыi]?|[пp]([еe][рpr][еe]|[рrp][оиioеe]|[оo0][дd])|и[зс]ъ?|[аоao][тt])?[пpn][иеёieu][зz3][дd9].*?|([зz3][аa])?[пp][иеieu][дd][аоеaoe]?[рrp](ну.*?|[оаoa][мm]|([аa][сcs])?([иiu]([лl][иiu])?[нщктлtlsn]ь?)?|([оo](ч[еиei])?|[аa][сcs])?[кk]([оo]й)?|[юu][гg])[ауеыauyei]?|[мm][аa][нnh][дd]([ауеыayueiи]([лl]([иi][сзc3щ])?[ауеыauyei])?|[оo][йi]|[аоao][вvwb][оo](ш|sh)[ь']?([e]?[кk][ауеayue])?|юк(ов|[ауи])?)|[мm][уuy][дd6]([яyаиоaiuo0].*?|[еe]?[нhn]([ьюия'uiya]|ей))|мля([тд]ь)?|лять|([нз]а|по)х|м[ао]л[ао]фь([яию]|[её]й))\\b")

local enabled = preferences:getBoolean("filter", true)

local function filterctl(_, query)
    enabled = query:getArgs() == "on"
    preferences:edit():putBoolean("filter", enabled):apply()
    query:answer(enabled and "On" or "Off")
end

local function watcher(input)
    if not enabled then
        return
    end
    local text = input:getText()
    if text == nil or text.toString == nil then
        return
    end
    local matcher = pattern:matcher(text)
    local result = text:toString()
    while matcher:find() do
        result = utf8.sub(result, 0, matcher:start()) ..
                string.rep("*", utf8.len(matcher:group())) .. utf8.sub(result, matcher["end"](matcher), utf8.len(result))
    end
    if result ~= text:toString() then
        inline:setText(input, result)
    end
end

return function(module)
    module:registerCommand("filterctl", filterctl, "Control interface")
    module:registerWatcher(watcher)
end
