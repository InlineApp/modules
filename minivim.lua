require "iutf8"
require "utils"
require "windows"

local context = {}
local actualInput

local help = [[Navigation
- h - Move cursor left (stays within the current line)
- l - Move cursor right (stays within the current line)
- j - Move cursor down one line (maintains column position)
- k - Move cursor up one line (maintains column position)
- 0 - Move to the beginning of the current line
- $ - Move to the end of the current line
- ^ - Move to the first non-whitespace character of the current line
- gg - Move to the beginning of the document
- G - Move to the end of the document
Insertion Mode
- i - Enter insert mode at current cursor position
- a - Enter insert mode after the cursor
- I - Enter insert mode at the beginning of the current line
- A - Enter insert mode at the end of the current line
- o - Create a new line below the current line and enter insert mode
- O - Create a new line above the current line and enter insert mode
Editing
- dd - Delete the current line]]

local function getContext(input)
    local current = context[input:getPackageName()]

    if not current then
        current = {
            mode = "INSERT"
        }

        context[input:getPackageName()] = current
    end

    return current
end

local function dropContext(input)
    context[input:getPackageName()] = nil
end

local function goToNormal(input, current)
    current.text = inline:getText(input)
    current.len = utf8.len(current.text)
    current.position = input:getTextSelectionStart() - 1
    inline:setSelection(input, current.position, current.position)
end

local function goToInsert(input, current)
    inline:setText(input, current.text)
    inline:setSelection(input, current.position, current.position)
end

local function updateTextButton(current)
    if current.button then
        current.button:setText(current.mode)
        current.button:setEnabled(current.mode ~= "NORMAL")
    end
end

local function switchMode(input, current)
    current.mode = current.mode == "NORMAL" and "INSERT" or "NORMAL"
    if current.mode == "NORMAL" then
        goToNormal(input, current)
    else
        goToInsert(input, current)
    end
    updateTextButton(current)
end

local function getCurrentLineInfo(text, pos)
    local textLen = utf8.len(text)
    local lineStart = 0
    local lineEnd = textLen - 1

    for i = pos, 0, -1 do
        if utf8.sub(text, i, i + 1) == "\n" then
            lineStart = i + 1
            break
        end
    end

    for i = pos, textLen - 1 do
        if utf8.sub(text, i, i + 1) == "\n" then
            lineEnd = i - 1
            break
        end
    end

    local column = pos - lineStart
    return lineStart, lineEnd, column
end

local function getLineNumber(text, pos)
    local lineNum = 1

    for i = 0, pos - 1 do
        if utf8.sub(text, i, i + 1) == "\n" then
            lineNum = lineNum + 1
        end
    end

    return lineNum
end

local function getLineByNumber(text, lineNum)
    local textLen = utf8.len(text)
    local currentLine = 1
    local lineStart = 0
    local lineEnd = textLen - 1

    for i = 0, textLen - 1 do
        if utf8.sub(text, i, i + 1) == "\n" then
            if currentLine == lineNum then
                lineEnd = i - 1
                break
            end
            currentLine = currentLine + 1
            lineStart = i + 1
        end
    end

    return lineStart, lineEnd
end

local function isWordChar(char)
    return char:match("[%w_]") ~= nil
end

local function deleteCurrentLine(text, pos)
    local lineStart, lineEnd, _ = getCurrentLineInfo(text, pos)
    local beforeLine = ""
    local afterLine = ""

    if lineStart > 0 then
        beforeLine = utf8.sub(text, 0, lineStart - 1)
    end

    if lineEnd < utf8.len(text) - 1 then
        afterLine = utf8.sub(text, lineEnd + 1)
    end

    if lineEnd < utf8.len(text) - 1 and utf8.sub(text, lineEnd + 1, lineEnd + 2) == "\n" then
        afterLine = utf8.sub(text, lineEnd + 2)
    end

    if lineEnd == utf8.len(text) - 1 and lineStart > 0 and beforeLine ~= "" then
        beforeLine = utf8.sub(beforeLine, 0, utf8.len(beforeLine) - 1)
    end

    local newText = beforeLine .. afterLine
    local newPos = lineStart

    if newText == "" then
        newText = ""
        newPos = 0
    end

    if newPos > utf8.len(newText) then
        newPos = utf8.len(newText)
    end

    return newText, newPos
