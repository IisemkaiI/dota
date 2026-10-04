--[[
	core/game_state.lua
	Конечный автомат матча и единое хралище данных.

	Здесь живут ТОЛЬКО данные. Вся логика изменения состояния --
	в GameMode, который вызывает сеттеры. Так исключены два источника правды.
]]

-- Состояния матча
GAME_STATE = {
	MENU				= 0,
	MODE_SELECTION		= 1,
	RANDOM_SETUP		= 2,
	DRAFT_SETUP			= 3,
	HERO_ASSIGNMENT		= 4,
	PRE_GAME			= 5,
	GAME				= 6,
	END_GAME			= 7,
}

GAME_STATE_NAME = {
	[ GAME_STATE.MENU ]				= "MENU",
	[ GAME_STATE.MODE_SELECTION ]	= "MODE_SELECTION",
	[ GAME_STATE.RANDOM_SETUP ]		= "RANDOM_SETUP",
	[ GAME_STATE.DRAFT_SETUP ]		= "DRAFT_SETUP",
	[ GAME_STATE.HERO_ASSIGNMENT ]	= "HERO_ASSIGNMENT",
	[ GAME_STATE.PRE_GAME ]			= "PRE_GAME",
	[ GAME_STATE.GAME ]				= "GAME",
	[ GAME_STATE.END_GAME ]			= "END_GAME",
}

-- Режимы игры
HCT_MODE = {
	NONE	= 0,
	RANDOM	= 1,
	DRAFT	= 2,
}

HCT_MODE_NAME = {
	[ HCT_MODE.NONE ]	= "NONE",
	[ HCT_MODE.RANDOM ]	= "RANDOM_CLASH",
	[ HCT_MODE.DRAFT ]	= "DRAFT_CLASH",
}

--[[
	GameState -- только данные + сеттеры с логированием.
	Писать напрямую в поля GameState нельзя, только через методы.
]]
if GameState == nil then
	GameState = {
		state = GAME_STATE.MENU,
		mode = HCT_MODE.NONE,

		--[[
			teamHeroes[team] = "npc_dota_hero_pudge"
			Пишет сюда ТОЛЬКО HeroManager.
		]]
		teamHeroes = {
			[ DOTA_TEAM_GOODGUYS ] = nil,
			[ DOTA_TEAM_BADGUYS ] = nil,
		},

		-- Атрибут команды для Draft Clash: strength / agility / intelligence / universal
		teamAttributes = {
			[ DOTA_TEAM_GOODGUYS ] = nil,
			[ DOTA_TEAM_BADGUYS ] = nil,
		},

		--[[
			draft[team] = {
				options = { ... },	-- предложенные герои
				pick = nil,			-- выбранный герой
				finished = false,	-- драфт закрыт
				open = false,		-- драфт принимает голоса
				votes = {},			-- { [heroName] = число голосов }
				voters = {},		-- { [playerID] = heroName }
			}
		]]
		draft = {
			[ DOTA_TEAM_GOODGUYS ] = {
				options = {}, pick = nil, finished = false,
				open = false, votes = {}, voters = {},
			},
			[ DOTA_TEAM_BADGUYS ] = {
				options = {}, pick = nil, finished = false,
				open = false, votes = {}, voters = {},
			},
		},
	}
end

-- Полный сброс. Вызывается один раз при инициализации GameMode.
function GameState:Reset()
	self.state = GAME_STATE.MENU
	self.mode = HCT_MODE.NONE

	self.teamHeroes = {
		[ DOTA_TEAM_GOODGUYS ] = nil,
		[ DOTA_TEAM_BADGUYS ] = nil,
	}

	self.teamAttributes = {
		[ DOTA_TEAM_GOODGUYS ] = nil,
		[ DOTA_TEAM_BADGUYS ] = nil,
	}

	self.draft = {
		[ DOTA_TEAM_GOODGUYS ] = {
			options = {}, pick = nil, finished = false,
			open = false, votes = {}, voters = {},
		},
		[ DOTA_TEAM_BADGUYS ] = {
			options = {}, pick = nil, finished = false,
			open = false, votes = {}, voters = {},
		},
	}
end

-----------------------------------------------------------------------------
-- Состояние
-----------------------------------------------------------------------------

function GameState:SetState( newState )
	if self.state == newState then
		return
	end

	local previous = GAME_STATE_NAME[ self.state ]
	self.state = newState
	HCTDebug:LogParts( "state:", previous, "->", self:GetStateName() )
