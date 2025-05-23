require "windows"
require "iutf8"

if not windows:isSupported() then
    inline:toast "The module is not supported on this version of Android"
    return
end

local preferences = inline:getDefaultSharedPreferences()

local Pattern = luajava.bindClass("java.util.regex.Pattern")
local pattern = Pattern:compile("(?<!\\S)([.,0-9+\\-*/()^<>\\s≥≤≠]+)=$", Pattern.MULTILINE)

local DEFAULT_WINDOW_OFFSET = 20
local DEFAULT_WINDOW_TIMEOUT = 7000

local window

local timer = inline:getTimer()

local function pasteFromClipboard(input, text)
    local clipboardService = inline:getSystemService(inline.CLIPBOARD_SERVICE)
    local ClipData = luajava.bindClass("android.content.ClipData")
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
            else
                windows.insertText(button:getText())
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

    if expression then
        local usedComma = expression:find(",") ~= nil

        expression = expression:gsub(",", ".")
        expression = expression:gsub("≥", ">=")
        expression = expression:gsub("≤", "<=")
        expression = expression:gsub("≠", "~=")

        local loaded = load("return " .. expression)

        if loaded then
            local status, calculated = pcall(loaded)

            if not status then
                return
            end

            local result = tostring(calculated)

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
            prefs.checkBox("calc", "Enabled")
                 :setDefault(true)
                 :setListener(function(isChecked)
                if isChecked then
                    module:registerWatcher(watcher)
                else
                    module:unregisterWatcher(watcher)
                end
            end),
            prefs.checkBox("calc_auto_insert", "Auto insert"),
            prefs.checkBox("calc_use_clipboard_paste", "Use clipboard to paste"),
            "Using the clipboard preserves text formatting in applications like Telegram.",
            prefs.spacer(16),
            prefs.textInput("calc_window_timeout", "Window timeout (ms)")
                 :setDefault(DEFAULT_WINDOW_TIMEOUT)
                 :useInt()
                 :setInputType({ "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" }),
            prefs.spacer(8),
            prefs.textInput("calc_window_offset", "Window offset (dp)")
                 :setDefault(DEFAULT_WINDOW_OFFSET)
                 :useInt()
                 :setInputType({ "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" }),
            prefs.spacer(16)
        }
    end)

    if preferences:getBoolean("calc", true) then
        module:registerWatcher(watcher)
    end

    windows.supportInsert()
end
