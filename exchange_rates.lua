require "windows"

if not windows:isSupported() then
    inline:toast "The module is not supported on this version of Android"
    return
end

require "http"
require "json"
require "iutf8"

local Pattern = require "java.util.regex.Pattern"

local timer = inline:getTimer()
local currencyAliases = {
    ["руб"] = "rub",
    ["грн"] = "uah",
    ["бун"] = "byn",
    ["буны"] = "byn",
    ["бр"] = "byn",
    ["буна"] = "byn",
    ["белруб"] = "byn",
    ["рубль"] = "rub",
    ["рублей"] = "rub",
    ["гривна"] = "uah",
    ["гривен"] = "uah",
    ["евро"] = "eur",
    ["доллар"] = "usd",
    ["долларов"] = "usd",
    ["тенге"] = "kzt",
    ["тон"] = "ton",
    ["тонкойн"] = "ton",
    ["йен"] = "jpy",
    ["€"] = "eur",
    ["₽"] = "rub",
    ["¥"] = "jpy",
    ["£"] = "gbp",
    ["₿"] = "btc",
}

local DEFAULT_CURRENCIES = "rub,usd,ton"
local DEFAULT_WINDOW_TIMEOUT = 3000
local DEFAULT_WINDOW_OFFSET = 25
local CURRENCY_API_BASE_URL = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/"

local function buildPattern()
    local patternBase = { "(?:\\b|\\s)(\\d+(?:[\\,\\.]\\d+)?)([кk]{0,3}?)\\s*(\\$|1inch|aave|ada|aed|afn|akt|algo|all|amd|amp|ang|aoa|ape|apt|ar|arb|ars|atom|ats|aud|avax|awg|axs|azm|azn|bake|bam|bat|bbd|bch|bdt|bef|bgn|bhd|bif|bmd|bnb|bnd|bob|brl|bsd|bsv|bsw|btc|btcb|btg|btn|btt|busd|bwp|byn|byr|bzd|cad|cake|cdf|celo|cfx|chf|chz|clp|cnh|cny|comp|cop|crc|cro|crv|cspr|cuc|cup|cve|cvx|cyp|czk|dai|dash|dcr|dem|dfi|djf|dkk|doge|dop|dot|dydx|dzd|eek|egld|egp|enj|eos|ern|esp|etb|etc|eth|eur|fei|fil|fim|fjd|fkp|flow|flr|frax|frf|ftt|fxs|gala|gbp|gel|ggp|ghc|ghs|gip|gmd|gmx|gnf|gno|grd|grt|gt|gtq|gusd|gyd|hbar|hkd|hnl|hnt|hot|hrk|ht|htg|huf|icp|idr|iep|ils|imp|imx|inj|inr|iqd|irr|isk|itl|jep|jmd|jod|jpy|kas|kava|kcs|kda|kes|kgs|khr|klay|kmf|knc|kpw|krw|ksm|kwd|kyd|kzt|lak|lbp|ldo|leo|link|lkr|lrc|lrd|lsl|ltc|ltl|luf|luna|lunc|lvl|lyd|mad|mana|mbx|mdl|mga|mgf|mina|mkd|mkr|mmk|mnt|mop|mro|mru|mtl|mur|mvr|mwk|mxn|mxv|myr|mzm|mzn|nad|near|neo|nexo|nft|ngn|nio|nlg|nok|npr|nzd|okb|omr|one|op|ordi|pab|paxg|pen|pepe|pgk|php|pkr|pln|pte|pyg|qar|qnt|qtum|rol|ron|rpl|rsd|rub|rune|rvn|rwf|sand|sar|sbd|scr|sdd|sdg|sek|sgd|shib|shp|sit|skk|sle|sll|snx|sol|sos|spl|srd|srg|std|stn|stx|sui|svc|syp|szl|thb|theta|tjs|tmm|tmt|tnd|ton|top|trl|trx|try|ttd|tusd|tvd|twd|twt|tzs|uah|ugx|uni|usd|usdc|usdd|usdp|usdt|uyu|uzs|val|veb|ved|vef|ves|vet|vnd|vuv|waves|wemix|woo|wst|xaf|xag|xau|xaut|xbt|xcd|xch|xdc|xdr|xec|xem|xlm|xmr|xof|xpd|xpf|xpt|xrp|xtz|yer|zar|zec|zil|zmk|zmw|zwd|zwg|zwl" }

    for alias, _ in pairs(currencyAliases) do
        table.insert(patternBase, "|")
        table.insert(patternBase, alias)
    end

    table.insert(patternBase, ")(?:\\s|$)")

    return Pattern:compile(table.concat(patternBase, ""))
