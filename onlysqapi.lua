--[[

OnlySq API (v1.1)

Использование ИИ используя OnlySq API(https://onlysq.ru)

Доступные модели: gpt-4o-mini, gemini

by https://t.me/ImSkaiden

--]]

require "menu"
require "http"
require "json"
require "utils"

local apiUrl = "https://api.onlysq.ru/ai/"
local prefs = inline:getDefaultSharedPreferences()
local availableModels = { "gpt-4o-mini", "gemini" }

local TimeUnit = luajava.bindClass "java.util.concurrent.TimeUnit"

local client = http(
        http.newBuilder()
            :readTimeout(60, TimeUnit.SECONDS)
            :writeTimeout(60, TimeUnit.SECONDS)
            :callTimeout(60, TimeUnit.SECONDS
        )   :build()
)

local function getPreferences(builder)
    return {
        builder.checkBox("v1_use", "Использовать v1"):setDefault(true),
        --builder.text("Текущая модель: "..prefs:getString("model")),
        builder.spacer(8),
        builder.text("Выберите модель"),
        builder.spinner("model", availableModels),
        builder.spacer(8),
        builder.button("Закрыть", function()
            builder:cancel()
        end),
    }
end

local function contains(table, element)
    for _, value in ipairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local sendRequest = function(question, query)
    local currentModel = prefs:getString("model")
    local v1_use = prefs:getBoolean("v1_use")
    --local data
    local jsonData
    if v1_use then
        jsonData = json.dump({
            {
                role = "user",
                content = tostring(question)
            }
        })
    else
        jsonData = json.dump({
            model = currentModel,
            request = {
                messages = {
                    {
                        role = "user",
                        content = question
                    }
                }
            }
        })
    end

    local url = apiUrl .. (v1_use and "v1" or "v2")
    local headers = http.buildHeaders({
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json" }
    )

    local request = http.Request.Builder.new()
                        :url(url)
                        :headers(headers)
                        :post(http.buildBody(jsonData, "application/json"))
                        :build()

    client.call(request, function(_, response, string)
        if response:isSuccessful() then
            local jsonResponse = json.load(string)
            query:answer(tostring(jsonResponse.answer))
        else
            query:answer("Request failed: " .. response:code())
            return

        end
    end, function(_, exception)
        query:answer("Request error: " .. exception)
    end)
end

return function(module)
    module:setCategory("OnlySq API")
    module:registerPreferences(getPreferences)
    module:registerCommand("setmodel", function(_, query)
        local model = query:getArgs()
        if prefs:getBoolean("v1_use") then
            query:answer("Используется v1, вы не можете сменить модель.")
            return
        end
        if not contains(availableModels, model) then
            query:answer("Модель " .. model " не найдена!\nДоступные модели: " .. availableModels)
            return
        end
        prefs:edit("model"):putString("model", model):apply()
        query:answer("Установлена модель " .. colorama.bold(tostring(prefs:getString("model"))))
    end, "Установка модели для использования")

    module:registerCommand("gpt", function(_, query)
        query:answer("Thinking...")
        local question = query:getArgs()
        -- query:answer(question)
        if not question then
            query:answer("Вы не задали вопрос!\nDebug: " .. question)
            return
        end
        sendRequest(question, query)
    end, "Задать вопрос ИИ")
end