--[[
	draft/draft_manager.lua
	Драфт команды: предложения, приём голосов, подсчёт, выбор победителя.

	Правила голосования:
		- Radiant и Dire голосуют НЕЗАВИСИМО, у каждой команды свой набор;
		- у каждого игрока команды ровно один голос;
		- голос засчитывается только внутри своей команды;
		- побеждает герой с максимальным числом голосов;
		- при равенстве побеждает ПЕРВЫЙ герой в исходном порядке
		  GameState:GetDraftOptions(team). Правило детерминированное,
		  дополнительная случайность не используется.

	Данные лежат в GameState.draft[team]. Пишутся туда только
	сеттерами GameState -- тот же контракт, что у HeroManager
	в отношении GameState.teamHeroes.

	Путь файла и набор функций заданы ТЗ §13. Имя ReceiveVote отличается
	от ReceivePick из ТЗ: здесь голосование с подсчётом, а не
	"кто первый нажал".

	Источник предложений -- HeroPool, единственный источник истины
	по списку героев. HeroList не используется.
]]

if DraftManager == nil then
	DraftManager = {}
end

-- Обе команды. Драфт каждой идёт полностью независимо.
local HCT_DRAFT_TEAMS = { DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }

-- Сколько предложений ожидается по ТЗ §24 (4 + 1).
local HCT_DRAFT_EXPECTED = HCT_DRAFT_MAIN_COUNT + HCT_DRAFT_EXTRA_COUNT

-- Список команд драфта. Единственный источник для обходов.
function DraftManager:GetTeams()
	return HCT_DRAFT_TEAMS
end

