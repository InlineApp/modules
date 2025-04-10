--[[

Pastebin

Модуль для мгновенной загрузки текста на pastebin.com

setpkey - Устанавливает ключ, который можно получить зарегистрировавшись на pastebin.com и перейдя на https://pastebin.com/doc_api#1

pbin text - Загружает текст на pastebin.com

by https://t.me/qhxfj

--]]

require "http"

local preferences = inline:getDefaultSharedPreferences()

local function setpkey(_, query)
    preferences:edit():putString("pkey", query:getArgs()):apply()
    query:answer "Success!"
end

local function pastebin(_, query)
    local body = http.buildFormBody(
            {
                api_dev_key = preferences:getString("pkey", ""),
                api_option = "paste",
                api_paste_code = query:getArgs()
            }
    )
    request = http.Request.Builder.new():url("https://pastebin.com/api/api_post.php"):post(body):build()
    http.call(
            request,
            function(_, _, data)
                query:answer(data)
            end
    )
end

return function(module)
    module:setCategory("Pastebin")
    module:registerCommand("pbin", pastebin, "Create new paste with pastebin")
    module:registerCommand("setpkey", setpkey, "Sets the pastebin key")
    module:saveLazyLoad()
end
