require "windows"
require "iutf8"

if not windows:isSupported() then
    inline:toast "The module is not supported on this version of Android"
    return
end

local preferences = inline:getDefaultSharedPreferences()
local whitelistPrefs = inline:getSharedPreferences "counter_whitelist"

local DEFAULT_WINDOW_OFFSET = 20
local DEFAULT_WINDOW_TIMEOUT = 5000

local window
local timer = inline:getTimer()

local function getWhitelist()
    local set = whitelistPrefs:getStringSet("apps", nil)
    if not set then return {} end

    local result = {}
    local iterator = set:iterator()
    while iterator:hasNext() do
        local pkg = iterator:next()
        result[pkg] = true
    end
    return result
end

local function saveWhitelist(list)
    local HashSet = require "java.util.HashSet"
    local set = luajava.new(HashSet)
    for pkg in pairs(list) do
        set:add(pkg)
    end
    whitelistPrefs:edit():putStringSet("apps", set):apply()
end

local function isAllowed(input)
    if not preferences:getBoolean("counter_use_whitelist", false) then
        return true
    end

    local pkg = input:getPackageName()
    local whitelist = getWhitelist()
    return whitelist[pkg] == true
end

local function count(text)
    local chars = utf8.len(text) or 0
    local words = 0
    local lines = 1
    local sentences = 0

    for _ in text:gmatch("%S+") do
        words = words + 1
    end

    for _ in text:gmatch("\n") do
        lines = lines + 1
    end

    for _ in text:gmatch("[%.!%?]+%s") do
        sentences = sentences + 1
    end

    if #text > 0 and text:match("[%.!%?]%s*$") then
        -- last sentence already counted above if followed by space
    elseif #text > 0 and words > 0 then
        sentences = sentences + 1
    end

    return chars, words, lines, sentences
end

local function formatStats(chars, words, lines, sentences)
    local parts = {}

    if preferences:getBoolean("counter_show_chars", true) then
        table.insert(parts, chars .. " chars")
    end

    if preferences:getBoolean("counter_show_words", true) then
        table.insert(parts, words .. " words")
    end

    if preferences:getBoolean("counter_show_lines", false) then
        table.insert(parts, lines .. " lines")
    end

    if preferences:getBoolean("counter_show_sentences", false) then
        table.insert(parts, sentences .. " sent")
    end

    if #parts == 0 then
        return chars .. " chars"
    end

    return table.concat(parts, " · ")
end

local function showWindow(input, text)
    local timerTask = inline:timerTask(function()
        window.close()
    end)

    local label

    local floatingWindow = windows.createAligned(input, {
        noBackground = true,
        offsetY = preferences:getInt("counter_window_offset", DEFAULT_WINDOW_OFFSET),
        onClose = function()
            window = nil
            timerTask:cancel()
        end
    }, function(ui)
        label = ui.text(text)
        return { label }
    end)

    timer:schedule(timerTask, preferences:getInt("counter_window_timeout", DEFAULT_WINDOW_TIMEOUT))

    return {
        close = function()
            floatingWindow:close()
        end,
        update = function(newText)
            label:setText(newText)
        end
    }
end

local function updateWindow(input, text)
    if window then
        window.update(text)
    else
        window = showWindow(input, text)
    end
end

local function watcher(input)
    if not isAllowed(input) then
        if window then window.close() end
        return
    end

    local text = inline:getText(input)

    if #text == 0 then
        if window then window.close() end
        return
    end

    local chars, words, lines, sentences = count(text)
    local result = formatStats(chars, words, lines, sentences)

    updateWindow(input, result)
end

local function addApp(input, query)
    local pkg = query:getArgs()
    if pkg == "" then
        pkg = input:getPackageName()
    end

    local whitelist = getWhitelist()
    whitelist[pkg] = true
    saveWhitelist(whitelist)
    query:answer("Added: " .. pkg)
end

local function removeApp(input, query)
    local pkg = query:getArgs()
    if pkg == "" then
        pkg = input:getPackageName()
    end

    local whitelist = getWhitelist()
    whitelist[pkg] = nil
    saveWhitelist(whitelist)
    query:answer("Removed: " .. pkg)
end

local function listApps(_, query)
    local whitelist = getWhitelist()
    local apps = {}
    for pkg in pairs(whitelist) do
        table.insert(apps, "• " .. pkg)
    end

    if #apps == 0 then
        query:answer "Whitelist is empty"
    else
        query:answer("Whitelisted apps:\n" .. table.concat(apps, "\n"))
    end
end

return function(module)
    module:setCategory "Counter"

    module:registerCommand("counter.add", addApp, "Add current app to counter whitelist")
    module:registerCommand("counter.remove", removeApp, "Remove current app from counter whitelist")
    module:registerCommand("counter.list", listApps, "List whitelisted apps")

    module:registerPreferences(function(prefs)
        return {
            prefs.switch("counter", "Enabled")
                 :setDefault(false)
                 :setListener(function(isChecked)
                if isChecked then
                    module:registerWatcher(watcher)
                else
                    module:unregisterWatcher(watcher)
                    if window then window.close() end
                end
            end),
            prefs.spacer(12),
            prefs.card {
                prefs.text "Display":bold():size(16),
                prefs.spacer(4),
                prefs.switch("counter_show_chars", "Characters"):setDefault(true),
                prefs.switch("counter_show_words", "Words"):setDefault(true),
                prefs.switch("counter_show_lines", "Lines"),
                prefs.switch("counter_show_sentences", "Sentences"),
            },
            prefs.spacer(12),
            prefs.card {
                prefs.text "Whitelist":bold():size(16),
                prefs.spacer(4),
                prefs.text "When enabled, counter only shows in whitelisted apps. Use {counter.add}$ in any app to add it.":size(12),
                prefs.spacer(4),
                prefs.switch("counter_use_whitelist", "Use app whitelist"),
            },
            prefs.spacer(12),
            prefs.card {
                prefs.text "Window":bold():size(16),
                prefs.spacer(8),
                prefs.textInput("counter_window_timeout", "Timeout (ms)")
                     :setDefault(DEFAULT_WINDOW_TIMEOUT)
                     :useInt()
                     :setInputType { "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" },
                prefs.spacer(8),
                prefs.textInput("counter_window_offset", "Offset (dp)")
                     :setDefault(DEFAULT_WINDOW_OFFSET)
                     :useInt()
                     :setInputType { "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" },
            },
        }
    end)

    if preferences:getBoolean("counter", false) then
        module:registerWatcher(watcher)
    end

    module:saveLazyLoad()
end