--[[
	Открыть драфт команды: сгенерировать предложения и принять голоса.

	Возвращает true, если предложения есть и драфт открыт.
]]
function DraftManager:StartForTeam( team )
	local teamName = TeamManager:GetTeamName( team )

	HCTDebug:Header( "DRAFT КОМАНДЫ: " .. tostring( teamName ) )

	local options = self:GenerateOptions( team )
	if options == nil or #options == 0 then
		HCTDebug:ErrorParts( "StartForTeam: у команды", teamName, "нет предложений" )
		return false
	end

	GameState:SetDraftOptions( team, options )
	GameState:SetDraftOpen( team, true )

	HCTDebug:LogParts( "предложений =", #options, "| атрибут =", tostring( GameState:GetTeamAttribute( team ) ) )

	for index, heroName in ipairs( options ) do
		HCTDebug:LogParts( "  вариант", index, "=", heroName )
	end

	-- Публикация предложений на клиент (CustomNetTables). Слой только
	-- чтения: NetTables сам берёт данные из GameState.draft.
	if NetTables ~= nil then
		NetTables:PublishTeam( team )
	end

	self:SendOptionsToTeam( team )
	return true
end

--[[
	Сгенерировать предложения команды по правилу 4 + 1 (ТЗ §24, §25).

	Четыре героя атрибута команды плюс один случайный из общего пула.
	Сам алгоритм живёт в HeroPool:GetDraftOptions() -- здесь только
	проверка результата.
]]
function DraftManager:GenerateOptions( team )
	local attribute = GameState:GetTeamAttribute( team )

	if attribute == nil then
		HCTDebug:ErrorParts( "GenerateOptions: у команды", TeamManager:GetTeamName( team ), "не задан атрибут" )
		return nil
	end

	local options = HeroPool:GetDraftOptions( attribute, HCT_DRAFT_MAIN_COUNT, HCT_DRAFT_EXTRA_COUNT )

	--[[
		Предупреждение, а не ошибка: генерация отработала корректно,
		просто в пуле может не оказаться героев нужного атрибута,
		и предложений получится меньше ожидаемых 5.
		Факт расхождения печатается, а не скрывается.
	]]
	if #options < HCT_DRAFT_EXPECTED then
		HCTDebug:WarnParts(
			"GenerateOptions: получено", #options, "из", HCT_DRAFT_EXPECTED,
			"| атрибут =", tostring( attribute ),
			"| в пуле нет героев этого атрибута"
		)
	end

	return options
end

--[[
	Отправить предложения команде.

	Panorama появится на Phase 5 (ТЗ §17). Клиентской части пока нет,
	отправлять некуда -- печатаем в лог.
]]
function DraftManager:SendOptionsToTeam( team )
	HCTDebug:LogParts( "SendOptionsToTeam:", TeamManager:GetTeamName( team ), "-- Panorama ещё нет, только лог" )
end

--[[
	Шесть проверок голоса из ТЗ §14, в том же порядке.

	Возвращает true, либо false и причину отказа.
	Порядок не менять: он совпадает с ТЗ.
]]
function DraftManager:ValidateVote( team, playerID, heroName )
	-- 1. Игрок существует и участвует в матче.
	if type( PlayerResource ) == "nil" or type( PlayerResource.GetPlayer ) ~= "function" then
		return false, "PlayerResource недоступен"
	end

	if not PlayerResource:GetPlayer( playerID ) then
		return false, "игрока нет в слоте"
	end

	-- 2. Игрок относится к этой команде.
	if TeamManager:GetPlayerTeam( playerID ) ~= team then
		return false, "игрок играет за другую команду"
	end

	-- 3. Драфт команды открыт.
	if not GameState:IsDraftOpen( team ) then
		return false, "драфт команды не открыт"
	end

	-- 4. Герой входит в предложения этой команды.
	local offered = false

	for _, option in ipairs( GameState:GetDraftOptions( team ) ) do
		if option == heroName then
			offered = true
			break
		end
	end

	if not offered then
		return false, "герой не входит в предложения команды"
	end

	-- 5. У команды ещё нет определённого героя.
	if GameState:GetDraftPick( team ) ~= nil then
		return false, "герой команды уже определён"
	end

	-- 6. Этот playerID ещё не голосовал.
	if GameState:GetDraftVote( team, playerID ) ~= nil then
		return false, "игрок уже голосовал"
	end

	return true, nil
end

--[[
	Принять голос игрока.

	Команда определяется по playerID -- игрок голосует только
	за свою команду и не может голосовать за чужую.

	Возвращает true, если голос принят.
]]
function DraftManager:ReceiveVote( playerID, heroName )
	local team = TeamManager:GetPlayerTeam( playerID )

	local valid, reason = self:ValidateVote( team, playerID, heroName )
	if not valid then
		HCTDebug:ErrorParts( "ReceiveVote: отказ -- игрок", playerID, "| причина:", tostring( reason ) )
		return false
	end

	GameState:SetDraftVote( team, playerID, heroName )

	HCTDebug:LogParts(
		"ReceiveVote: команда =", TeamManager:GetTeamName( team ),
		"| игрок =", playerID,
		"| герой =", heroName,
		"| проголосовало =", GameState:CountDraftVoters( team ),
		"из", #TeamManager:GetTeamPlayers( team )
	)

	-- Обновить счётчики голосов на клиенте.
	if NetTables ~= nil then
		NetTables:PublishTeam( team )
	end

	return true
end

--[[
	Проголосовали ли все игроки команды.

	Без этого условия драфт не закрывается: FinishTeamDraft
	нельзя вызывать, пока есть игроки без голоса.
]]
function DraftManager:IsTeamVoteComplete( team )
	local players = TeamManager:GetTeamPlayers( team )

	if #players == 0 then
		HCTDebug:ErrorParts( "IsTeamVoteComplete: в команде", TeamManager:GetTeamName( team ), "никого нет" )
		return false
	end

	return GameState:CountDraftVoters( team ) == #players
end

--[[
	Подсчитать голоса и определить героя команды.

	Победитель -- герой с максимальным числом голосов.
	При равенстве побеждает ПЕРВЫЙ в исходном порядке options:
	обход идёт по options, а счётчик обновляется только при строгом
	большем значении, поэтому первым при равенстве остаётся
	ранний вариант. Порядок обхода и есть правило разрешения ничьей.
	Дополнительная случайность не используется.
]]
function DraftManager:FinishTeamDraft( team )
	local teamName = TeamManager:GetTeamName( team )
	local options = GameState:GetDraftOptions( team )
	local votes = GameState:GetDraftVotes( team )

	local winner = nil
	local bestCount = 0

	for _, heroName in ipairs( options ) do
		local count = votes[ heroName ] or 0

		if count > bestCount then
			winner = heroName
			bestCount = count
		end
	end

	HCTDebug:Header( "ИТОГ ДРАФТА: " .. tostring( teamName ) )
	HCTDebug:LogParts( "принято голосов =", GameState:CountDraftVoters( team ), "| предложений =", #options )

	for _, heroName in ipairs( options ) do
		HCTDebug:LogParts( "  голосов |", heroName, "=", tostring( votes[ heroName ] or 0 ) )
	end

	if winner == nil then
		HCTDebug:ErrorParts( "FinishTeamDraft: у команды", teamName, "нет ни одного голоса" )
		GameState:SetDraftOpen( team, false )
		return false
	end

	HCTDebug:LogParts( "победитель =", winner, "| голосов =", bestCount )

	GameState:SetDraftPick( team, winner )
	GameState:SetDraftOpen( team, false )

	-- Финальное состояние драфта на клиент: pick + finished.
	if NetTables ~= nil then
		NetTables:PublishTeam( team )
	end

	if not HeroManager:SetTeamHero( team, winner ) then
		HCTDebug:ErrorParts( "FinishTeamDraft: HeroManager отклонил героя команды", teamName )
		return false
	end

	return true
end

--[[
	ВРЕМЕННО: голоса ботов вместо Panorama и AI.

	Настоящий голос придёт по событию hero_clash_pick (ТЗ §17, Phase 5).
	Пока каждый игрок команды голосует автоматически -- так проверяется
	весь серверный цикл целиком.

	Голос идёт через тот же DraftManager:ReceiveVote() с теми же
	шестью проверками. Отдельного счётчика голосов здесь нет.
	Каждый playerID голосует ровно один раз: повтор отсекает
	проверка 6 внутри ReceiveVote.

	Удалить вместе с Panorama, когда появится настоящий ввод.
]]
function DraftManager:CastTestVotes( team )
	local options = GameState:GetDraftOptions( team )
	local players = TeamManager:GetTeamPlayers( team )

	HCTDebug:Header( "ВРЕМЕННЫЕ ГОЛОСА: " .. tostring( TeamManager:GetTeamName( team ) ) )

	for _, playerID in ipairs( players ) do
		self:ReceiveVote( playerID, HCTRandom:PickFromArray( options ) )
	end

	HCTDebug:LogParts(
		"принято голосов =", GameState:CountDraftVoters( team ),
		"| игроков в команде =", #players
	)
end

-- Драфт команды закрыт.
function DraftManager:IsDraftFinished( team )
	return GameState:IsDraftFinished( team )
end