--[[

Person (Beta)

Генерирует случайного юзера

{person male}$
{person female}$
{person}$

by https://t.me/aye_ya

--]]

require "com.wavecat.inline.libs.http"

local baseurl = "https://randomuser.me/api/?format=json"

local function person(_, query)
    local request = http.Request.Builder.new():url(
        baseurl .. "&gender=" .. (query == "female" and "female&nat" or "male")
    ):get():build()

    query:answer "Loading"

    http.call(
        request,
        function(_, _, string)
            local json = json.load(string).results[1]
            result =
                string.format(
                "Name: %s %s\nAge: %d\nLocation: %s, %s\nPhoto: %s",
                json.name.first,
                json.name.last,
                json.dob.age,
                json.location.city,
                json.location.country,
                json.picture.large
            )
            query:answer(result)
        end
    )
end

return function(module)
    module:setCategory "Person"
    module:registerCommand("person", person, "Generates people")
end
