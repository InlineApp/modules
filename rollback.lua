require "menu"
require "windows"

local preferences = inline:getDefaultSharedPreferences()

local lastString
local lastState
local results = {}
local cursor = 1
local offset = 1

local buffer = {}
local viewer = false

local DEFAULT_BUFFER_SIZE = 2000
local bufferSize = preferences:getInt("rollback_buffer_size", DEFAULT_BUFFER_SIZE)

if bufferSize < 1 then
    bufferSize = DEFAULT_BUFFER_SIZE
end

local function startsWith(text, start)
    return text:sub(1, #start) == start
end

local function watcher(input)
    local text = inline:getText(input)

    if text == nil or text == "" or viewer then
        return
    end

    if lastString ~= nil and startsWith(text, lastString) then
        text = text:sub(#lastString + 1, #text)
        lastString = lastString .. text
        buffer[#buffer] = buffer[#buffer] .. text
    else
        lastString = text
        buffer[#buffer + 1] = text
        if #buffer > bufferSize then
            table.remove(buffer, 1)
        end
    end
end

local createMenu

local function createSetStepMenu(_, query)
    local result = { "Step: " }

    for i = 1, 20 do
        table.insert(result, {
            caption = "[" .. i .. "]",
            action = function(input, query_)
                offset = i
                createMenu(input, query_)
            end
        })
        table.insert(result, " ")
    end

    menu.create(query, result, createMenu)
end

function createMenu(_, query)
    if cursor > #results then
        cursor = 1
    elseif cursor < 1 then
        cursor = #results
    end

    viewer = true

    local offsetText = offset == 1 and "" or tostring(offset)

    local result = {
        results[cursor],
        "\n",
        tostring(cursor),
        "/",
        tostring(#results),
        " ",
        {
            caption = "[ <" .. offsetText .. " ]",
            action = function(input_, query_)
                cursor = cursor - offset
                createMenu(input_, query_)
            end,
        },
        " ",
        {
            caption = "[ " .. offsetText .. "> ]",
            action = function(input_, query_)
                cursor = cursor + offset
                createMenu(input_, query_)
            end
        },
        " ",
        {
            caption = "[Set step]",
            action = function(input_, query_)
                createSetStepMenu(input_, query_)
            end
        },
        " ",
        {
            caption = "[Ok]",
            action = function(input_, _)
                viewer = false
                inline:setText(input_, results[cursor])
            end
        }
    }

    menu.create(query, result, function(input_)
        viewer = false
        inline:setText(input_, lastState)
    end)
end

local function findResults(query)
    if query:getArgs() == "" then
        results = buffer
    else
        results = {}

        for _, v in ipairs(buffer) do
            if v:find(query:getArgs()) ~= nil then
                results[#results + 1] = v
            end
        end
    end

    if #results == 0 then
        query:answer("Not found")
        return false
    end

    cursor = #results
    return true
end

local function back(input, query)
    if not findResults(query) then
        return
    end

    lastState = query:replaceExpression("")
    createMenu(input, query)
end

local function showCurrentResult(input)
    if cursor > #results then
        cursor = 1
    elseif cursor < 1 then
        cursor = #results
    end

    inline:setText(input, results[cursor] .. "\n[" .. cursor .. "/" .. #results .. "]")
end

local function fback(input, query)
    if not findResults(query) then
        return
    end

    showCurrentResult(input)
    viewer = true

    windows.createAligned(input, {
        noBackground = true,
        position = "below",
        onClose = function()
            viewer = false
        end
    }, function(ui)
        local offsetText = offset == 1 and "" or " " .. offset

        local undo = ui.button("Undo" .. offsetText, function()
            cursor = cursor - offset
            showCurrentResult(input)
        end)

        local redo = ui.button("Redo" .. offsetText, function()
            cursor = cursor + offset
            showCurrentResult(input)
        end)

        local ok = ui.button("Ok", function()
            inline:setText(input, results[cursor])
            ui:close()
        end)

        undo:setMinimumWidth(0)
        redo:setMinimumWidth(0)
        ok:setMinimumWidth(0)

        undo:setMinWidth(0)
        redo:setMinWidth(0)
        ok:setMinWidth(0)

        local setSteps = ui.seekBar(nil, 19)
                           :setOnProgressChanged(function(i)
            offset = i + 1
            local offsetText_ = offset == 1 and "" or offset
            undo:setText("Undo " .. offsetText_)
            redo:setText("Redo " .. offsetText_)
        end)

        setSteps:setVisibility(setSteps.GONE)

        local function showSteps()
            setSteps:setVisibility(setSteps.VISIBLE)
        end

        ui.setOnLongClickListener(redo, showSteps)
        ui.setOnLongClickListener(undo, showSteps)

        return {
            {
                undo,
                ui.spacer(4),
                redo,
                ui.spacer(4),
                ok,
            },
            ui.spacer(4),
            setSteps
        }
    end)
end

local function ftime(input, query)
    if not findResults(query) then
        return
    end

    viewer = true
    lastState = query:replaceExpression("")

    local box = windows.getBoundsInScreen(input)

    windows.createAligned(input, {
        position = "below",
        onClose = function()
            viewer = false
        end
    }, function(ui)
        local seekBar = ui.seekBar(nil, #results)
                          :setOnProgressChanged(function(i)
            cursor = i
            inline:setText(input, results[cursor])
        end)

        seekBar:setMinWidth(box:width())
        seekBar:setProgress(#results)

        return {
            seekBar,
            ui.spacer(8),
            {
                ui.button("Cancel", function()
                    inline:setText(input, lastState)
                    ui:close()
                end),
                ui.spacer(8),
                ui.button("Apply", function()
                    ui:close()
                end)
            }
        }
    end)
end

local function finder()
    if viewer then
        return function()
        end
    end
end

local function getPreferences(prefs)
    return {
        prefs.textInput("rollback_buffer_size", "Buffer size (edits count)")
             :setDefault(DEFAULT_BUFFER_SIZE)
             :setListener(function(s)
            if bufferSize > 1 then
                bufferSize = tonumber(s)
            end
        end)
             :useInt()
             :setInputType({ "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" }),
        prefs.spacer(8)
    }
end

return function(module)
    module:setCategory("Roll")
    module:registerCommand("back", back)

    if (windows.isSupported()) then
        module:registerCommand("fback", fback)
        module:registerCommand("ftime", ftime)
    end

    module:setCategory("Rollback")
    module:registerWatcher(watcher)
    module:registerCommandFinder(finder)
    module:registerPreferences(getPreferences)
end
