local function uppercaseCyrillicOnly(text)
    local result = {}

    for uchar in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if uchar:find("[а-яёА-ЯЁ]") then
            local upperChar = string.upper(uchar)
            table.insert(result, upperChar)
        else
            table.insert(result, uchar)
        end
    end

    return table.concat(result)
end

local function cupper(input, query)
    local useAllText = query:getArgs() == ""
    if useAllText then
        inline:setText(input, uppercaseCyrillicOnly(query:replaceExpression("")))
    else
        query:answer(uppercaseCyrillicOnly(query:getArgs()))
    end
end

return function(module)
    module:registerCommand("cupper", cupper, "Converts only Cyrillic characters in the given string to uppercase")
end
