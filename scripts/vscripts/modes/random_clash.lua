--[[
	modes/random_clash.lua
	Режим 1: случайный общий герой на команду.

	Правила (ТЗ §2):
		1. случайный герой для Radiant;
		2. случайный герой для Dire;
		3. выборы независимы;
		4. повтор героя между командами разрешён (зеркальный матч);
		5. после выбора герой назначается всем игрокам команды.

	Модуль отвечает ТОЛЬКО за определение героев команд.
	Назначение игрокам делает HeroManager (Phase 3).
]]

if RandomClash == nil then
	RandomClash = {}
end

--[[
	Сгенерировать по одному герою на команду.
	Возвращает таблицу:
		{ [DOTA_TEAM_GOODGUYS] = "npc_dota_hero_x", [DOTA_TEAM_BADGUYS] = "npc_dota_hero_y" }
]]
function RandomClash:GenerateHeroes()
	local radiantHero = HeroPool:GetRandomHero()
	local direHero = HeroPool:GetRandomHero()

	return {
		[ DOTA_TEAM_GOODGUYS ] = radiantHero,
		[ DOTA_TEAM_BADGUYS ] = direHero,
	}
end

--[[
	Полный запуск режима.
	Возвращает true, если матч подготовлен к старту.
]]
function RandomClash:Start()
	GameState:SetMode( HCT_MODE.RANDOM )
	GameState:SetState( GAME_STATE.RANDOM_SETUP )

	HCTDebug:Header( "RANDOM CLASH" )

	local heroes = self:GenerateHeroes()
	local radiantHero = heroes[ DOTA_TEAM_GOODGUYS ]
	local direHero = heroes[ DOTA_TEAM_BADGUYS ]

	if radiantHero == nil or direHero == nil then
		HCTDebug:Error( "Не удалось сгенерировать героев: пул пуст. Матч не стартует." )
		return false
	end

	if not HeroManager:SetTeamHero( DOTA_TEAM_GOODGUYS, radiantHero ) then
		return false
	end

	if not HeroManager:SetTeamHero( DOTA_TEAM_BADGUYS, direHero ) then
		return false
	end

	if HeroManager:IsMirrorMatch() then
		HCTDebug:Log( "Зеркальный матч: обе команды играют на " .. tostring( radiantHero ) )
	end

	--[[
		Phase 3: здесь вызывается HeroManager:SpawnTeamHeroes() для обеих команд.
		Пока только состояние.
	]]
	GameState:SetState( GAME_STATE.HERO_ASSIGNMENT )
	GameState:SetState( GAME_STATE.PRE_GAME )

	HeroManager:LogTeamHeroes()
	return true
end