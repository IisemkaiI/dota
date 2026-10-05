--[[
        core/net_tables.lua

        Публикация состояния драфта на клиент через CustomNetTables.

        Единственная таблица: "hct_draft".
        Ключи: "radiant", "dire" (TeamManager:GetTeamName в нижнем регистре).

        Схема записи (только сериализуемые скаляры и массив строк --
        числа и строки, никаких вложенных map с численными ключами):

                options    = { hero1..hero5 }   -- предложения команды
                open       = 0 | 1              -- драфт принимает голоса
                finished   = 0 | 1              -- драфт закрыт
                pick       = "npc_dota_hero_x"  -- победитель или ""
                votesN     = 0..4               -- голоса за N-й option
                voterCount = 0..5               -- сколько проголосовало
                teamSize   = 5                  -- размер команды

        Это слой ТОЛЬКО чтения GameState.draft: ничего не пишет в
        GameState/DraftManager, не меняет их API. Вызывается из
        DraftManager в тех же точках, где уже идёт логирование.

        Boolean -> 0/1: CustomNetTables надёжнее переносит числа и
        строки, чем nil/false-поля, поэтому состояние кодируется числами.

        ПУБЛИЧНЫЙ API:
                NetTables:Init()                 -- один раз при Activate
                NetTables:PublishTeam( team )    -- обновить запись команды
                NetTables:PublishAll()           -- обе команды
]]

if NetTables == nil then
        NetTables = {}
end

-- Имя net-таблицы. Клиент читает CustomNetTables.GetTableValue("hct_draft", key)
HCT_NETTABLE_DRAFT = "hct_draft"

-- Есть ли вообще CustomNetTables в этом рантайме (в VScript может отсутствовать).
local function HasCustomNetTables()
        return type( CustomNetTables ) ~= "nil"
             and type( CustomNetTables.SetTableValue ) == "function"
end

-- Ключ записи по команде: "radiant" / "dire".
function NetTables:GetTeamKey( team )
        local name = TeamManager:GetTeamName( team )
        if name == nil then
                return nil
        end
        return string.lower( tostring( name ) )
end

--[[
        Один раз при старте аддона. Сейчас только проверка доступности API;
        держим функцию, чтобы точка подключения была одна.
]]
function NetTables:Init()
        if not HasCustomNetTables() then
                HCTDebug:WarnParts( "NetTables: CustomNetTables недоступен в этом рантайме, публикация пропущена" )
                return false
        end

        HCTDebug:Log( "NetTables: CustomNetTables доступен" )
        return true
end

--[[
        Собрать запись для команды из GameState.draft.
        Только чтение. Возвращает таблицу или nil, если команда неизвестна.
]]
function NetTables:BuildRecord( team )
        local draft = GameState.draft[ team ]
        if draft == nil then
                return nil
        end

        local options = draft.options or {}
        local votes   = draft.votes or {}

        local record = {
                options    = {},
                open       = draft.open == true and 1 or 0,
                finished   = draft.finished == true and 1 or 0,
                pick       = draft.pick or "",
                voterCount = GameState:CountDraftVoters( team ),
                teamSize   = #TeamManager:GetTeamPlayers( team ),
        }

        for index, heroName in ipairs( options ) do
                record.options[ index ] = heroName
                record[ "votes" .. index ] = votes[ heroName ] or 0
        end

        return record
end

--[[
        Опубликовать текущее состояние драфта команды.
        Идемпотентно: можно вызывать после любой mutation.
]]
function NetTables:PublishTeam( team )
        if not HasCustomNetTables() then
                return false
        end

        local key = self:GetTeamKey( team )
        if key == nil then
                HCTDebug:ErrorParts( "NetTables: нет ключа для команды", tostring( team ) )
                return false
        end

        local record = self:BuildRecord( team )
        if record == nil then
                HCTDebug:ErrorParts( "NetTables: нет данных драфта для команды", key )
                return false
        end

        local ok, err = pcall( function()
                CustomNetTables:SetTableValue( HCT_NETTABLE_DRAFT, key, record )
        end )

        if not ok then
                HCTDebug:ErrorParts( "NetTables: SetTableValue упал |", key, "|", tostring( err ) )
                return false
        end

        HCTDebug:LogParts(
                "NetTables: опубликовано |", key,
                "| options =", #record.options,
                "| open =", record.open,
                "| finished =", record.finished,
                "| votes =", record.voterCount, "/", record.teamSize
        )
        return true
end

-- Обе команды сразу.
function NetTables:PublishAll()
        local ok = true
        for _, team in ipairs( DraftManager:GetTeams() ) do
                if not self:PublishTeam( team ) then
                        ok = false
                end
        end
        return ok
end
