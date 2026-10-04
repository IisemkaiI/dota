--[[
	modes/draft_clash.lua
	Режим 2: команда голосует за одного общего героя.

	Текущий этап -- серверный MVP, без Panorama и без custom events.
	Обе команды проходят драфт независимо, каждая голосует
	за своего героя, победитель команды уходит в HeroManager.

	Модуль отвечает ТОЛЬКО за определение героев команд,
	как и RandomClash. Назначение игрокам делает HeroManager
	на GAME_IN_PROGRESS -- этот код не менялся.

	Незавершено этого этапа:
		- Panorama Draft UI и отправка предложений (Phase 5);
		- ввод голоса от настоящего игрока через hero_clash_pick;
		  пока вместо него работают временные голоса в DraftManager;
		- правило 4 + 1: набор героев атрибута в HeroPool пуст,
		  поэтому предложений получается меньше пяти.
]]

if DraftClash == nil then
	DraftClash = {}
end

--[[
	Готов ли режим к запуску.
	Функцию пока никто не вызывает: выбор режима идёт
	через CHeroClashGameMode:SelectMode().
]]
function DraftClash:IsReady()
	return false
end

--[[
	Запуск режима.

	Возвращает true, только если обе команды получили героя.
	Ошибка одной команды не отменяет вторую: команды
	независимы.
]]
function DraftClash:Start()
	GameState:SetMode( HCT_MODE.DRAFT )
	GameState:SetState( GAME_STATE.DRAFT_SETUP )

	HCTDebug:Header( "DRAFT CLASH" )

	-- Атрибуты команд уже определены и лежат в GameState --
	-- на них опирается генерация предложения 4 + 1.
	for _, team in ipairs( DraftManager:GetTeams() ) do
		GameState:SetTeamAttribute( team, HCT_TEAM_DEFAULT_ATTRIBUTE[ team ] )
	end

	local ok = true

	for _, team in ipairs( DraftManager:GetTeams() ) do
		if not DraftManager:StartForTeam( team ) then
			ok = false
		end
	end

	--[[
		ВРЕМЕННО: голоса ботов вместо Panorama и AI.
		Каждый голос идёт через DraftManager:ReceiveVote()
		с теми же шестью проверками, что и настоящий.
		Убрать вместе с появлением Panorama.
	]]
	if ok then
		for _, team in ipairs( DraftManager:GetTeams() ) do
			DraftManager:CastTestVotes( team )

			if DraftManager:IsTeamVoteComplete( team ) then
				if not DraftManager:FinishTeamDraft( team ) then
					ok = false
				end
			else
				HCTDebug:ErrorParts(
					"DraftClash: команда", TeamManager:GetTeamName( team ),
					"не проголосовала, герой не определён"
				)
				ok = false
			end
		end
	end

	GameState:SetState( GAME_STATE.HERO_ASSIGNMENT )
	GameState:SetState( GAME_STATE.PRE_GAME )

	GameState:LogSummary()
	HeroManager:LogTeamHeroes()

	return ok
end