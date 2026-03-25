require "iutf8"
require "utils"
require "windows"
require "json"

local Color = require "android.graphics.Color"
local ColorStateList = require "android.content.res.ColorStateList"
local Query = require "com.wavecat.inline.service.commands.Query"
local ClipData = require "android.content.ClipData"

local prefs = inline:getSharedPreferences("hub")

local DEFAULT_BUTTONS = json.dump({
    { name = "Bold", command = "bold" },
    { name = "Italic", command = "italic" },
    { name = "B+I", command = "bolditalic" },
    { name = "Strike", command = "strike" },
    { name = "Case", command = "toggle" },
    { name = "Close", command = "hubclose", textColor = "#FF0000" },
})

local DEFAULT_SUB_BUTTONS = json.dump({
    { name = "Back", command = "hubback" },
    { name = "Close", command = "hubclose" },
})

local hubWindow
local paletteWindow
local hideTimer
local paletteTimer
local lastInput

local function parseColor(hex, fallback)
    if not hex or hex == "" then
        return fallback
    end
    local ok, color = pcall(function()
        if not hex:find("^#") then
            hex = "#" .. hex
        end
        return Color:parseColor(hex)
    end)
    return ok and color or fallback
end

local function buttonsKey(prefix)
    if not prefix or prefix == "" then
        return "buttons"
    end
    return "buttons_" .. prefix
end

local function getButtonConfigs(prefix)
    local key = buttonsKey(prefix)
    local default = (not prefix or prefix == "") and DEFAULT_BUTTONS or DEFAULT_SUB_BUTTONS
    local raw = prefs:getString(key, default)
    local ok, parsed = pcall(json.load, raw)
    return (ok and type(parsed) == "table") and parsed or {}
end

local function saveButtons(buttons, prefix)
    prefs:edit():putString(buttonsKey(prefix), json.dump(buttons)):apply()
end

local function getWhitelist()
    local raw = prefs:getString("whitelist", "[]")
    local ok, parsed = pcall(json.load, raw)
    return (ok and type(parsed) == "table") and parsed or {}
end

local function saveWhitelist(list)
    prefs:edit():putString("whitelist", json.dump(list)):apply()
end

local function isAppAllowed(packageName)
    local mode = prefs:getString("list_mode", "All apps")
    if mode == "All apps" then
        return true
    end
    local list = getWhitelist()
    if #list == 0 then
        return true
    end
    local found = false
    for _, pkg in ipairs(list) do
        if pkg == packageName then
            found = true
            break
        end
    end
    if mode == "Blacklist" then
        return not found
    end
    return found
end

local function matchesTrigger(text)
    local trigger = prefs:getString("trigger_suffix", "")
    return trigger == "" or utils.endsWith(text, trigger)
end

local function textLengthOk(text)
    local len = #text
    local minLen = prefs:getInt("min_length", 0)
    local maxLen = prefs:getInt("max_length", 0)
    if minLen > 0 and len < minLen then
        return false
    end
    if maxLen > 0 and len > maxLen then
        return false
    end
    return true
end

local function cancelHideTimer()
    if hideTimer then
        pcall(function()
            hideTimer:cancel()
        end)
        hideTimer = nil
    end
end

local function closeHub()
    cancelHideTimer()
    if hubWindow then
        pcall(function()
            hubWindow:close()
        end)
        hubWindow = nil
    end
end

local function cancelPaletteTimer()
    if paletteTimer then
        pcall(function()
            paletteTimer:cancel()
        end)
        paletteTimer = nil
    end
end

local function closePalette()
    cancelPaletteTimer()
    if paletteWindow then
        pcall(function()
            paletteWindow:close()
        end)
        paletteWindow = nil
    end
end

local function closeAll()
    closePalette()
    closeHub()
end

local function scheduleAutoHide()
    cancelHideTimer()
    local timeout = prefs:getInt("timeout", 2000)
    if timeout > 0 then
        hideTimer = inline:timerTask(function()
            closeAll()
        end)
        inline:getTimer():schedule(hideTimer, timeout)
    end
end

local function schedulePaletteHide()
    cancelPaletteTimer()
    local timeout = prefs:getInt("palette_timeout", 5000)
    if timeout > 0 then
        paletteTimer = inline:timerTask(function()
            closePalette()
        end)
        inline:getTimer():schedule(paletteTimer, timeout)
    end
