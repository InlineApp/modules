require "colorama"
require "http"

local preferences = inline:getDefaultSharedPreferences()

local DEFAULT_URL_PARAMS = "?m?M?0?q?T&lang=en"
local HEADERS = { ["User-Agent"] = "python-requests/2.32.3" }

local function weather(_, query)
    query:answer("Loading...")

    local city = query:getArgs()
    if city == "" then
        city = preferences:getString("wttr_in_city", "")
    end

    local params = preferences:getString("wttr_in_url_params", DEFAULT_URL_PARAMS)
    local hideFirstLine = preferences:getBoolean("wttr_in_hide_first_line", false)

    http.get({
        url = "https://wttr.in/" .. city .. params,
        headers = HEADERS
    },
        function(_, _, text)
            if hideFirstLine then
                text = text:gsub("^[^\n]*\n", "")
            else
                text = "Weather report: " .. text
            end

            local formatted = text:gsub("\n", "<br>"):gsub(" ", "&nbsp;")
            query:answer("<pre>" .. formatted .. "</pre>")
        end,
        function(_)
            query:answer "Error occurred"
        end)
end

return function(module)
    module:setCategory("wttr.in")
    module:registerCommand("weather", colorama.wrap(weather), "Display the current weather for a specified city")
    module:registerPreferences(function(prefs)
        local helpButton

        helpButton = prefs.button("Help", function()
            helpButton:setEnabled(false)
            http.get({
                url = "https://wttr.in/:help",
                headers = HEADERS
            },
                function(_, _, text)
                    helpButton:setEnabled(true)
                    prefs:create("Help", function(prefs2)
                        return {
                            prefs.spacer(16),
                            text,
                            prefs.button("I'm done", function()
                                prefs2:cancel()
                            end),
                            prefs.spacer(16)
                        }
                    end)
                end,
                function(_)
                    helpButton:setEnabled(true)
                    inline:toast "Error occurred"
                end)
        end)

        return {
            prefs.textInput("wttr_in_url_params", "wttr.in URL parameters")
                 :setDefault(DEFAULT_URL_PARAMS),
            prefs.spacer(8),
            helpButton,
            prefs.spacer(8),
            prefs.textInput("wttr_in_city", "Default city"),
            prefs.spacer(4),
            prefs.checkBox("wttr_in_hide_first_line", "Hide city")
                 :setDefault(false),
            prefs.spacer(4)
        }
    end)

    local aliases = inline:getSharedPreferences "aliases"
    if aliases:getString("w", "") == "" then
        aliases:edit():putString("w", "weather"):apply()
    end
end