end

local singleCommands = {
    h = function(input, current)
        local lineStart, _, _ = getCurrentLineInfo(current.text, current.position)

        if current.position > lineStart then
            current.position = current.position - 1
        end

        inline:setSelection(input, current.position, current.position)
    end,

    l = function(input, current)
        local _, lineEnd, _ = getCurrentLineInfo(current.text, current.position)

        if current.position < lineEnd then
            current.position = current.position + 1
        end

        inline:setSelection(input, current.position, current.position)
    end,

    j = function(input, current)
        local text = current.text
        local _, _, column = getCurrentLineInfo(text, current.position)
        local lineNum = getLineNumber(text, current.position)

        local nextLineStart, nextLineEnd = getLineByNumber(text, lineNum + 1)

        if nextLineStart < utf8.len(text) then
            local nextLineLength = nextLineEnd - nextLineStart + 1

            if column < nextLineLength then
                current.position = nextLineStart + column
            else
                current.position = nextLineEnd
            end
        end

        inline:setSelection(input, current.position, current.position)
    end,

    k = function(input, current)
        local text = current.text
        local _, _, column = getCurrentLineInfo(text, current.position)
        local lineNum = getLineNumber(text, current.position)

        if lineNum > 1 then
            local prevLineStart, prevLineEnd = getLineByNumber(text, lineNum - 1)
            local prevLineLength = prevLineEnd - prevLineStart + 1

            if column < prevLineLength then
                current.position = prevLineStart + column
            else
                current.position = prevLineEnd
            end

        end

        inline:setSelection(input, current.position, current.position)
    end,

    i = function(input, current)
        current.mode = "INSERT"
        goToInsert(input, current)
        updateTextButton(current)
    end,

    ["0"] = function(input, current)
        local lineStart, _, _ = getCurrentLineInfo(current.text, current.position)
        current.position = lineStart
        inline:setSelection(input, current.position, current.position)
    end,

    ["$"] = function(input, current)
        local _, lineEnd, _ = getCurrentLineInfo(current.text, current.position)
        current.position = lineEnd
        inline:setSelection(input, current.position, current.position)
    end,

    G = function(input, current)
        current.position = utf8.len(current.text)
        inline:setSelection(input, current.position, current.position)
    end,

    ["^"] = function(input, current)
        local lineStart, lineEnd, _ = getCurrentLineInfo(current.text, current.position)
        local pos = lineStart

        while pos <= lineEnd do
            local char = utf8.sub(current.text, pos, pos + 1)
            if char ~= " " and char ~= "\t" then
                break
            end
            pos = pos + 1
        end

        current.position = pos
        inline:setSelection(input, current.position, current.position)
    end,

    a = function(input, current)
        if current.position < utf8.len(current.text) then
            current.position = current.position + 1
        end
        current.mode = "INSERT"
        goToInsert(input, current)
        updateTextButton(current)
    end,

    I = function(input, current)
        local lineStart, _, _ = getCurrentLineInfo(current.text, current.position)
        current.position = lineStart
        current.mode = "INSERT"
        goToInsert(input, current)
        updateTextButton(current)
    end,

    A = function(input, current)
        local _, lineEnd, _ = getCurrentLineInfo(current.text, current.position)
        current.position = lineEnd + 1
        current.mode = "INSERT"
        goToInsert(input, current)
        updateTextButton(current)
    end,

    o = function(input, current)
        local text = current.text
        local _, lineEnd, _ = getCurrentLineInfo(text, current.position)

        local newText = utf8.sub(text, 0, lineEnd + 1) .. "\n" .. utf8.sub(text, lineEnd + 1)
        current.text = newText
        current.len = utf8.len(newText)
        current.position = lineEnd + 2

        current.mode = "INSERT"
        inline:setText(input, current.text)
        inline:setSelection(input, current.position, current.position)
        updateTextButton(current)
    end,

    O = function(input, current)
        local text = current.text
        local lineStart, _, _ = getCurrentLineInfo(text, current.position)

        local newText = utf8.sub(text, 0, lineStart) .. "\n" .. utf8.sub(text, lineStart)
        current.text = newText
        current.len = utf8.len(newText)

        current.position = lineStart

        current.mode = "INSERT"
        inline:setText(input, current.text)
        inline:setSelection(input, current.position, current.position)
        updateTextButton(current)
    end,

    dd = function(input, current)
        local newText, newPos = deleteCurrentLine(current.text, current.position)
        current.text = newText
        current.len = utf8.len(newText)
        current.position = newPos

        inline:setText(input, current.text)
        inline:setSelection(input, current.position, current.position)
    end,

    gg = function(input, current)
        current.position = 0
        inline:setSelection(input, current.position, current.position)
    end,

    w = function(input, current)
        local text = current.text
        local textLen = utf8.len(text)
        local pos = current.position

        if pos >= textLen - 1 then
            return
        end

        pos = pos + 1

        local currentChar = utf8.sub(text, pos, pos + 1)
        if isWordChar(currentChar) then
            while pos < textLen and isWordChar(utf8.sub(text, pos, pos + 1)) do
                pos = pos + 1
            end
        end

        while pos < textLen and not isWordChar(utf8.sub(text, pos, pos + 1)) do
            pos = pos + 1
        end

        current.position = pos
        inline:setSelection(input, current.position, current.position)
    end,

    b = function(input, current)
        local text = current.text
        local pos = current.position

        if pos <= 0 then
            return
        end

        pos = pos - 1

        while pos > 0 and not isWordChar(utf8.sub(text, pos, pos + 1)) do
            pos = pos - 1
        end

        if pos > 0 and isWordChar(utf8.sub(text, pos, pos + 1)) then
            while pos > 0 and isWordChar(utf8.sub(text, pos - 1, pos)) do
                pos = pos - 1
            end
        end

        current.position = pos
        inline:setSelection(input, current.position, current.position)
    end,

    e = function(input, current)
        local text = current.text
        local textLen = utf8.len(text)
        local pos = current.position

        if pos >= textLen - 1 then
            return
        end

        local currentAtEndOfWord = pos < textLen - 1 and
            isWordChar(utf8.sub(text, pos, pos + 1)) and
            (pos == textLen - 1 or not isWordChar(utf8.sub(text, pos + 1, pos + 2)))

        if currentAtEndOfWord then
            pos = pos + 1
            while pos < textLen - 1 and not isWordChar(utf8.sub(text, pos, pos + 1)) do
                pos = pos + 1
            end
        end

        if not isWordChar(utf8.sub(text, pos, pos + 1)) then
            while pos < textLen - 1 and not isWordChar(utf8.sub(text, pos, pos + 1)) do
                pos = pos + 1
            end
        end

        if pos < textLen - 1 then
            while pos < textLen - 1 and isWordChar(utf8.sub(text, pos + 1, pos + 2)) do
                pos = pos + 1
            end
        end

        current.position = pos
        inline:setSelection(input, current.position, current.position)
    end,

    x = function(input, current)
        local text = current.text
        local textLen = utf8.len(text)

        if textLen > 0 and current.position < textLen then
            local newText = utf8.sub(text, 0, current.position) ..
                utf8.sub(text, current.position + 1)
            current.text = newText
            current.len = utf8.len(newText)
            inline:setText(input, current.text)
            inline:setSelection(input, current.position, current.position)
        end
    end,

    X = function(input, current)
        local text = current.text

        if current.position > 0 then
            local newText = utf8.sub(text, 0, current.position - 1) ..
                utf8.sub(text, current.position)
            current.text = newText
            current.len = utf8.len(newText)
            current.position = current.position - 1
            inline:setText(input, current.text)
            inline:setSelection(input, current.position, current.position)
        end
    end,

    ["~"] = function(input, current)
        local text = current.text
        local textLen = utf8.len(text)

        if textLen > 0 and current.position < textLen then
            local char = utf8.sub(text, current.position, current.position + 1)
            local newChar

            if char:match("%u") then
                newChar = char:lower()
            else
                newChar = char:upper()
            end

            local newText = utf8.sub(text, 0, current.position) ..
                newChar ..
                utf8.sub(text, current.position + 1)

            current.text = newText
            current.len = utf8.len(newText)
            current.position = current.position + 1

            inline:setText(input, current.text)
            inline:setSelection(input, current.position, current.position)
        end
    end,

    s = function(input, current)
        local text = current.text
        local textLen = utf8.len(text)

        if textLen > 0 and current.position < textLen then
            local newText = utf8.sub(text, 0, current.position) ..
                utf8.sub(text, current.position + 1)
            current.text = newText
            current.len = utf8.len(newText)

            current.mode = "INSERT"
            inline:setText(input, current.text)
            inline:setSelection(input, current.position, current.position)
            updateTextButton(current)
        end
    end,

    S = function(input, current)
        local text = current.text

        local lineStart, lineEnd, _ = getCurrentLineInfo(text, current.position)
        local before = ""
        if lineStart > 0 then
            before = utf8.sub(text, 0, lineStart)
        end

        local after = ""
        if lineEnd < utf8.len(text) - 1 then
            after = utf8.sub(text, lineEnd + 1)
        end

        local newText = before .. after
        if newText == "" then
            newText = ""
        end

        current.text = newText
        current.len = utf8.len(newText)
        current.position = lineStart

        current.mode = "INSERT"
        inline:setText(input, current.text)
        inline:setSelection(input, current.position, current.position)
        updateTextButton(current)
    end,

    C = function(input, current)
        local text = current.text

        local _, lineEnd, _ = getCurrentLineInfo(text, current.position)

        local newText = utf8.sub(text, 0, current.position) ..
            utf8.sub(text, lineEnd + 1)

        current.text = newText
        current.len = utf8.len(newText)

        current.mode = "INSERT"
        inline:setText(input, current.text)
        inline:setSelection(input, current.position, current.position)
        updateTextButton(current)
    end
}