end

local preferences = inline:getDefaultSharedPreferences()

local currencyEmoji = {
    ["EUR"] = "🇪🇺",
    ["USD"] = "🇺🇸",
    ["CAD"] = "🇨🇦",
    ["AED"] = "🇦🇪",
    ["AFN"] = "🇦🇫",
    ["ALL"] = "🇦🇱",
    ["AMD"] = "🇦🇲",
    ["ANG"] = "🇨🇼",
    ["AOA"] = "🇦🇴",
    ["ARS"] = "🇦🇷",
    ["AUD"] = "🇦🇺",
    ["AWG"] = "🇦🇼",
    ["AZN"] = "🇦🇿",
    ["BAM"] = "🇧🇦",
    ["BDT"] = "🇧🇩",
    ["BGN"] = "🇧🇬",
    ["BHD"] = "🇧🇭",
    ["BIF"] = "🇧🇮",
    ["BND"] = "🇧🇳",
    ["BBD"] = "🇧🇧",
    ["BSD"] = "🇧🇸",
    ["BMD"] = "🇧🇲",
    ["BOB"] = "🇧🇴",
    ["BRL"] = "🇧🇷",
    ["BTN"] = "🇧🇹",
    ["BWP"] = "🇧🇼",
    ["BYN"] = "🇧🇾",
    ["BZD"] = "🇧🇿",
    ["CDF"] = "🇨🇩",
    ["CHF"] = "🇨🇭",
    ["CLP"] = "🇨🇱",
    ["CUC"] = "🇨🇺",
    ["CNY"] = "🇨🇳",
    ["COP"] = "🇨🇴",
    ["CUP"] = "🇨🇺",
    ["CRC"] = "🇨🇷",
    ["CVE"] = "🇨🇻",
    ["CZK"] = "🇨🇿",
    ["DJF"] = "🇩🇯",
    ["DKK"] = "🇩🇰",
    ["DOP"] = "🇩🇴",
    ["DZD"] = "🇩🇿",
    ["EEK"] = "🇪🇪",
    ["EGP"] = "🇪🇬",
    ["ERN"] = "🇪🇷",
    ["ETB"] = "🇪🇹",
    ["FKP"] = "🇫🇰",
    ["FJD"] = "🇫🇯",
    ["GBP"] = "🇬🇧",
    ["GEL"] = "🇬🇪",
    ["GHS"] = "🇬🇭",
    ["GIP"] = "🇬🇮",
    ["GNF"] = "🇬🇳",
    ["GTQ"] = "🇬🇹",
    ["GYD"] = "🇬🇾",
    ["GMD"] = "🇬🇲",
    ["GGP"] = "🇬🇬",
    ["HKD"] = "🇭🇰",
    ["HNL"] = "🇭🇳",
    ["HRK"] = "🇭🇷",
    ["HUF"] = "🇭🇺",
    ["HTG"] = "🇭🇹",
    ["IDR"] = "🇮🇩",
    ["ILS"] = "🇮🇱",
    ["IMP"] = "🇮🇲",
    ["INR"] = "🇮🇳",
    ["IQD"] = "🇮🇶",
    ["IRR"] = "🇮🇷",
    ["ISK"] = "🇮🇸",
    ["JMD"] = "🇯🇲",
    ["JOD"] = "🇯🇴",
    ["JPY"] = "🇯🇵",
    ["KGS"] = "🇰🇬",
    ["KHR"] = "🇰🇭",
    ["KMF"] = "🇰🇲",
    ["KPW"] = "🇰🇵",
    ["KRW"] = "🇰🇷",
    ["KWD"] = "🇰🇼",
    ["KYD"] = "🇰🇾",
    ["KZT"] = "🇰🇿",
    ["KES"] = "🇰🇪",
    ["LAK"] = "🇱🇦",
    ["LBP"] = "🇱🇧",
    ["LKR"] = "🇱🇰",
    ["LRD"] = "🇱🇷",
    ["LTL"] = "🇱🇹",
    ["LSL"] = "🇱🇸",
    ["LVL"] = "🇱🇻",
    ["LYD"] = "🇱🇾",
    ["MAD"] = "🇲🇦",
    ["MDL"] = "🇲🇩",
    ["MGA"] = "🇲🇬",
    ["MKD"] = "🇲🇰",
    ["MMK"] = "🇲🇲",
    ["MOP"] = "🇲🇴",
    ["MUR"] = "🇲🇺",
    ["MWK"] = "🇲🇼",
    ["MVR"] = "🇲🇻",
    ["MXN"] = "🇲🇽",
    ["MYR"] = "🇲🇾",
    ["MZN"] = "🇲🇿",
    ["NAD"] = "🇳🇦",
    ["NGN"] = "🇳🇬",
    ["NIO"] = "🇳🇮",
    ["NOK"] = "🇳🇴",
    ["NPR"] = "🇳🇵",
    ["NZD"] = "🇳🇿",
    ["OMR"] = "🇴🇲",
    ["PAB"] = "🇵🇦",
    ["PEN"] = "🇵🇪",
    ["PHP"] = "🇵🇭",
    ["PKR"] = "🇵🇰",
    ["PGK"] = "🇵🇬",
    ["PLN"] = "🇵🇱",
    ["PYG"] = "🇵🇾",
    ["QAR"] = "🇶🇦",
    ["RON"] = "🇷🇴",
    ["RSD"] = "🇷🇸",
    ["RUB"] = "🇷🇺",
    ["RWF"] = "🇷🇼",
    ["SAR"] = "🇸🇦",
    ["SCR"] = "🇸🇨",
    ["WST"] = "🇼🇸",
    ["SBD"] = "🇸🇧",
    ["SVC"] = "🇸🇻",
    ["SDG"] = "🇸🇩",
    ["SRD"] = "🇸🇷",
    ["SEK"] = "🇸🇪",
    ["SGD"] = "🇸🇬",
    ["SLL"] = "🇸🇱",
    ["SOS"] = "🇸🇴",
    ["SSP"] = "🇸🇸",
    ["STN"] = "🇸🇹",
    ["SHP"] = "🇸🇭",
    ["SYP"] = "🇸🇾",
    ["SZL"] = "🇸🇿",
    ["THB"] = "🇹🇭",
    ["TJS"] = "🇹🇭",
    ["TND"] = "🇹🇳",
    ["TOP"] = "🇹🇴",
    ["TRY"] = "🇹🇷",
    ["TMT"] = "🇹🇲",
    ["TTD"] = "🇹🇹",
    ["TWD"] = "🇹🇼",
    ["JEP"] = "🇯🇪",
    ["TZS"] = "🇹🇿",
    ["UAH"] = "🇺🇦",
    ["UGX"] = "🇺🇬",
    ["MRU"] = "🇲🇷",
    ["MNT"] = "🇲🇳",
    ["UYU"] = "🇺🇾",
    ["UZS"] = "🇺🇿",
    ["VEF"] = "🇻🇪",
    ["VND"] = "🇻🇳",
    ["VUV"] = "🇻🇺",
    ["XAF"] = "🇨🇫",
    ["XCD"] = "🇦🇬",
    ["XOF"] = "🇨🇮",
    ["XPF"] = "🇵🇫",
    ["YER"] = "🇾🇪",
    ["ZAR"] = "🇿🇦",
    ["ZMW"] = "🇿🇲",
    ["ZWL"] = "🇿🇼",
    ["1INCH"] = "💸",
    ["AAVE"] = "🔮",
    ["ADA"] = "🔷",
    ["AVAX"] = "❄️",
    ["AXS"] = "🪙",
    ["BAKE"] = "🍰",
    ["BAT"] = "🦇",
    ["BCH"] = "💵",
    ["BNB"] = "🏖️",
    ["BSV"] = "⚡",
    ["BTC"] = "💰",
    ["BUSD"] = "💵",
    ["CAKE"] = "🍰",
    ["CELO"] = "🌍",
    ["CHZ"] = "⚽",
    ["COMP"] = "⚖️",
    ["CRO"] = "🌍",
    ["CRV"] = "📉",
    ["DAI"] = "🪙",
    ["DASH"] = "⚡",
    ["DCR"] = "🔒",
    ["DOGE"] = "🐕",
    ["DOT"] = "🔵",
    ["DYDX"] = "📈",
    ["EGLD"] = "👑",
    ["ENJ"] = "⚙️",
    ["EOS"] = "🚀",
    ["ETH"] = "Ξ",
    ["FEI"] = "💎",
    ["FIL"] = "💾",
    ["FLOW"] = "🌊",
    ["FRAX"] = "💰",
    ["FTT"] = "💲",
    ["GALA"] = "🎭",
    ["GMX"] = "📉",
    ["GNO"] = "🌐",
    ["GRT"] = "📊",
    ["LINK"] = "🔗",
    ["LTC"] = "💰",
    ["LUNA"] = "🌙",
    ["MKR"] = "👑",
    ["NEAR"] = "🚀",
    ["NEO"] = "🌱",
    ["NEXO"] = "🔐",
    ["NFT"] = "🖼️",
    ["OKB"] = "🔑",
    ["OP"] = "🟢",
    ["PAXG"] = "💰",
    ["PEPE"] = "🐸",
    ["QNT"] = "⚙️",
    ["QTUM"] = "💡",
    ["RPL"] = "🔧",
    ["RUNE"] = "🛡️",
    ["SAND"] = "🏖️",
    ["SHIB"] = "🐶",
    ["SOL"] = "🟣",
    ["SNX"] = "📉",
    ["SUI"] = "💎",
    ["THETA"] = "🎭",
    ["TON"] = "💎",
    ["TRX"] = "⚡",
    ["USDC"] = "💵",
    ["USDT"] = "💵",
    ["UNI"] = "🦄",
    ["USDD"] = "💰",
    ["XMR"] = "🕵️",
    ["XRP"] = "💳",
    ["XTZ"] = "🔮",
    ["ZEC"] = "🛡️",
    ["ZIL"] = "🔮"
}