end

function GameState:GetState()
	return self.state
end

function GameState:GetStateName()
	return GAME_STATE_NAME[ self.state ] or "UNKNOWN"
end

function GameState:IsState( state )
	return self.state == state
end

-----------------------------------------------------------------------------
-- Режим
-----------------------------------------------------------------------------

function GameState:SetMode( mode )
	self.mode = mode
	HCTDebug:Log( "mode: " .. self:GetModeName() )
end

function GameState:GetMode()
	return self.mode
end

function GameState:GetModeName()
	return HCT_MODE_NAME[ self.mode ] or "UNKNOWN"
end

-----------------------------------------------------------------------------
-- Команды
-----------------------------------------------------------------------------

function GameState:SetTeamHero( team, heroName )
	self.teamHeroes[ team ] = heroName
end

function GameState:GetTeamHero( team )
	return self.teamHeroes[ team ]
end

function GameState:SetTeamAttribute( team, attribute )
	self.teamAttributes[ team ] = attribute
end

function GameState:GetTeamAttribute( team )
	return self.teamAttributes[ team ]
end

-----------------------------------------------------------------------------
-- Драфт
-----------------------------------------------------------------------------

--[[
	Сохранить новый набор предложений команды.

	Новый набор -- это новый драфт, поэтому прежние голоса
	к нему не относятся и обнуляются вместе с pick.
]]
function GameState:SetDraftOptions( team, options )
	local draft = self.draft[ team ]
	if draft == nil then
		return
	end

	draft.options = options or {}
	draft.pick = nil
	draft.finished = false
	draft.open = false
	draft.votes = {}
	draft.voters = {}
end

function GameState:GetDraftOptions( team )
	local draft = self.draft[ team ]
	if draft == nil then
		return {}
	end
	return draft.options
end

function GameState:SetDraftPick( team, heroName )
	local draft = self.draft[ team ]
	if draft == nil then
		return
	end

	draft.pick = heroName
	draft.finished = true
end

function GameState:GetDraftPick( team )
	local draft = self.draft[ team ]
	if draft == nil then
		return nil
	end
	return draft.pick
end

function GameState:IsDraftFinished( team )
	local draft = self.draft[ team ]
	if draft == nil then
		return false
	end
	return draft.finished == true
end

-- Принимает ли драфт команды голоса прямо сейчас.
function GameState:SetDraftOpen( team, isOpen )
	local draft = self.draft[ team ]
	if draft == nil then
		return
	end

	draft.open = isOpen == true
end

function GameState:IsDraftOpen( team )
	local draft = self.draft[ team ]
	if draft == nil then
		return false
	end
	return draft.open == true
end

--[[
	Принять один голос команды.

	Запись идёт в двух местах и должна оставаться одной операцией:
		votes  -- "сколько у героя голосов";
		voters -- "кто уже голосовал" (проверка 6 в DraftManager).
]]
function GameState:SetDraftVote( team, playerID, heroName )
	local draft = self.draft[ team ]
	if draft == nil or heroName == nil then
		return
	end

	draft.votes[ heroName ] = ( draft.votes[ heroName ] or 0 ) + 1
	draft.voters[ playerID ] = heroName
end

-- Герой, за который playerID уже голосовал, либо nil.
function GameState:GetDraftVote( team, playerID )
	local draft = self.draft[ team ]
	if draft == nil then
		return nil
	end
	return draft.voters[ playerID ]
end

-- Таблица { [heroName] = число голосов }. Копия не делается:
-- подсчёт ведётся на чтение.
function GameState:GetDraftVotes( team )
	local draft = self.draft[ team ]
	if draft == nil then
		return {}
	end
	return draft.votes
end

-- Сколько разных playerID уже проголосовали.
function GameState:CountDraftVoters( team )
	local draft = self.draft[ team ]
	if draft == nil then
		return 0
	end

	local count = 0

	for _ in pairs( draft.voters ) do
		count = count + 1
	end

	return count
end

-----------------------------------------------------------------------------
-- Отладка
-----------------------------------------------------------------------------

function GameState:LogSummary()
	HCTDebug:LogParts( "GameState:", "state =", self:GetStateName(), "| mode =", self:GetModeName() )
	HCTDebug:LogTable( "teamHeroes", self.teamHeroes, 1 )
	HCTDebug:LogTable( "teamAttributes", self.teamAttributes, 1 )
end