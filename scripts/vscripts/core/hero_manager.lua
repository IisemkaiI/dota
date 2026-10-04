--[[
	core/hero_manager.lua
	Центральная система назначения героев.

	Смысл: у команды ОДИН общий герой, и все её игроки играют на нём.
	Radiant: Pudge x5
	Dire:    Morphling x5

	Данные хранятся в GameState.teamHeroes.
	Писать в GameState.teamHeroes напрямую нельзя -- только через этот модуль.

	Важно: замена героев игроков реализована через
	PlayerResource:ReplaceHeroWith() и вызывается из GameMode на
	GAME_IN_PROGRESS. Раньше это состояние ещё недоступно: у игрока
	нет герой-сущности, и движок отказывает.
]]

if HeroManager == nil then
	HeroManager = {}
end

-----------------------------------------------------------------------------
-- Выбор героя команды
-----------------------------------------------------------------------------

--[[
	Назначить команде общего героя.
	Возвращает true, если герой назначен, иначе false.
]]
function HeroManager:SetTeamHero( team, heroName )
	if heroName == nil then
		HCTDebug:Error( "SetTeamHero: heroName = nil" )
		return false
	end

	if not self:IsHeroAllowed( heroName ) then
		HCTDebug:Error( "SetTeamHero: герой не разрешён -- " .. tostring( heroName ) )
		return false
	end

	GameState:SetTeamHero( team, heroName )
	HCTDebug:LogParts( "HeroManager:", TeamManager:GetTeamName( team ), "->", heroName )
	return true
end

function HeroManager:GetTeamHero( team )
	return GameState:GetTeamHero( team )
end

function HeroManager:ClearTeamHero( team )
	GameState:SetTeamHero( team, nil )
end

function HeroManager:HasTeamHero( team )
	return GameState:GetTeamHero( team ) ~= nil
end

--[[
	Разрешён ли герой.
	Список героев берётся из HeroPool -- единственного источника истины.
]]
function HeroManager:IsHeroAllowed( heroName )
	if heroName == nil then
		return false
	end
	return HeroPool:Contains( heroName )
end

-- Растолковать, отличаются ли герои команд (зеркальный матч разрешён)
function HeroManager:IsMirrorMatch()
	local radiant = self:GetTeamHero( DOTA_TEAM_GOODGUYS )
	local dire = self:GetTeamHero( DOTA_TEAM_BADGUYS )
	return radiant ~= nil and radiant == dire
end

-----------------------------------------------------------------------------
-- Phase 3: реальное назначение героев игрокам
-----------------------------------------------------------------------------

--[[
	Выдать героя игроку.

	Герой берётся у команды, а не извне: параметр heroName --
	это проверка, что вызывающий не пытается выдать чужого.
	Источник истины -- GameState.teamHeroes, доступ через
	HeroManager:GetTeamHero().

	Механика замены проверена прогонами:
		- вызов возможен только когда у игрока уже есть
		  герой-сущность, то есть не раньше GAME_IN_PROGRESS.
		  На STRATEGY_TIME движок пишет "ReplaceHeroWith failed as
		  player has no current hero to replace.";
		- признак успеха -- возвращённая сущность нового героя.
		  Отказ возвращает nil, поэтому одного pcall мало: он
		  успешен и при отказе;
		- пять игроков одной команды заменяются подряд, слоты
		  другой команды не затрагиваются (5 из 5, отказов 0).

	Сигнатура из last_hit_trainer
	(scripts/vscripts/events.lua:446):
		PlayerResource:ReplaceHeroWith( nPlayerID, sHeroClass, 0, 0 )

	pcall обязателен: падение метода не должно оборвать
	обработчик состояния и потерять лог остальных игроков.
]]
function HeroManager:AssignHeroToPlayer( playerID, heroName )
	local team = TeamManager:GetPlayerTeam( playerID )
	local teamHero = self:GetTeamHero( team )

	if teamHero == nil then
		HCTDebug:ErrorParts( "AssignHeroToPlayer: у команды ", team, " нет героя" )
		return false
	end

	if heroName ~= nil and heroName ~= teamHero then
		HCTDebug:ErrorParts( "AssignHeroToPlayer: попытка выдать чужого героя ", tostring( heroName ) )
		return false
	end

	if type( PlayerResource ) == "nil" or type( PlayerResource.ReplaceHeroWith ) ~= "function" then
		HCTDebug:Error( "AssignHeroToPlayer: ReplaceHeroWith недоступен" )
		return false
	end

	local ok, result = pcall( function()
		return PlayerResource:ReplaceHeroWith( playerID, teamHero, 0, 0 )
	end )

	-- Проверка результата. GetSelectedHeroName не зависит от
	-- наличия герой-объекта, в отличие от GetAssignedHero.
	local applied = "нет метода"

	if type( PlayerResource.GetSelectedHeroName ) == "function" then
		applied = tostring( PlayerResource:GetSelectedHeroName( playerID ) )
	end

	if not ok or type( result ) ~= "table" then
		HCTDebug:LogParts(
			"HeroManager: игрок", playerID, "-> ОТКАЗ",
			"| pcall ok =", tostring( ok ),
			"| вернулось:", tostring( result ),
			"| в слоте:", applied
		)
		return false
	end

	if applied ~= teamHero then
		HCTDebug:ErrorParts(
			"HeroManager: игрок", playerID, "получил", applied, "вместо", teamHero
		)
		return false
	end

	HCTDebug:LogParts( "HeroManager: игрок", playerID, "->", teamHero, "( команда", team, ")" )
	return true
end

--[[
	Выдать общего героя команды всем игрокам команды.
	Возвращает true, только если герой получили ВСЕ игроки.
]]
function HeroManager:SpawnTeamHeroes( team )
	local heroName = self:GetTeamHero( team )

	if heroName == nil then
		HCTDebug:ErrorParts( "SpawnTeamHeroes: у команды", team, "нет героя" )
		return false
	end

	local players = TeamManager:GetTeamPlayers( team )

	HCTDebug:Header( "ГЕРОЙ КОМАНДЫ" )
	HCTDebug:LogParts( "команда =", TeamManager:GetTeamName( team ), "| герой =", heroName )
	HCTDebug:LogParts( "игроков =", #players, "| playerID =", TeamManager:SummarizeIds( players ) )

	if #players == 0 then
		HCTDebug:Error( "SpawnTeamHeroes: в команде никого нет" )
		return false
	end

	local assigned = 0

	for _, playerID in ipairs( players ) do
		if self:AssignHeroToPlayer( playerID, heroName ) then
			assigned = assigned + 1
		end
	end

	HCTDebug:LogParts(
		"итог:", TeamManager:GetTeamName( team ),
		"| герой =", heroName,
		"| игроков =", #players,
		"| применено =", assigned,
		"| отказов =", #players - assigned
	)

	return assigned == #players
end

-------------------------------------------------------------------------------
-- Отладка
-----------------------------------------------------------------------------

function HeroManager:LogTeamHeroes()
	HCTDebug:LogTable( "teamHeroes (HeroManager)", {
		Radiant = self:GetTeamHero( DOTA_TEAM_GOODGUYS ),
		Dire = self:GetTeamHero( DOTA_TEAM_BADGUYS ),
		mirror = self:IsMirrorMatch(),
	}, 1 )
end