local baseCurrencies = utils.split(preferences:getString("currencies", DEFAULT_CURRENCIES), ",")

local pattern = buildPattern()
currencyAliases["$"] = "usd"

local isLoading = false
local data = {}
local result = {}
local timestamp = os.time()
local bar

local function showBar(input)
    local text
    local tools
    local window

    local timerTask = inline:timerTask(function()
        window:close()
    end)

    window = windows.createAligned(input, {
        noLimits = true,
        paddingLeft = 8,
        paddingRight = 8,
        paddingBottom = 8,
        paddingTop = 8,
        offsetY = preferences:getInt("window_offset", DEFAULT_WINDOW_OFFSET),
        onMove = function()
            text:setPaddingRelative(12, 12, 12, 8)
            text:setTextSize(14)
            tools:setVisibility(tools.VISIBLE)
            timerTask:cancel()
        end,
        onClose = function()
            bar = nil
        end
    }, function(ui)
        text = ui.text ""
        text:setTextSize(12)

        local paste = ui.smallButton("Paste", function()
            if not windows.insertText(text:getText()) then
                return inline:toast "Please focus on the desired input"
            end
        end)

        paste:setEnabled(windows.isInsertAvailable())

        ui.onFocusChanged = function(isFocused)
            paste:setEnabled(not isFocused and windows.isInsertAvailable())
        end

        tools = ui.row {
            ui.smallButton("Close", function()
                ui:close()
            end),
            paste
        }

        tools:setVisibility(tools.GONE)
        return { text, tools }
    end)

    timer:schedule(timerTask, preferences:getInt("window_timeout", DEFAULT_WINDOW_TIMEOUT))

    return function(newResult)
        if #newResult == 0 then
            return
        end

        local buffer = {}

        for i, pair in pairs(newResult) do
            local currencyCode = string.upper(pair.currency)
            table.insert(buffer, currencyEmoji[currencyCode])
            table.insert(buffer, " ")
            table.insert(buffer, pair.value)
            table.insert(buffer, " ")
            table.insert(buffer, currencyCode)

            if data[pair.currency] then
                for _, base in pairs(baseCurrencies) do
                    if pair.currency ~= base then
                        table.insert(buffer, " = ")
                        local calculated = (data[pair.currency][base] or 0) * pair.value
                        local currencyCodeBase = string.upper(base)
                        table.insert(buffer, currencyEmoji[currencyCodeBase])
                        table.insert(buffer, " ")
                        table.insert(buffer, string.format("%.2f", calculated))
                        table.insert(buffer, " ")
                        table.insert(buffer, currencyCodeBase)
                    end
                end
            else
                table.insert(buffer, " Loading...")
            end

            if i ~= #newResult then
                table.insert(buffer, "\n")
            end
        end

        text:setText(table.concat(buffer, ""))
    end
