--[[

Porfirevich (=0.6.1)

Является "портом" porfirevich.ru

Нейросеть Порфирьевич дописывает любые тексты и стихи на русском языке.

text {pf}$ 

Является больше примером

by https://t.me/wavecat

--]]

require "com.wavecat.inline.libs.colorama"
require "com.wavecat.inline.libs.http"

colorama.init(inline)

local function pf(input, query)
    local json = luajava.newInstance("org.json.JSONObject")

    json:put("prompt", query:replaceExpression(""))
    json:put("length", 30)

    local request =
        http.Request.Builder.new():url("https://pelevin.gpt.dobro.ai/generate/"):post(
        http.buildBody(json:toString(), "application/json")
    ):build()

    query:answer(colorama.italic("loading..."))

    http.call(
        request,
        function(_, response, string)
            if response:code() ~= 200 then
                query:answer()
                return
            end

            local json = luajava.newInstance("org.json.JSONObject", string)
            query:answer(colorama.font(json:getJSONArray("replies"):getString(0), "#8AB4F8"))
        end
    )
end

return function(module)
    module:registerCommand("pf", colorama.wrap(pf), "Adds any texts and poems in Russian")
end
