require "utils"
require "menu"
require "windows"

local Base64 = require "java.util.Base64"

-- Zero-width characters for steganographic encoding
local ZWS  = "\xE2\x80\x8B"  -- U+200B Zero Width Space       (bit 0)
local ZWNJ = "\xE2\x80\x8C"  -- U+200C Zero Width Non-Joiner  (bit 1)
local ZWJ  = "\xE2\x80\x8D"  -- U+200D Zero Width Joiner      (marker)

-- Convert any text to ASCII-safe Base64 via Java (handles Cyrillic, emoji, etc.)
local function to_ascii(text)
    local bytes = luajava.newInstance("java.lang.String", text):getBytes("UTF-8")
    return Base64:getEncoder():encodeToString(bytes)
end

local function from_ascii(ascii)
    local bytes = Base64:getDecoder():decode(ascii)
    return luajava.newInstance("java.lang.String", bytes, "UTF-8"):toString()
end

local function encode(message)
    local safe = to_ascii(message)
    local parts = { ZWJ }

    for i = 1, #safe do
        local byte = string.byte(safe, i)
        for bit = 7, 0, -1 do
            local value = math.floor(byte / (2 ^ bit)) % 2
            parts[#parts + 1] = value == 1 and ZWNJ or ZWS
        end
    end

    parts[#parts + 1] = ZWJ
    return table.concat(parts)
end

local function decode(text)
    local messages = {}
    local pattern = ZWJ .. "(.-)" .. ZWJ

    for hidden in text:gmatch(pattern) do
        local chars = {}
        local bits = {}

        for i = 1, #hidden, 3 do
            local char = hidden:sub(i, i + 2)
            if char == ZWNJ then
                bits[#bits + 1] = 1
            elseif char == ZWS then
                bits[#bits + 1] = 0
            end

            if #bits == 8 then
                local byte = 0
                for j = 1, 8 do
                    byte = byte * 2 + bits[j]
                end
                chars[#chars + 1] = string.char(byte)
                bits = {}
            end
        end

        if #chars > 0 then
            local ok, result = pcall(from_ascii, table.concat(chars))
            if ok then
                messages[#messages + 1] = result
            end
        end
    end

    return messages
end

local function cleanText(text)
    return text:gsub(ZWS, ""):gsub(ZWNJ, ""):gsub(ZWJ, "")
end

-- Commands

local function hide(_, query)
    local secret = query:getArgs()
    if secret == "" then
        return query:answer "Usage: hide <secret message>"
    end

    query:answer(encode(secret))
end

local function reveal(_, query)
    local text = query:replaceExpression("")
    local messages = decode(text)

    if #messages == 0 then
        return menu.create(query, { "No hidden messages found" })
    end

    local result = { "Hidden messages found: " .. #messages .. "\n\n" }

    for i, msg in ipairs(messages) do
        result[#result + 1] = "#" .. i .. ": " .. msg .. "\n"
    end

    result[#result + 1] = "\n"
    result[#result + 1] = {
        caption = "[OK]",
        action = function(_, q)
            q:answer(text)
        end
    }

    menu.create(query, result)
end

local function clean(input, query)
    inline:setText(input, cleanText(query:replaceExpression("")))
end

local function inspect(_, query)
    local text = query:replaceExpression("")
    local cleaned = cleanText(text)
    local hiddenCount = 0

    for _ in text:gmatch(ZWS) do hiddenCount = hiddenCount + 1 end
    for _ in text:gmatch(ZWNJ) do hiddenCount = hiddenCount + 1 end
    for _ in text:gmatch(ZWJ) do hiddenCount = hiddenCount + 1 end

    local messages = decode(text)

    local result = {
        "Phantom Inspect\n\n",
        "Visible length: " .. #cleaned .. " bytes\n",
        "Total length: " .. #text .. " bytes\n",
        "Hidden chars: " .. hiddenCount .. "\n",
        "Hidden messages: " .. #messages .. "\n",
    }

    for i, msg in ipairs(messages) do
        result[#result + 1] = "\n#" .. i .. ": " .. msg
    end

    result[#result + 1] = "\n"
    result[#result + 1] = {
        caption = "[OK]",
        action = function(_, q)
            q:answer(text)
        end
    }

    menu.create(query, result)
end

-- Floating reveal window

local function freveal(_, query)
    windows.create({ noLimits = true }, function(ui)
        local text = query:replaceExpression("")
        local messages = decode(text)

        local content
        if #messages == 0 then
            content = ui.text "No hidden messages found"
        else
            local parts = {}
            for i, msg in ipairs(messages) do
                parts[#parts + 1] = "#" .. i .. ": " .. msg
            end
            content = ui.text(table.concat(parts, "\n"))
        end

        content:setMaxLines(15)

        local paste = ui.smallButton("Paste", function()
            if #messages > 0 then
                if not windows.insertText(messages[1]) then
                    return inline:toast "Please focus on the desired input"
                end
            end
        end)

        paste:setEnabled(#messages > 0 and windows.isInsertAvailable())

        ui.onFocusChanged = function(isFocused)
            paste:setEnabled(not isFocused and #messages > 0 and windows.isInsertAvailable())
        end

        return {
            content,
            ui.spacer(8),
            {
                ui.smallButton("Close", function()
                    ui:close()
                end),
                ui.spacer(8),
                paste
            }
        }
    end)

    query:answer()
end

-- Floating hide composer

local function fhide(_, query)
    windows.create({ noLimits = true }, function(ui)
        local secretInput = ui.textInput "Secret message"

        secretInput:getEditText():setMaxLines(5)
        secretInput:setText(query:getArgs())

        local paste = ui.smallButton("Paste", function()
            local secret = secretInput:getText()

            if secret == "" then
                return inline:toast "Enter a hidden message"
            end

            if not windows.insertText(encode(secret)) then
                return inline:toast "Please focus on the desired input"
            end
        end)

        paste:setEnabled(windows.isInsertAvailable())

        ui.onFocusChanged = function(isFocused)
            paste:setEnabled(not isFocused and windows.isInsertAvailable())
        end

        return {
            secretInput,
            ui.spacer(8),
            {
                ui.smallButton("Close", function()
                    ui:close()
                end),
                ui.spacer(8),
                paste
            }
        }
    end)

    query:answer()
end

return function(module)
    module:setCategory "Phantom"

    module:registerCommand("hide", utils.hasArgs(hide), "Encodes a secret into invisible zero-width characters")
    module:registerCommand("reveal", reveal, "Decodes hidden messages from the text")
    module:registerCommand("clean", clean, "Removes all invisible characters from text")
    module:registerCommand("inspect", inspect, "Shows stats about hidden content in text")

    if windows.isSupported() then
        module:registerCommand("freveal", freveal, "Floating window to reveal hidden messages")
        module:registerCommand("fhide", fhide, "Floating composer for hiding messages")
        windows.supportInsert()
    end

    module:saveLazyLoad()
end
