--[[
	core/game_mode.lua
	Главный контроллер. Только координирует системы, не содержит их логики.

	Обязанности (ТЗ §7):
		- инициализировать правила;
		- отслеживать состояние;
		- запускать выбранный режим;
		- запускать HeroManager;
		- отслеживать победу/поражение;
		- регистрировать игровые события.

	Ссылка на себя кладётся на игровую сущность, как это принято в Dota:
		GameRules:GetGameModeEntity().HeroClashTurbo
	Так к ней обращаются остальные модули.
]]

if CHeroClashGameMode == nil then
	_G.CHeroClashGameMode = class( {} )
end

--[[
	Самопроверка Phase 1.
	На этом этапе нет Panorama и способа выбрать режим из интерфейса,
	поэтому режим запускается автоматически и результат печатается
	в консоль -- чтобы очередной этап можно было проверить без UI.

	На Phase 2 (появление меню выбора режима) выставить false.
]]
HCT_DEBUG_SELF_TEST = true
HCT_DEBUG_SELF_TEST_DELAY = 5.0

--[[
	Режим самопроверки: HCT_MODE.DRAFT -- голосование,
	HCT_MODE.RANDOM -- случайный выбор. Меняется одним числом.

	Сам модуль RandomClash остаётся на месте и вызывается
	из SelectMode как раньше.
]]
HCT_SELF_TEST_MODE = HCT_MODE.DRAFT

function CHeroClashGameMode:Init()
	-- Ссылка на себя для всех остальных модулей (паттерн Conquest)
	GameRules:GetGameModeEntity().HeroClashTurbo = self

	GameState:Reset()

	--[[
		Основная механика Mirror TURBO: нескольким игрокам разрешено
		выбрать одного и того же героя. Метод CDOTAGameRules.
		Вызывается до старта, чтобы действовать на всю сетку выбора.
	]]
	GameRules:SetSameHeroSelectionEnabled( true )

	HCTDebug:Header( "HERO CLASH TURBO INITIALIZED" )
	HCTDebug:LogParts( "state     =", GameState:GetStateName() )
	HCTDebug:LogParts( "mode      =", GameState:GetModeName() )
	HCTDebug:Log( "systems   = GameState, GameMode, TeamManager, HeroManager, HeroPool, RandomClash, DraftClash" )
	HCTDebug:Log( "phase     = 1 (каркас): Panorama и Turbo ещё не реализованы" )

	--[[
		ListenToGameEvent -- штатный способ подписки из кода Valve (см. Conquest).
		Третий аргумент self передаётся в обработчик первым.
	]]
	ListenToGameEvent( "game_rules_state_change", Dynamic_Wrap( self, "OnGameRulesStateChange" ), self )

	GameRules:GetGameModeEntity():SetThink( "OnThink", self, "GlobalThink", 1 )

	if HCT_DEBUG_SELF_TEST then
		GameRules:GetGameModeEntity():SetContextThink(
			"HeroClashTurboSelfTest",
			function() self:RunSelfTest() end,
			HCT_DEBUG_SELF_TEST_DELAY
		)
	end
end

-----------------------------------------------------------------------------
-- Игровые события
-----------------------------------------------------------------------------

--[[
	Глобальный think.
	Возвращает 1, чтобы думать каждый кадр; nil -- прекратить.
]]
function CHeroClashGameMode:OnThink()
	local gameState = GameRules:State_Get()

	if gameState == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		--[[
			Phase 6+ здесь включается TurboSystem.
		]]
	elseif gameState >= DOTA_GAMERULES_STATE_POST_GAME then
		GameState:SetState( GAME_STATE.END_GAME )
		HCTDebug:Header( "END_GAME" )
		GameState:LogSummary()
		return nil
	end

	return 1
end