end

local function styleButton(btn, textSize, textColor, bgColor, isTextStyle)
    if textSize and textSize > 0 then
        btn:setTextSize(textSize)
    end
    if textColor then
        local c = parseColor(textColor, nil)
        if c then
            btn:setTextColor(c)
        end
    end
    if isTextStyle then
        btn:setBackgroundTintList(ColorStateList:valueOf(0x00000000))
        btn:setStrokeWidth(0)
        btn:setElevation(0)
        btn:setRippleColor(ColorStateList:valueOf(0x20000000))
    elseif bgColor then
        local c = parseColor(bgColor, nil)
        if c then
            btn:setBackgroundTintList(ColorStateList:valueOf(c))
        end
    end
end

local MARKER = "\xEF\xBF\xBC" -- U+FFFC Object Replacement Character

local function charToByte(str, charPos)
    local bytePos = 0
    local chars = 0
    while chars < charPos and bytePos < #str do
        local b = str:byte(bytePos + 1)
        if b < 0x80 then
            bytePos = bytePos + 1
        elseif b < 0xE0 then
            bytePos = bytePos + 2
        elseif b < 0xF0 then
            bytePos = bytePos + 3
        else
            bytePos = bytePos + 4
        end
        chars = chars + 1
    end
    return bytePos
end

local function executeCommand(commandName, input, args)
    local command = inline:getAllCommands():get(commandName)
    if not command then
        inline:toast("Command not found: " .. commandName)
        return false
    end
    pcall(function()
        input:refresh()
    end)
    local text = inline:getText(input) or ""
    local cursorChar = tonumber(input:getTextSelectionStart()) or 0
    local bytePos = charToByte(text, cursorChar)
    local markedText = text:sub(1, bytePos) .. MARKER .. text:sub(bytePos + 1)
    local query = Query.new(input, markedText, MARKER, args or "")
    command:getCallable()(input, query)
    return true
end

local function showArgsDialog(commandName, input, argsTemplate)
    local hasTemplate = argsTemplate and argsTemplate ~= "" and argsTemplate:find("%%s")

    local placement = prefs:getString("placement", "")
    local posBelow = prefs:getString("position", "Below input") == "Below input"

    local config = {
        noLimits = true,
    }

    local function builder(ui)
        local argsInput = ui.textInput("Arguments for " .. commandName)

        local run = ui.smallButton("Run", function()
            local capturedNode = windows.getLastNode()
            if not capturedNode then
                return inline:toast "Focus on the target input field first"
            end
            local userInput = argsInput:getText()
            local args
            if hasTemplate then
                args = argsTemplate:gsub("%%s", userInput)
            else
                args = userInput
            end
            ui:close()
            executeCommand(commandName, capturedNode, args)
        end)

        run:setEnabled(windows.isInsertAvailable())

        ui.onFocusChanged = function(isFocused)
            run:setEnabled(not isFocused and windows.isInsertAvailable())
        end

        return {
            argsInput,
            ui.spacer(8),
            {
                run,
                ui.spacer(8),
                ui.smallButton("Close", function()
                    ui:close()
                end),
            },
        }
    end

    if placement == "Fixed position (X, Y)" then
        config.positionX = prefs:getInt("fixed_x", 0)
        config.positionY = prefs:getInt("fixed_y", 100)
        windows.create(config, builder)
    else
        config.position = posBelow and "below" or nil
        config.offsetX = prefs:getInt("offset_x", 0)
        config.offsetY = prefs:getInt("offset_y", -20)
        config.align = prefs:getString("align", "") == "Left" and "left" or "right"
        windows.createAligned(input, config, builder)
    end
end

