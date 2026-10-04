--[[
	core/team_manager.lua
	Всё, что связано с составом команд: кто в какой команде, сколько их,
	кто капитан. Не содержит игровой логики матча.

	Исправление после второго реального запуска Phase 1:
		PlayerResource:GetAllPlayerIDs()  -- ТАКОГО МЕТОДА НЕТ
		Была ошибка: hero_pool.lua:1486: attempt to call method
		'GetAllPlayerIDs' (a nil value), и из-за этого же падал
		основной путь TeamManager:GetTeamPlayers -- команды выдавали
		players = 0 при реально подключённом игроке.
		GetPlayerTeam на PlayerResource тоже отсутствует.

	Что реально есть (подтверждено дампом CDesc.CDOTA_PlayerResource
	из живого лога и кодом штатных аддонов):
		PlayerResource:GetPlayer( id )     -- CDOTAPlayerController или nil
		PlayerResource:GetTeam( id )       -- номер команды
		PlayerResource:IsValidPlayerID( id )

	Рабочий путь: перебрать playerID от 0 до DOTA_MAX_TEAM_PLAYERS-1
	и оставить те, у которых есть контроллер. Это в точности приём
	из Conquest, events.lua:26-31.
]]

HCT_TEAM_EXPECTED_PLAYERS = 5

if TeamManager == nil then
	TeamManager = {
		apiLogged = false,
	}
end

--[[
	Одноразовый отчёт: какие методы PlayerResource реально доступны.
	Нужен, чтобы следующая итерация опиралась на факты, а не на догадки.
]]
function TeamManager:LogApiAvailability()
	if self.apiLogged then
		return
	end
	self.apiLogged = true

	HCTDebug:Log( "PlayerResource = " .. type( PlayerResource ) )

	local probes = {
		-- На этом пути мы строимся. Должны быть functions.
		{ "GetPlayer", function() return type( PlayerResource.GetPlayer ) end },
		{ "GetTeam", function() return type( PlayerResource.GetTeam ) end },
		{ "IsValidPlayerID", function() return type( PlayerResource.IsValidPlayerID ) end },
		-- Этих в движке нет. Оставлены как зафиксированный факт:
		-- именно они дали nil в прошлом прогоне.
		{ "GetAllPlayerIDs", function() return type( PlayerResource.GetAllPlayerIDs ) end },
		{ "GetPlayerTeam", function() return type( PlayerResource.GetPlayerTeam ) end },
		{ "GetTeamPlayers", function() return type( PlayerResource.GetTeamPlayers ) end },
		{ "GetNumPlayersOnTeam", function() return type( PlayerResource.GetNumPlayersOnTeam ) end },
		{ "GetPlayerSteamID", function() return type( PlayerResource.GetPlayerSteamID ) end },
	}

	for _, probe in ipairs( probes ) do
		local ok, result = pcall( probe[ 2 ] )
		if not ok then
			HCTDebug:Warn( "PR." .. probe[ 1 ] .. " -> проверка упала: " .. tostring( result ) )
		else
			HCTDebug:Log( "PR." .. probe[ 1 ] .. " = " .. tostring( result ) )
		end
	end

	--[[
		Функциональная проверка ОСНОВНОГО пути: перебор playerID должен
		находить реально подключённых игроков и их команды.
		Раньше здесь проверялся GetTeamPlayers, которого в движке нет,
		поэтому блок никогда не выполнялся и печатал вводящий в заблуждение
		текст. Теперь проверяется то, чем мы реально пользуемся.
	]]
	for _, team in ipairs( { DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS } ) do
		local ids = self:GetTeamPlayers( team )

		HCTDebug:LogParts(
			"DIAG перебор playerID, команда", team, "->",
			self:SummarizeIds( ids )
		)
	end
end

-- "1, 2, 3" или "пусто"
function TeamManager:SummarizeIds( ids )
	if ids == nil or #ids == 0 then
		return "пусто"
	end
	return table.concat( ids, "," )
