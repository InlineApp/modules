require "utils"
require "menu"
require "windows"

local MessageDigest = require "java.security.MessageDigest"
local Base64 = require "java.util.Base64"
local UUID = require "java.util.UUID"

-- XOR helper (pure Lua, no bit32 needed)
local function bxor(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local a1, b1 = a % 2, b % 2
        if a1 ~= b1 then r = r + p end
        a = (a - a1) / 2
        b = (b - b1) / 2
        p = p * 2
    end
    return r
end

-- XOR cipher with key, returns hex string
local function xor_encrypt(text, key)
    local result = {}
    for i = 1, #text do
        local tb = string.byte(text, i)
        local kb = string.byte(key, (i - 1) % #key + 1)
        result[#result + 1] = string.format("%02x", bxor(tb, kb))
    end
    return table.concat(result)
end

-- Hex string → XOR decrypt with key
local function xor_decrypt(hex, key)
    local result = {}
    for i = 1, #hex, 2 do
        local byte = tonumber(hex:sub(i, i + 1), 16)
        if not byte then return nil end
        local kb = string.byte(key, ((i - 1) / 2) % #key + 1)
        result[#result + 1] = string.char(bxor(byte, kb))
    end
    return table.concat(result)
end

-- ROT13
local function rot13(text)
    return text:gsub("%a", function(c)
        local base = c:match("%l") and 97 or 65
        return string.char((string.byte(c) - base + 13) % 26 + base)
    end)
end

-- Caesar cipher
local function caesar(text, shift)
    return text:gsub("%a", function(c)
        local base = c:match("%l") and 97 or 65
        return string.char((string.byte(c) - base + shift) % 26 + base)
    end)
end

-- Morse code tables
local to_morse = {
    A = ".-", B = "-...", C = "-.-.", D = "-..", E = ".", F = "..-.",
    G = "--.", H = "....", I = "..", J = ".---", K = "-.-", L = ".-..",
    M = "--", N = "-.", O = "---", P = ".--.", Q = "--.-", R = ".-.",
    S = "...", T = "-", U = "..-", V = "...-", W = ".--", X = "-..-",
    Y = "-.--", Z = "--..",
    ["0"] = "-----", ["1"] = ".----", ["2"] = "..---", ["3"] = "...--",
    ["4"] = "....-", ["5"] = ".....", ["6"] = "-....", ["7"] = "--...",
    ["8"] = "---..", ["9"] = "----.",
    [" "] = "/", ["."] = ".-.-.-", [","] = "--..--", ["?"] = "..--..",
    ["!"] = "-.-.--", ["'"] = ".----.", ['"'] = ".-..-.",
    [":"] = "---...", [";"] = "-.-.-.", ["="] = "-...-",
    ["+"] = ".-.-.", ["-"] = "-....-", ["/"] = "-..-.",
    ["("] = "-.--.", [")"] = "-.--.-", ["@"] = ".--.-.",
}

local from_morse = {}
for k, v in pairs(to_morse) do from_morse[v] = k end

local function morse_encode(text)
    local result = {}
    for i = 1, #text do
        local c = text:sub(i, i):upper()
        result[#result + 1] = to_morse[c] or c
    end
    return table.concat(result, " ")
end

local function morse_decode(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do
        result[#result + 1] = from_morse[word] or word
    end
    return table.concat(result)
end

-- Base64 via Java
local function base64_encode(text)
    local bytes = luajava.newInstance("java.lang.String", text):getBytes("UTF-8")
    return Base64:getEncoder():encodeToString(bytes)
end

local function base64_decode(text)
    local bytes = Base64:getDecoder():decode(text)
    return luajava.newInstance("java.lang.String", bytes, "UTF-8"):toString()
end

-- SHA-256 via Java
local function sha256(text)
    local md = MessageDigest:getInstance("SHA-256")
    local bytes = md:digest(luajava.newInstance("java.lang.String", text):getBytes("UTF-8"))
    local hex = {}
    for i = 1, #bytes do
        local b = bytes[i]
        if b < 0 then b = b + 256 end
        hex[#hex + 1] = string.format("%02x", b)
    end
    return table.concat(hex)
end

-- Password generator
local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"

local function genpass(length)
    local result = {}
    for _ = 1, length do
        local idx = math.random(1, #chars)
        result[#result + 1] = chars:sub(idx, idx)
    end
    return table.concat(result)
end

-- Helper: get text from args or field
local function get_text(query)
    local args = query:getArgs()
    if args ~= "" then return args, true end
    return query:replaceExpression(""), false
end

local function output(input, query, result, from_args)
    if from_args then
        query:answer(result)
    else
        inline:setText(input, result)
    end
end

-- Commands

local function encrypt_cmd(input, query)
    local parts = utils.split(query:getArgs(), " ", 2)
    local key = parts[1]

    if not key or key == "" then
        return query:answer "Usage: encrypt <key> [text]"
    end

    local text = parts[2]
    if text and text ~= "" then
        query:answer(xor_encrypt(text, key))
    else
        inline:setText(input, xor_encrypt(query:replaceExpression(""), key))
    end
end

local function decrypt_cmd(input, query)
    local parts = utils.split(query:getArgs(), " ", 2)
    local key = parts[1]

    if not key or key == "" then
        return query:answer "Usage: decrypt <key> [hex]"
    end

    local hex = parts[2]
    if hex and hex ~= "" then
        local result = xor_decrypt(hex, key)
        query:answer(result or "Invalid hex input")
    else
        local result = xor_decrypt(query:replaceExpression(""):gsub("%s+", ""), key)
        inline:setText(input, result or "Invalid hex input")
    end
end

local function rot13_cmd(input, query)
    local text, from_args = get_text(query)
    output(input, query, rot13(text), from_args)
end

local function caesar_cmd(input, query)
    local parts = utils.split(query:getArgs(), " ", 2)
    local shift = tonumber(parts[1])

    if not shift then
        return query:answer "Usage: caesar <shift> [text]"
    end

    local text = parts[2]
    if text and text ~= "" then
        query:answer(caesar(text, shift))
    else
        inline:setText(input, caesar(query:replaceExpression(""), shift))
    end
end

local function morse_cmd(input, query)
    local text, from_args = get_text(query)
    output(input, query, morse_encode(text), from_args)
end

local function demorse_cmd(input, query)
    local text, from_args = get_text(query)
    output(input, query, morse_decode(text), from_args)
end

local function base64e_cmd(input, query)
    local text, from_args = get_text(query)
    local ok, result = pcall(base64_encode, text)
    output(input, query, ok and result or "Error: " .. result, from_args)
end

local function base64d_cmd(input, query)
    local text, from_args = get_text(query)
    local ok, result = pcall(base64_decode, text:gsub("%s+", ""))
    output(input, query, ok and result or "Error: " .. result, from_args)
end

local function sha256_cmd(input, query)
    local text, from_args = get_text(query)
    local ok, result = pcall(sha256, text)
    output(input, query, ok and result or "Error: " .. result, from_args)
end

local function uuid_cmd(_, query)
    query:answer(UUID:randomUUID():toString())
end

local function genpass_cmd(_, query)
    local len = tonumber(query:getArgs())
    if not len or len < 1 then len = 16 end
    if len > 128 then len = 128 end
    query:answer(genpass(len))
end

-- Floating encrypt/decrypt window

local function fcrypt(input, query)
    windows.createAligned(input, { noLimits = true }, function(ui)
        local textInput = ui.textInput("Text", "Message")
        local keyInput = ui.textInput("Key", "Secret key")
        local result = ui.text ""

        textInput:getEditText():setMaxLines(5)
        result:setMaxLines(10)

        textInput:setText(query:getArgs())

        local paste = ui.smallButton("Paste", function()
            if not windows.insertText(result:getText()) then
                return inline:toast "Please focus on the desired input"
            end
        end)

        paste:setEnabled(windows.isInsertAvailable())

        ui.onFocusChanged = function(isFocused)
            paste:setEnabled(not isFocused and windows.isInsertAvailable())
        end

        return {
            textInput,
            ui.spacer(8),
            keyInput,
            ui.spacer(8),
            {
                ui.smallButton("Encrypt", function()
                    local key = keyInput:getText()
                    if key == "" then return inline:toast "Enter a key" end
                    result:setText(xor_encrypt(textInput:getText(), key))
                end),
                ui.spacer(8),
                ui.smallButton("Decrypt", function()
                    local key = keyInput:getText()
                    if key == "" then return inline:toast "Enter a key" end
                    local r = xor_decrypt(textInput:getText():gsub("%s+", ""), key)
                    result:setText(r or "Invalid hex input")
                end),
                ui.spacer(8),
                ui.smallButton("B64 Enc", function()
                    local ok, r = pcall(base64_encode, textInput:getText())
                    result:setText(ok and r or "Error")
                end),
                ui.spacer(8),
                ui.smallButton("B64 Dec", function()
                    local ok, r = pcall(base64_decode, textInput:getText():gsub("%s+", ""))
                    result:setText(ok and r or "Error")
                end),
            },
            ui.spacer(8),
            result,
            ui.spacer(8),
            {
                ui.smallButton("Close", function()
                    ui:close()
                end),
                ui.spacer(8),
                paste,
            }
        }
    end)

    query:answer()
end

return function(module)
    module:setCategory "Crypt"

    module:registerCommand("encrypt", encrypt_cmd, "XOR encrypt: encrypt <key> [text]")
    module:registerCommand("decrypt", decrypt_cmd, "XOR decrypt: decrypt <key> [hex]")
    module:registerCommand("rot13", rot13_cmd, "ROT13 cipher")
    module:registerCommand("caesar", caesar_cmd, "Caesar cipher: caesar <shift> [text]")
    module:registerCommand("morse", morse_cmd, "Text to Morse code")
    module:registerCommand("demorse", demorse_cmd, "Morse code to text")
    module:registerCommand("base64e", base64e_cmd, "Base64 encode")
    module:registerCommand("base64d", base64d_cmd, "Base64 decode")
    module:registerCommand("sha256", sha256_cmd, "SHA-256 hash")
    module:registerCommand("uuid", uuid_cmd, "Generate random UUID")
    module:registerCommand("genpass", genpass_cmd, "Generate password: genpass [length]")

    if windows.isSupported() then
        module:registerCommand("fcrypt", fcrypt, "Floating encrypt/decrypt toolbox")
        windows.supportInsert()
    end

    module:saveLazyLoad()
end