local function showPalette(input, prefix, parentPrefix)
    closePalette()
    local buttons = getButtonConfigs(prefix)

    if #buttons == 0 then
        inline:toast "No buttons configured. Open Hub settings."
        return
    end

    local placement = prefs:getString("placement", "")
    local posBelow = prefs:getString("position", "Below input") == "Below input"

    local paletteBg = prefs:getString("palette_bg", "#000000")

    local config = {
        paddingLeft = 8,
        paddingRight = 8,
        paddingTop = 8,
        paddingBottom = 8,
        noBackground = paletteBg == "",
        onClose = function()
            paletteWindow = nil
            cancelPaletteTimer()
        end
    }

    if paletteBg ~= "" then
        local c = parseColor(paletteBg, nil)
        if c then
            config.backgroundColor = c
        end
    end

    local function builder(ui)
        local rows = {}
        local currentRow = {}
        local maxPerRow = prefs:getInt("columns", 7)
        local useSmall = prefs:getBoolean("palette_btn_small", true)

        for i, btn in ipairs(buttons) do
            local btnName = btn.name or ("Btn " .. i)
            local btnCommand = btn.command or ""
            local btnArgs = btn.args or ""

            local btnPalette = btn.palette or ""
            local btnAskArgs = btn.askArgs

            local b = (useSmall and ui.smallButton or ui.button)(btnName, function()
                local capturedNode = windows.getLastNode() or lastInput or input
                if btnCommand == "hubback" then
                    showPalette(capturedNode, parentPrefix)
                elseif btnPalette ~= "" then
                    showPalette(capturedNode, btnPalette, prefix)
                elseif btnCommand ~= "" then
                    closePalette()
                    if btnAskArgs then
                        showArgsDialog(btnCommand, capturedNode, btnArgs)
                    else
                        executeCommand(btnCommand, capturedNode, btnArgs)
                    end
                end
            end)

            if btn.color then
                local c = parseColor(btn.color, nil)
                if c then
                    b:setBackgroundTintList(ColorStateList:valueOf(c))
                end
            end
            if btn.textColor then
                local c = parseColor(btn.textColor, nil)
                if c then
                    b:setTextColor(c)
                end
            end

            currentRow[#currentRow + 1] = b

            if #currentRow >= maxPerRow or i == #buttons then
                if #currentRow > 1 then
                    for j = 1, #currentRow - 1 do
                        table.insert(currentRow, j * 2, ui.spacer(4))
                    end
                end
                rows[#rows + 1] = currentRow
                if i < #buttons then
                    rows[#rows + 1] = ui.spacer(4)
                end
                currentRow = {}
            end
        end

        return { ui.hscroll({ ui.vscroll(rows) }) }
    end

    if placement == "Fixed position (X, Y)" then
        config.positionX = prefs:getInt("fixed_x", 0)
        config.positionY = prefs:getInt("fixed_y", 100)
        paletteWindow = windows.create(config, builder)
    else
        config.position = posBelow and "below" or nil
        config.offsetX = prefs:getInt("offset_x", 0)
        config.offsetY = prefs:getInt("offset_y", -20)
        config.align = prefs:getString("align", "") == "Left" and "left" or "right"
        paletteWindow = windows.createAligned(input, config, builder)
    end

    schedulePaletteHide()
end

local function buildHubContent(ui, input)
    local label = prefs:getString("button_label", "Hub")
    local textSize = prefs:getInt("button_text_size", 0)
    local textColor = prefs:getString("button_text_color", "")
    local bgColor = prefs:getString("button_bg_color", "")
    local isSmall = prefs:getBoolean("button_small", true)

    local onClick = function()
        if prefs:getBoolean("run_first_command", false) then
            local buttons = getButtonConfigs()
            if #buttons > 0 and buttons[1].command and buttons[1].command ~= "" then
                closeHub()
                executeCommand(buttons[1].command, input, buttons[1].args or "")
            else
                closeHub()
                showPalette(input)
            end
        else
            closeHub()
            showPalette(input)
        end
    end

    local btn = (isSmall and ui.smallButton or ui.button)(label, onClick)
    styleButton(btn, textSize, textColor, bgColor, false)
    return { { btn } }
end

local function showHub(input)
    if hubWindow or paletteWindow then
        return
    end

    local placement = prefs:getString("placement", "")
    local posBelow = prefs:getString("position", "Below input") == "Below input"

    local bgColor = prefs:getString("button_bg_color", "#000000")
    local isSmall = prefs:getBoolean("button_small", true)

    local config = {
        paddingLeft = 4,
        paddingRight = 4,
        paddingTop = 4,
        paddingBottom = 4,
        noLimits = true,
        noBackground = not isSmall,
        onClose = function()
            hubWindow = nil
            cancelHideTimer()
        end
    }

    if isSmall and bgColor ~= "" then
        local c = parseColor(bgColor, nil)
        if c then
            config.backgroundColor = c
        end
    end

    if placement == "Fixed position (X, Y)" then
        config.positionX = prefs:getInt("fixed_x", 0)
        config.positionY = prefs:getInt("fixed_y", 100)
        hubWindow = windows.create(config, function(ui)
            return buildHubContent(ui, input)
        end)
    else
        config.position = posBelow and "below" or nil
        config.offsetX = prefs:getInt("offset_x", 0)
        config.offsetY = prefs:getInt("offset_y", -20)
        config.align = prefs:getString("align", "") == "Left" and "left" or "right"
        hubWindow = windows.createAligned(input, config, function(ui)
            return buildHubContent(ui, input)
        end)
    end

    scheduleAutoHide()
end

local function watcher(input, eventType)
    lastInput = input

    local isSelection = eventType == inline.TYPE_SELECTION_CHANGED

    if not prefs:getBoolean("enabled", true) then
        closeAll()
        return
    end

    if isSelection and not prefs:getBoolean("trigger_on_selection", true) then
        return
    end

    local pkg = input:getPackageName()
    if pkg then
        pkg = tostring(pkg)
        if not isAppAllowed(pkg) then
            closeAll()
            return
        end
    end

    if isSelection then
        showHub(input)
        return
    end

    local text = inline:getText(input) or ""

    if not textLengthOk(text) or not matchesTrigger(text) then
        closeAll()
        return
    end

    if prefs:getBoolean("trigger_open_palette", false) and matchesTrigger(text) then
        if not paletteWindow then
            showPalette(input)
        end
        return
    end

    showHub(input)
end

local function hubAddApp(_, query)
    local pkg = query:getArgs()
    if pkg == "" then
        local last = windows.getLastPackage()
        if last then
            pkg = tostring(last)
        else
            return inline:toast "Usage: hubadd <package.name> or focus on an app first"
        end
    end

    local list = getWhitelist()
    for _, p in ipairs(list) do
        if p == pkg then
            return inline:toast(pkg .. " is already in whitelist")
        end
    end
    list[#list + 1] = pkg
    saveWhitelist(list)
    inline:toast("Added to whitelist: " .. pkg)
    query:answer()
end

local function hubDelApp(_, query)
    local pkg = query:getArgs()
    if pkg == "" then
        return inline:toast "Usage: hubdel <package.name>"
    end

    local list = getWhitelist()
    local newList = {}
    local found = false
    for _, p in ipairs(list) do
        if p == pkg then
            found = true
        else
            newList[#newList + 1] = p
        end
    end

    if not found then
        return inline:toast(pkg .. " is not in whitelist")
    end

    saveWhitelist(newList)
    inline:toast("Removed from whitelist: " .. pkg)
    query:answer()
end

local function hubApps(_, query)
    local list = getWhitelist()
    if #list == 0 then
        inline:toast "Whitelist is empty (Hub works in all apps)"
    else
        inline:toast("Whitelist:\n" .. table.concat(list, "\n"))
    end
    query:answer()
end

--Preferences

local showMainPrefs
local showButtonsList

local function showEditButton(builder, buttons, index, prefix)
    local btn = buttons[index]
    builder:cancel()
    builder:create("Edit button #" .. index, function()
        local nameInput = builder.textInput "Name"
        nameInput:setText(btn.name or "")

        local cmdInput = builder.textInput "Command"
        cmdInput:setText(btn.command or "")

        local argsInput = builder.textInput "Arguments (use %s as placeholder for input)"
        argsInput:setText(btn.args or "")

        local paletteInput = builder.textInput "Sub-palette prefix (opens palette instead)"
        paletteInput:setText(btn.palette or "")

        local askArgsSwitch = builder.switch("", "Ask for arguments before running")
        askArgsSwitch:setChecked(btn.askArgs == true)

        local colorInput = builder.textInput "Background color (#FF0000)"
        colorInput:setText(btn.color or "")

        local textColorInput = builder.textInput "Text color (#FFFFFF)"
        textColorInput:setText(btn.textColor or "")

        local items = {
            nameInput,
            builder.spacer(12),
            cmdInput,
            builder.spacer(12),
            argsInput,
            builder.spacer(12),
            askArgsSwitch,
            builder.spacer(12),
            paletteInput,
            builder.spacer(12),
            colorInput,
            builder.spacer(12),
            textColorInput,
        }

        if btn.palette and btn.palette ~= "" then
            items[#items + 1] = builder.spacer(16)
            items[#items + 1] = builder.smallButton("Edit sub-palette: " .. btn.palette, function()
                builder:cancel()
                showButtonsList(builder, btn.palette)
            end)
        end

        items[#items + 1] = builder.spacer(20)
        items[#items + 1] = {
            builder.button("Save", function()
                btn.name = nameInput:getText()
                btn.command = cmdInput:getText()

                local args = argsInput:getText()
                btn.args = args ~= "" and args or nil

                btn.askArgs = askArgsSwitch:isChecked() or nil

                local pal = paletteInput:getText()
                btn.palette = pal ~= "" and pal or nil

                local color = colorInput:getText()
                btn.color = color ~= "" and color or nil

                local tc = textColorInput:getText()
                btn.textColor = tc ~= "" and tc or nil

                buttons[index] = btn
                saveButtons(buttons, prefix)
                builder:cancel()
                showButtonsList(builder, prefix)
            end),
            builder.spacer(12),
            builder.button("Cancel", function()
                builder:cancel()
                showButtonsList(builder, prefix)
            end),
        }

        return items
    end)
end

local function showAddButton(builder, prefix)
    builder:cancel()
    builder:create("Add palette button", function()
        local nameInput = builder.textInput "Name"
        local cmdInput = builder.textInput "Command"
        local argsInput = builder.textInput "Arguments (optional)"
        local paletteInput = builder.textInput "Sub-palette prefix (opens palette instead)"
        local colorInput = builder.textInput "Background color (#FF0000)"
        local textColorInput = builder.textInput "Text color (#FFFFFF)"

        return {
            nameInput,
            builder.spacer(12),
            cmdInput,
            builder.spacer(12),
            argsInput,
            builder.spacer(12),
            paletteInput,
            builder.spacer(12),
            colorInput,
            builder.spacer(12),
            textColorInput,
            builder.spacer(20),
            {
                builder.button("Add", function()
                    local name = nameInput:getText()
                    local cmd = cmdInput:getText()
                    local pal = paletteInput:getText()
                    if name == "" or (cmd == "" and pal == "") then
                        return inline:toast "Name and command or palette are required"
                    end

                    local entry = { name = name, command = cmd }

                    local args = argsInput:getText()
                    if args ~= "" then
                        entry.args = args
                    end

                    if pal ~= "" then
                        entry.palette = pal
                    end

                    local color = colorInput:getText()
                    if color ~= "" then
                        entry.color = color
                    end

                    local tc = textColorInput:getText()
                    if tc ~= "" then
                        entry.textColor = tc
                    end

                    local buttons = getButtonConfigs(prefix)
                    buttons[#buttons + 1] = entry
                    saveButtons(buttons, prefix)

                    builder:cancel()
                    showButtonsList(builder, prefix)
                end),
                builder.spacer(12),
                builder.button("Cancel", function()
                    builder:cancel()
                    showButtonsList(builder, prefix)
                end),
            }
        }
    end)
end

local function showDeleteConfirm(builder, buttons, index, prefix)
    builder:cancel()
    builder:create("Delete \"" .. (buttons[index].name or "?") .. "\"?", function()
        return {
            "This will remove the button from the palette.",
            builder.spacer(20),
            {
                builder.flexSpacer(),
                builder.button("Yes", function()
                    table.remove(buttons, index)
                    saveButtons(buttons, prefix)
                    builder:cancel()
                    showButtonsList(builder, prefix)
                end),
                builder.spacer(16),
                builder.button("No", function()
                    builder:cancel()
                    showButtonsList(builder, prefix)
                end),
            },
        }
    end)
end

showButtonsList = function(builder, prefix)
    builder:cancel()
    local title = prefix and prefix ~= "" and ("Palette: " .. prefix) or "Palette buttons"
    builder:create(title, function()
        local buttons = getButtonConfigs(prefix)
        local items = {}

        if #buttons == 0 then
            items[#items + 1] = builder.text "No buttons configured"
            items[#items + 1] = builder.spacer(16)
        else
            for i, btn in ipairs(buttons) do
                local hasPalette = btn.palette and btn.palette ~= ""
                local cardItems = {}

                local infoRow = {
                    builder.text(btn.name or "?"):bold(),
                    builder.spacer(4),
                }
                if hasPalette then
                    infoRow[#infoRow + 1] = builder.text("palette: " .. btn.palette):italic():size(13)
                else
                    infoRow[#infoRow + 1] = builder.text(btn.command or "?"):italic():size(13)
                    if btn.args and btn.args ~= "" then
                        infoRow[#infoRow + 1] = builder.spacer(4)
                        infoRow[#infoRow + 1] = builder.text(btn.args):size(12)
                    end
                end
                cardItems[#cardItems + 1] = infoRow

                cardItems[#cardItems + 1] = builder.spacer(6)

                local actionsRow = {}
                if i > 1 then
                    actionsRow[#actionsRow + 1] = builder.smallButton("Up", function()
                        buttons[i], buttons[i - 1] = buttons[i - 1], buttons[i]
                        saveButtons(buttons, prefix)
                        showButtonsList(builder, prefix)
                    end)
                    actionsRow[#actionsRow + 1] = builder.spacer(4)
                end
                if i < #buttons then
                    actionsRow[#actionsRow + 1] = builder.smallButton("Down", function()
                        buttons[i], buttons[i + 1] = buttons[i + 1], buttons[i]
                        saveButtons(buttons, prefix)
                        showButtonsList(builder, prefix)
                    end)
                    actionsRow[#actionsRow + 1] = builder.spacer(4)
                end
                if hasPalette then
                    actionsRow[#actionsRow + 1] = builder.smallButton("Open palette", function()
                        showButtonsList(builder, btn.palette)
                    end)
                    actionsRow[#actionsRow + 1] = builder.spacer(4)
                end
                actionsRow[#actionsRow + 1] = builder.smallButton("Edit", function()
                    showEditButton(builder, buttons, i, prefix)
                end)
                actionsRow[#actionsRow + 1] = builder.spacer(4)
                actionsRow[#actionsRow + 1] = builder.smallButton("Delete", function()
                    showDeleteConfirm(builder, buttons, i, prefix)
                end)
                cardItems[#cardItems + 1] = actionsRow

                local card = builder.card(cardItems)
                if btn.color and btn.color ~= "" then
                    local c = parseColor(btn.color, nil)
                    if c then
                        card:setCardBackgroundColor(c)
                    end
                end
                items[#items + 1] = card
                items[#items + 1] = builder.spacer(8)
            end
        end

        items[#items + 1] = builder.spacer(12)
        items[#items + 1] = {
            builder.button("Back", function()
                builder:cancel()
                if prefix and prefix ~= "" then
                    showButtonsList(builder)
                else
                    showMainPrefs(builder)
                end
            end),
            builder.spacer(12),
            builder.button("Add", function()
                showAddButton(builder, prefix)
            end),
            builder.spacer(12),
            builder.button("Delete all", function()
                builder:cancel()
                builder:create("Delete all buttons?", function()
                    return {
                        builder.text "This will remove all buttons from the palette.",
                        builder.spacer(20),
                        {
                            builder.flexSpacer(),
                            builder.button("Delete", function()
                                saveButtons({}, prefix)
                                builder:cancel()
                                showButtonsList(builder, prefix)
                            end),
                            builder.spacer(12),
                            builder.button("Cancel", function()
                                builder:cancel()
                                showButtonsList(builder, prefix)
                            end),
                        },
                    }
                end)
            end),
        }

        items[#items + 1] = builder.spacer(16)
        items[#items + 1] = builder.smallButton("Fill all commands", function()
            local allButtons = {}
            for name in utils.mapEntries(inline:getAllCommands()) do
                allButtons[#allButtons + 1] = { name = name, command = name }
            end
            saveButtons(allButtons, prefix)
            showButtonsList(builder, prefix)
        end)

        return items
    end)
end

local function buildPrefsItems(b)
    local items = {}
    local enabled = prefs:getBoolean("enabled", true)
    local placement = prefs:getString("placement", "")
    local hasTrigger = prefs:getString("trigger_suffix", "") ~= ""

    items[#items + 1] = b.switch("enabled", "Enable Hub"):setDefault(true)

    if not enabled then
        return items
    end

    items[#items + 1] = b.spacer(16)

    local triggerCard = {
        b.text "Trigger":bold():size(16),
        b.spacer(8),
        b.text "Show hub only when text ends with a specific string":size(14),
        b.spacer(12),
        b.textInput("trigger_suffix", "Trigger suffix (empty = always)")
         :setDefault(""),
        b.spacer(12),
        b.chip("trigger_on_selection", "Trigger on selection change"):setDefault(true),
    }

    if hasTrigger then
        triggerCard[#triggerCard + 1] = b.spacer(12)
        triggerCard[#triggerCard + 1] = b.switch("trigger_open_palette", "Open palette directly"):setDefault(false)
        triggerCard[#triggerCard + 1] = b.spacer(16)
        triggerCard[#triggerCard + 1] = b.text "Text length filter":bold():size(14)
        triggerCard[#triggerCard + 1] = b.spacer(8)
        triggerCard[#triggerCard + 1] = b.slider("min_length", 500):setDefault(0):useInt()
        triggerCard[#triggerCard + 1] = b.text "Min length (0 = no limit)":size(13)
        triggerCard[#triggerCard + 1] = b.spacer(8)
        triggerCard[#triggerCard + 1] = b.slider("max_length", 500):setDefault(0):useInt()
        triggerCard[#triggerCard + 1] = b.text "Max length (0 = no limit)":size(13)
    end

    items[#items + 1] = b.card(triggerCard)
    items[#items + 1] = b.spacer(16)

    items[#items + 1] = b.card {
        b.text "App Filter":bold():size(16),
        b.spacer(12),
        b.spinner("list_mode", { "All apps", "Whitelist", "Blacklist" }),
        b.spacer(8),
        b.text "All apps: works everywhere\nWhitelist: only listed apps\nBlacklist: all except listed":size(13),
        b.spacer(12),
        b.text "Manage apps via commands: hubadd, hubdel, hubapps":italic():size(13),
    }

    items[#items + 1] = b.spacer(16)

    items[#items + 1] = b.card {
        b.text "Hub Button":bold():size(16),
        b.spacer(12),
        b.textInput("button_label", "Button label"):setDefault("Hub"),
        b.spacer(12),
        b.chip("button_small", "Small button"):setDefault(true),
        b.spacer(12),
        b.slider("button_text_size", 40):setDefault(0):useInt(),
        b.text "Text size in sp (0 = default)":size(13),
        b.spacer(12),
        b.textInput("button_text_color", "Text color (#FF5722)"):setDefault(""),
        b.spacer(8),
        b.textInput("button_bg_color", "Background color (#2196F3)"):setDefault("#000000"),
    }

    items[#items + 1] = b.spacer(16)

    local posCard = {
        b.text "Positioning":bold():size(16),
        b.spacer(12),
        b.spinner("placement", { "Aligned to input", "Fixed position (X, Y)" }),
        b.spacer(12),
    }

    if placement == "Fixed position (X, Y)" then
        posCard[#posCard + 1] = b.slider("fixed_x", -windows.getScreenWidth(), windows.getScreenWidth()):setDefault(0):useInt()
        posCard[#posCard + 1] = b.text "Position X (px)":size(13)
        posCard[#posCard + 1] = b.spacer(8)
        posCard[#posCard + 1] = b.slider("fixed_y", -windows.getScreenWidth(), windows.getScreenHeight()):setDefault(100):useInt()
        posCard[#posCard + 1] = b.text "Position Y (px)":size(13)
    else
        posCard[#posCard + 1] = b.spinner("position", { "Below input", "Above input" })
        posCard[#posCard + 1] = b.spacer(8)
        posCard[#posCard + 1] = b.spinner("align", { "Right", "Left" })
        posCard[#posCard + 1] = b.spacer(12)
        posCard[#posCard + 1] = b.slider("offset_x", -300, 300, 5):setDefault(0):useInt()
        posCard[#posCard + 1] = b.text "Offset X (dp)":size(13)
        posCard[#posCard + 1] = b.spacer(8)
        posCard[#posCard + 1] = b.slider("offset_y", -300, 300, 5):setDefault(-20):useInt()
        posCard[#posCard + 1] = b.text "Offset Y (dp)":size(13)
    end

    items[#items + 1] = b.card(posCard)
    items[#items + 1] = b.spacer(16)

    items[#items + 1] = b.card {
        b.text "Timers":bold():size(16),
        b.spacer(12),
        b.slider("timeout", 10000):setDefault(2000):setStep(100):useInt(),
        b.text "Button auto-hide (ms, 0 = never)":size(13),
        b.spacer(12),
        b.slider("palette_timeout", 15000):setDefault(5000):setStep(100):useInt(),
        b.text "Palette auto-hide (ms, 0 = never)":size(13),
    }

    items[#items + 1] = b.spacer(16)

    items[#items + 1] = b.card {
        b.text "Palette":bold():size(16),
        b.spacer(12),
        b.chip("palette_btn_small", "Small buttons"):setDefault(true),
        b.spacer(12),
        b.slider("columns", 15):setDefault(7):useInt(),
        b.text "Buttons per row":size(13),
        b.spacer(12),
        b.textInput("palette_bg", "Background color (#2196F3, empty = transparent)"):setDefault("#000000"),
        b.spacer(12),
        b.switch("keep_palette_open", "Keep palette open after command"):setDefault(false),
        b.spacer(12),
        b.switch("run_first_command", "Run first command directly"):setDefault(false),
        b.spacer(4),
        b.text "Execute the first palette button command instead of opening palette":size(13),
        b.spacer(16),
        b.button("Manage buttons", function()
            showButtonsList(b)
        end),
    }

    items[#items + 1] = b.spacer(20)

    items[#items + 1] = b.button("Reset all settings", function()
        b:cancel()
        b:create("Reset all settings?", function()
            return {
                b.text "This will reset all Hub settings to defaults.",
                b.spacer(20),
                {
                    b.flexSpacer(),
                    b.button("Reset", function()
                        prefs:edit():clear():apply()
                        inline:toast "Hub settings reset"
                        b:cancel()
                    end),
                    b.spacer(12),
                    b.button("Cancel", function()
                        b:cancel()
                        showMainPrefs(b)
                    end),
                },
            }
        end)
    end)

    return items
end

showMainPrefs = function(builder)
    builder:cancel()
    builder:create("Hub settings", function()
        return buildPrefsItems(builder)
    end)
end

local function getPreferences(builder)
    return buildPrefsItems(builder)
end

local function getClipboard()
    return inline:getSystemService(inline.CLIPBOARD_SERVICE)
end

local function formatSelection(input, tag)
    input:refresh()

    local text = inline:getText(input)
    local selStart = input:getTextSelectionStart()
    local selEnd = input:getTextSelectionEnd()

    if selStart < 0 then
        selStart = 0
    end
    if selEnd < 0 then
        selEnd = 0
    end

    if selStart == selEnd then
        selStart = 0
        selEnd = utf8.len(text)
    end

    inline:setSelection(input, selStart, selEnd)

    local selected = utf8.sub(text, selStart, selEnd)
    local escaped = selected:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br>")
    local html = escaped
    for t in tag:gmatch("[^,]+") do
        html = "<" .. t .. ">" .. html .. "</" .. t .. ">"
    end

    local clip = ClipData:newHtmlText("fmt", selected, html)
    getClipboard():setPrimaryClip(clip)
    inline:paste(input)
end

return function(module)
    module:setCategory "Hub"

    if windows.isSupported() then
        windows.supportInsert()
        module:registerWatcher(watcher, inline.TYPE_ALL_MASK)
    end

    module:registerCommand("hubclose", function(_, query)
        closeAll()
        query:answer()
    end, "Close Hub palette")

    module:registerCommand("hubback", function(_, query)
        closePalette()
        query:answer()
    end, "Go back in Hub palette")

    module:registerCommand("hubadd", hubAddApp, "Add app to Hub whitelist")
    module:registerCommand("hubdel", hubDelApp, "Remove app from Hub whitelist")
    module:registerCommand("hubapps", hubApps, "Show Hub whitelist")

    module:registerCommand("bold", function(input)
        formatSelection(input, "b")
    end, "Makes selected text bold")
    module:registerCommand("italic", function(input)
        formatSelection(input, "i")
    end, "Makes selected text italic")
    module:registerCommand("strike", function(input)
        formatSelection(input, "strike")
    end, "Makes selected text strikethrough")
    module:registerCommand("bolditalic", function(input)
        formatSelection(input, "b,i")
    end, "Makes selected text bold and italic")

    module:registerPreferences(prefs, getPreferences)
end