function CHeroClashGameMode:OnGameRulesStateChange( event )
	local newState = GameRules:State_Get()
	local newName = self:GetEngineStateName( newState )

	HCTDebug:LogParts( "game_rules_state_change ->", tostring( newName ) )

	if newState == DOTA_GAMERULES_STATE_HERO_SELECTION then
		--[[
			Здесь по ТЗ должно открываться главное меню выбора режима.
			Panorama появится на Phase 5, пока только печатаем состав.
		]]
		GameState:SetState( GAME_STATE.MENU )
		TeamManager:LogTeams()
	elseif newState == DOTA_GAMERULES_STATE_STRATEGY_TIME then
		self:FillWithBots()
		self:StartSelfTestMode()
	elseif newState == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		GameState:SetState( GAME_STATE.GAME )

		--[[
			Применение героев команд игрокам.

			Именно здесь, а не раньше: замена возможна только когда
			у игрока уже есть герой-сущность. На STRATEGY_TIME движок
			пишет "ReplaceHeroWith failed as player has no current
			hero to replace." и возвращает nil.

			Герои берутся у HeroManager, тот читает
			GameState.teamHeroes -- тот же слот, куда их кладёт
			режим игры. Radiant и Dire обрабатываются отдельно,
			каждый получает своего героя.

			Проверка результата и признак успеха -- внутри
			HeroManager:AssignHeroToPlayer().
		]]
		local radiantApplied = HeroManager:SpawnTeamHeroes( DOTA_TEAM_GOODGUYS )
		local direApplied = HeroManager:SpawnTeamHeroes( DOTA_TEAM_BADGUYS )

		HCTDebug:Header( "ГЕРОИ КОМАНД ПРИМЕНЕНЫ" )
		HCTDebug:LogParts(
			"Radiant:", tostring( radiantApplied ),
			"| Dire:", tostring( direApplied )
		)
	end
end

--[[
	Заполнение матча ботами.

	GameRules:BotPopulate() дополняет лобби до размера, заданного в
	настройках кастомной игры. Штатный способ, ровно так делают
	conquest (scripts/vscripts/events.lua:23),
	ws (scripts/vscripts/events.lua:23),
	manyplayer_example (scripts/vscripts/addon_game_mode.lua:183),
	overthrow (scripts/vscripts/addon_game_mode.lua:642).

	Вызывается на STRATEGY_TIME: все живые игроки к этому моменту
	уже выбрали героя, отсчёт стратегии ещё не пошёл.

	Сколько ботов добавится, решает движок -- состояние лобби из
	скрипта недоступно. Проверяем только факт: пересчитываем
	подключённые контроллеры до и после через уже проверенный
	TeamManager:GetTeamPlayers().

	Разделить людей и ботов из скрипта нечем: GetPlayerSteamID
	в VScript отсутствует, поэтому считаем всех вместе.
]]
function CHeroClashGameMode:FillWithBots()
	HCTDebug:Header( "BOT POPULATE" )

	local before = self:CountConnectedPlayers()
	HCTDebug:LogParts( "до BotPopulate подключено:", before )

	-- pcall обязателен: падение метода не должно обрывать обработчик
	-- состояния, иначе теряется весь лог матча.
	local ok, err = pcall( function() GameRules:BotPopulate() end )

	if not ok then
		HCTDebug:Error( "BotPopulate упал: " .. tostring( err ) )
		return false
	end

	local after = self:CountConnectedPlayers()
	HCTDebug:LogParts( "после BotPopulate подключено:", after )
	HCTDebug:LogParts( "добавлено контроллеров:", after - before )

	--[[
		Повторный пересчёт через секунду. Заполнение может быть
		не мгновенным, и синхронный after уже успевает устареть.
		Второй прогон покажет, нужен ли вообще этот отложенный замер.
	]]
	GameRules:GetGameModeEntity():SetContextThink(
		"HeroClashTurboBotRecheck",
		function()
			local late = self:CountConnectedPlayers()
			HCTDebug:LogParts( "через 1с подключено:", late, "| прирост к моменту вызова:", late - before )
		end,
		1.0
	)

	return true
end

--[[
	Запуск режима самопроверки.

	Режим стартует здесь, а не в RunSelfTest: голосовать должны
	игроки обеих команд, а полный состав появляется только после
	BotPopulate на STRATEGY_TIME. На HERO_SELECTION существует
	один реальный игрок, и драфт не смог бы завершиться.

	Защита от повторного запуска: STRATEGY_TIME приходит один раз,
	но если придёт снова, второй драфт сбросил бы предложения
	и уже принятые голоса.
]]
function CHeroClashGameMode:StartSelfTestMode()
	if GameState:GetMode() ~= HCT_MODE.NONE then
		HCTDebug:LogParts( "StartSelfTestMode: режим уже запущен --", GameState:GetModeName() )
		return false
	end

	return self:SelectMode( HCT_SELF_TEST_MODE )