end

local function createAttemptTask()
    timer:schedule(inline:timerTask(function()
        isLoading = false
    end), 5000)
end

local function updateBar(input)
    if bar == nil and #result > 0 then
        bar = showBar(input)
    end

    if bar then
        bar(result)
    end
end

local function loadData(input, currency)
    isLoading = true
    local url = CURRENCY_API_BASE_URL .. currency .. ".min.json"
    http.get({ url = url },
            function(_, _, string)
                local success, decoded = pcall(json.load, string)
                if success then
                    data[currency] = decoded[currency]
                    updateBar(input)
                    isLoading = false
                else
                    inline:toast("Failed to decode currency data for " .. currency .. ": " .. decoded)
                    createAttemptTask()
                end
            end,
            function()
                inline:toast("Failed to load currency data for " .. currency)
                createAttemptTask()
            end
    )
end

local function watcher(input)
    local text = inline:getText(input)

    if #text > 500 then
        return
    end

    local matcher = pattern:matcher(text)
    result = {}

    if os.time() - timestamp > 900 then
        data = {}
        timestamp = os.time()
    end

    while matcher:find() do
        local numberString = string.gsub(matcher:group(1), ",", ".")
        local factor = string.gsub(matcher:group(2), "к", "k")
        local number = tonumber(numberString)

        if factor == "k" then
            number = number * 1000
        elseif factor == "kk" then
            number = number * 1000000
        elseif factor == "kkk" then
            number = number * 1000000000
        end

        local currencyCode = string.lower(matcher:group(3))
        local currency = currencyAliases[currencyCode] or currencyCode

        table.insert(result, { value = number, currency = currency })

        if #result > 10 then
            table.remove(result, 1)
        end

        if not data[currency] and not isLoading then
            loadData(input, currency)
        end
    end

    updateBar(input)