local bufferedCommands = {
    g = true,
    d = true
}

local pendingCommands = {
    r = function(input, current, char)
        local text = current.text
        local textLen = utf8.len(text)

        if textLen > 0 and current.position < textLen then
            local newText = utf8.sub(text, 0, current.position) ..
                char ..
                utf8.sub(text, current.position + 1)

            current.text = newText
            current.len = utf8.len(newText)

            inline:setText(input, current.text)
            inline:setSelection(input, current.position, current.position)
        end

        return true
    end
}

local function showSwitcher(input, query)
    query:answer()
    local current = getContext(input)
    if not current.button then
        windows.createAligned(input, {
            paddingLeft = 8,
            paddingRight = 8,
            paddingTop = 8,
            paddingBottom = 8,
            position = "below",
            onClose = function()
                current.button = nil
                goToInsert(input, getContext(input))
                dropContext(input)
            end
        }, function(ui)
            local switcher
            switcher = ui.smallButton(current.mode, function()
                current = getContext(actualInput)
                actualInput:refresh()
                switchMode(actualInput, current)
            end)
            current.button = switcher
            return {
                {
                    switcher,
                    ui.spacer(8),
                    "MiniVIM",
                    ui.spacer(8),
                    ui.smallButton("CLOSE", function()
                        ui:close()
                    end)
                }
            }
        end)
    end