end

-- Массив playerID команды. Всегда массив, никогда nil.
function TeamManager:GetTeamPlayers( team )
	local result = {}

	if type( PlayerResource ) == "nil" then
		return result
	end

	if type( PlayerResource.GetPlayer ) ~= "function" then
		self:LogApiAvailability()
		return result
	end

	--[[
		Штатный обход playerID от 0 до DOTA_MAX_TEAM_PLAYERS-1 с проверкой
		наличия контроллера. Именно так перебирает Conquest
		(conquest/scripts/vscripts/events.lua:26-31).
		Номера в слотах идут подряд, реальный игрок выделяется тем,
		что GetPlayer для его слота возвращает контроллер, а не nil.
	]]
	for playerID = 0, ( DOTA_MAX_TEAM_PLAYERS - 1 ) do
		local hPlayer = PlayerResource:GetPlayer( playerID )

		if hPlayer and self:GetPlayerTeam( playerID ) == team then
			result[ #result + 1 ] = playerID
		end
	end

	table.sort( result )
	return result
end

function TeamManager:GetPlayerTeam( playerID )
	if type( PlayerResource ) == "nil" or type( PlayerResource.GetTeam ) ~= "function" then
		return DOTA_TEAM_NOTEAM
	end

	local ok, team = pcall( PlayerResource.GetTeam, PlayerResource, playerID )
	if not ok or type( team ) ~= "number" then
		return DOTA_TEAM_NOTEAM
	end

	return team
end

-- Считаем сами из списка, чтобы не зависеть от лишнего API.
function TeamManager:GetPlayerCount( team )
	return #self:GetTeamPlayers( team )
end

--[[
	Готова ли команда к старту.
	expected по умолчанию HCT_TEAM_EXPECTED_PLAYERS.
]]
function TeamManager:IsTeamReady( team, expected )
	expected = expected or HCT_TEAM_EXPECTED_PLAYERS
	return self:GetPlayerCount( team ) >= expected
end

--[[
	Капитан команды -- первый playerID в списке.
	Выбор капитана нужен для Draft Clash: капитан выбирает
	общего героя один за всю команду.
]]
function TeamManager:GetCaptain( team )
	local players = self:GetTeamPlayers( team )
	if #players == 0 then
		return nil
	end
	return players[ 1 ]
end

function TeamManager:IsCaptain( playerID )
	local team = self:GetPlayerTeam( playerID )
	if team == DOTA_TEAM_NOTEAM then
		return false
	end
	return self:GetCaptain( team ) == playerID
end

-- Человекочитаемое имя команды для логов
function TeamManager:GetTeamName( team )
	if team == DOTA_TEAM_GOODGUYS then
		return "Radiant"
	elseif team == DOTA_TEAM_BADGUYS then
		return "Dire"
	end
	return "NotTeam"
end

--[[
	Раскладка команд в консоль: кто в какой команде, готовность, капитаны.
	Тело закрыто pcall -- LogTeams не имеет права ронять лог (ТЗ Phase 1).
]]
function TeamManager:LogTeams()
	HCTDebug:Header( "TEAMS" )
	self:LogApiAvailability()

	local ok, err = pcall( function()
		local allTeams = { DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }

		for _, team in ipairs( allTeams ) do
			local players = self:GetTeamPlayers( team )
			local captain = self:GetCaptain( team )

			HCTDebug:LogParts(
				self:GetTeamName( team ),
				"| players =", #players,
				"| ready =", tostring( self:IsTeamReady( team ) ),
				"| captain =", tostring( captain )
			)

			for _, playerID in ipairs( players ) do
				HCTDebug:LogParts(
					"    player", playerID,
					self:GetPlayerTeam( playerID ) == team and "(captain)" or ""
				)
			end
		end
	end )

	if not ok then
		HCTDebug:Error( "LogTeams прерван: " .. tostring( err ) )
	end
end