end

return function(module)
    module:setCategory "Exchange rates"

    module:registerPreferences(function(prefs)
        return {
            prefs.switch("exchange_rates", "Enabled")
                 :setDefault(true)
                 :setListener(function(isChecked)
                if isChecked then
                    module:registerWatcher(watcher)
                else
                    module:unregisterWatcher(watcher)
                end
            end),
            prefs.spacer(12),
            prefs.card {
                prefs.text "Currencies":bold():size(16),
                prefs.spacer(4),
                prefs.text "Comma-separated list of base currencies to convert to.":size(12),
                prefs.spacer(6),
                prefs.textInput("currencies", "Currencies")
                     :setDefault(DEFAULT_CURRENCIES)
                     :setListener(function(s)
                    baseCurrencies = utils.split(s, ",")
                end),
            },
            prefs.spacer(12),
            prefs.card {
                prefs.text "Window":bold():size(16),
                prefs.spacer(8),
                prefs.textInput("window_timeout", "Timeout (ms)")
                     :setDefault(DEFAULT_WINDOW_TIMEOUT)
                     :useInt()
                     :setInputType { "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" },
                prefs.spacer(8),
                prefs.textInput("window_offset", "Offset (dp)")
                     :setDefault(DEFAULT_WINDOW_OFFSET)
                     :useInt()
                     :setInputType { "TYPE_CLASS_NUMBER", "TYPE_NUMBER_FLAG_SIGNED" },
            },
        }
    end)

    if preferences:getBoolean("exchange_rates", true) then
        module:registerWatcher(watcher)
    end

    windows.supportInsert()
end