end

local function watcher(input)
    local current = getContext(input)

    if current.ignore then
        current.ignore = false
        return
    end

    if current.mode == "NORMAL" then
        local text = inline:getText(input)
        local delta = utf8.len(text) - current.len
        if delta > 0 then
            local selectionStart = input:getTextSelectionStart()
            if selectionStart == nil or selectionStart == -1 then
                selectionStart = 0
            end

            local cmdString = utf8.sub(text, selectionStart - delta, selectionStart)

            if current.pendingCommand then
                local handler = pendingCommands[current.pendingCommand]
                if handler then
                    local finished = handler(input, current, cmdString)
                    if finished then
                        current.pendingCommand = nil
                    end
                    current.ignore = true
                    return
                end
            end

            local command = singleCommands[cmdString]
            local isBuffered = bufferedCommands[cmdString]

            if command then
                current.ignore = true
                inline:setText(input, current.text)
                command(input, current)
            elseif pendingCommands[cmdString] then
                current.pendingCommand = cmdString
                current.ignore = true
                inline:setText(input, current.text)
            elseif not isBuffered then
                inline:setText(input, current.text)
            end
        else
            inline:setText(input, current.text)
        end
    end
end

local function inputWatcher(input)
    actualInput = input
end

return function(module)
    module:setCategory "Editor"
    module:registerCommand("vim", showSwitcher)
    module:registerWatcher(watcher, inline.TYPE_TEXT_CHANGED)
    module:registerWatcher(inputWatcher, inline.TYPE_ALL_MASK)
    module:saveLazyLoad()
end