end

--[[
	Число подключённых контроллеров -- люди и боты вместе.

	Не дублирует обход из TeamManager:GetTeamPlayers(): переиспользует
	его и складывает две команды. Свой playerID-обход здесь не нужен.
]]
function CHeroClashGameMode:CountConnectedPlayers()
	return #TeamManager:GetTeamPlayers( DOTA_TEAM_GOODGUYS )
		 + #TeamManager:GetTeamPlayers( DOTA_TEAM_BADGUYS )
end

--[[
	Человекочитаемое имя состояния движка.
	Список собирается с проверкой на nil: если какой-то из констант
	движка окажется недоступен, таблица не сломается, а просто не
	покажет это состояние.
]]
function CHeroClashGameMode:GetEngineStateName( state )
	local names = {}
	local order = {
		{ DOTA_GAMERULES_STATE_INIT,					"INIT" },
		{ DOTA_GAMERULES_STATE_HERO_SELECTION,			"HERO_SELECTION" },
		{ DOTA_GAMERULES_STATE_HERO_SELECTION_PHASE,	"HERO_SELECTION_PHASE" },
		{ DOTA_GAMERULES_STATE_STRATEGY_TIME,			"STRATEGY_TIME" },
		{ DOTA_GAMERULES_STATE_PRE_GAME,				"PRE_GAME" },
		{ DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,		"GAME_IN_PROGRESS" },
		{ DOTA_GAMERULES_STATE_GAME_OVER,				"GAME_OVER" },
		{ DOTA_GAMERULES_STATE_POST_GAME,				"POST_GAME" },
	}

	for _, pair in ipairs( order ) do
		if pair[ 1 ] ~= nil then
			names[ pair[ 1 ] ] = pair[ 2 ]
		end
	end

	return names[ state ] or "UNKNOWN"
end

-----------------------------------------------------------------------------
-- Выбор режима
-----------------------------------------------------------------------------

--[[
	Единая точка входа для выбора режима.
	Подтверждённые на Phase 1 режимы: HCT_MODE.RANDOM, HCT_MODE.DRAFT.
	Вызывается из Panorama позже (Phase 5).
]]
function CHeroClashGameMode:SelectMode( mode )
	if mode ~= HCT_MODE.RANDOM and mode ~= HCT_MODE.DRAFT then
		HCTDebug:ErrorParts( "SelectMode: неизвестный режим --", tostring( mode ) )
		return false
	end

	HCTDebug:Header( "ВЫБОР РЕЖИМА" )
	GameState:SetState( GAME_STATE.MODE_SELECTION )

	if mode == HCT_MODE.RANDOM then
		return RandomClash:Start()
	end

	return DraftClash:Start()
end

-----------------------------------------------------------------------------
-- Самопроверка Phase 1
-----------------------------------------------------------------------------

--[[
	Одноразовая проверка каркаса.
	Прогоняет пул героев и раскладку команд в консоль.

	Сам режим здесь НЕ запускается: он стартует на STRATEGY_TIME
	через StartSelfTestMode, когда есть полный состав игроков.
	Запуск режима на этом шаге занял бы GameState.mode раньше времени
	и заблокировал бы драфт проверкой в StartSelfTestMode.

	Каждый шаг обёрнут в pcall: падение одной подсистемы не должно
	обрывать лог -- иначе теряется вся диагностика целиком.
]]
function CHeroClashGameMode:RunSelfTest()
	HCTDebug:Header( "PHASE 1 SELF-TEST" )

	local steps = {
		{ "HeroPool", function() HeroPool:LogSummary() end },
		{ "TeamManager", function() TeamManager:LogTeams() end },
	}

	for _, step in ipairs( steps ) do
		local ok, err = pcall( step[ 2 ] )
		if not ok then
			HCTDebug:Error( step[ 1 ] .. " упал: " .. tostring( err ) )
		end
	end

	HCTDebug:LogParts( "SELF-TEST DONE | state =", GameState:GetStateName(), "| mode =", GameState:GetModeName() )
	HCTDebug:Log( "Чтобы отключить самопроверку, поставь HCT_DEBUG_SELF_TEST = false в core/game_mode.lua" )
end