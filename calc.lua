require "windows"
require "iutf8"

if not windows:isSupported() then
    inline:toast "The module is not supported on this version of Android"
    return
end

local preferences = inline:getDefaultSharedPreferences()

local Pattern = require "java.util.regex.Pattern"
local pattern = Pattern:compile("(?<!\\S)([.,0-9a-zA-Z_+\\-*/()^%<>\\s≥≤≠√π!]+)=$", Pattern.MULTILINE)

local DEFAULT_WINDOW_OFFSET = 20
local DEFAULT_WINDOW_TIMEOUT = 5000

local env = {
    sin = math.sin, cos = math.cos, tan = math.tan,
    asin = math.asin, acos = math.acos, atan = math.atan,
    sinh = math.sinh, cosh = math.cosh, tanh = math.tanh,
    sqrt = math.sqrt, abs = math.abs,
    log = math.log, ln = math.log, log10 = math.log10,
    exp = math.exp,
    floor = math.floor, ceil = math.ceil,
    min = math.min, max = math.max,
    rad = math.rad, deg = math.deg,
    pi = math.pi, e = math.exp(1),
    huge = math.huge, inf = math.huge,
}

local function factorial(n)
    if n < 0 or n ~= math.floor(n) then
        return 0 / 0
    end
    if n <= 1 then
        return 1
    end
    local r = 1
    for i = 2, n do
        r = r * i
    end
    return r
end

local function preprocess(expr)
    expr = expr:gsub(",", ".")
    expr = expr:gsub("≥", ">=")
    expr = expr:gsub("≤", "<=")
    expr = expr:gsub("≠", "~=")
    expr = expr:gsub("π", "pi")
    expr = expr:gsub("√%(", "sqrt(")
    expr = expr:gsub("√([%d%.]+)", "sqrt(%1)")
    expr = expr:gsub("(%d+)!", "fact(%1)")
    return expr
end

local function formatResult(value)
    if type(value) == "boolean" then
        return tostring(value)
    end

    if type(value) ~= "number" then
        return tostring(value)
    end

    if value ~= value then
        return "NaN"
    end
    if value == math.huge then
        return "∞"
    end
    if value == -math.huge then
        return "-∞"
    end

    if value == math.floor(value) and math.abs(value) < 1e15 then
        return string.format("%.0f", value)
    end

    local s = string.format("%.10g", value)
    return s
end

local window
local timer = inline:getTimer()

local function pasteFromClipboard(input, text)
    local clipboardService = inline:getSystemService(inline.CLIPBOARD_SERVICE)
    local ClipData = require "android.content.ClipData"
    local clip = ClipData:newPlainText("calc", text)
    clipboardService:setPrimaryClip(clip)
    inline:paste(input)
end

local function showWindow(input, result)
    local timerTask = inline:timerTask(function()
        window.close()
    end)

    local button

    local floatingWindow = windows.createAligned(input, {
        noBackground = true,
        offsetY = preferences:getInt("calc_window_offset", DEFAULT_WINDOW_OFFSET),
        onClose = function()
            window = nil
            timerTask:cancel()
        end
    }, function(ui)
        button = ui.button(result, function()
            if preferences:getBoolean("calc_use_clipboard_paste", false) then
                pasteFromClipboard(input, result)
            elseif not windows.insertText(button:getText()) then
                return inline:toast "Please focus on the desired input"
            end

            window.close()
        end)

        return { button }
    end)

    timer:schedule(timerTask, preferences:getInt("calc_window_timeout", DEFAULT_WINDOW_TIMEOUT))

    return {
        close = function()
            floatingWindow:close()
        end,
        update = function(text)
            button:setText(text)
        end
    }
end

local function updateWindow(input, result)
    if window then
        window.update(result)
    else
        window = showWindow(input, result)
    end
end

local function looksLikeMath(expr)
    return expr:find("%d") ~= nil
            or expr:find("[+%-%*/%%^()]") ~= nil
            or expr:find("√") ~= nil
            or expr:find("π") ~= nil
end

local function evaluate(expression)
    env.fact = factorial

    local loaded, err = load("return " .. expression, "calc", "t", env)

    if not loaded then
        return nil
    end

    local status, calculated = pcall(loaded)

    if not status then
        return nil
    end

    return calculated
end

local function watcher(input)
    local text = inline:getText(input)

    if #text == 0 then
        return
    end

    local selectionEnd = input:getTextSelectionEnd()

    if selectionEnd == -1 then
        selectionEnd = nil
    end

    text = utf8.sub(text, 0, selectionEnd)

    local matcher = pattern:matcher(text)
    local expression

    while matcher:find() do
        expression = matcher:group(1)
    end

    if expression and looksLikeMath(expression) then
        local usedComma = expression:find(",") ~= nil
        expression = preprocess(expression)

        local calculated = evaluate(expression)

        if calculated ~= nil then
            local result = formatResult(calculated)

            if usedComma then
                result = result:gsub("%.", ",")
            end

            if preferences:getBoolean("calc_auto_insert", false) then
                if preferences:getBoolean("calc_use_clipboard_paste", false) then
                    pasteFromClipboard(input, result)
                else
                    return inline:insertText(input, result)
                end
            else
                return updateWindow(input, tostring(result))
            end
        end
    end

    if window then
        window.close()
    end
end

return function(module)
    module:setCategory "Calc"

    module:registerPreferences(function(prefs)
        return {
            prefs.switch("calc", "Enabled")
                 :setDefault(true)
                 :setListener(function(isChecked)
                if isChecked then
                    module:registerWatcher(watcher)
                else
                    module:unregisterWatcher(watcher)
                end
            end),
            prefs.spacer(12),
            prefs.card {
                prefs.text "Insertion":bold():size(16),
                prefs.spacer(8),
                prefs.text "Using the clipboard preserves text formatting in applications like Telegram.":size(12),
                prefs.spacer(4),
                prefs.switch("calc_use_clipboard_paste", "Use clipboard to paste"),
                prefs.spacer(4),
                prefs.switch("calc_auto_insert", "Auto insert"),
            },
            prefs.spacer(12),
            prefs.card {
                prefs.text "Window":bold():size(16),
                prefs.spacer(8),
                prefs.textInput("calc_window_timeout", "Timeout (ms)")
                     :setDefault(DEFAULT_WINDOW_TIMEOUT)
                     :useInt()
                     :setInputType { "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" },
                prefs.spacer(8),
                prefs.textInput("calc_window_offset", "Offset (dp)")
                     :setDefault(DEFAULT_WINDOW_OFFSET)
                     :useInt()
                     :setInputType { "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" },
            },
        }
    end)

    if preferences:getBoolean("calc", true) then
        module:registerWatcher(watcher)
    end

    windows.supportInsert()
end
