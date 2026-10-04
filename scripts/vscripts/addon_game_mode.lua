--[[
	addon_game_mode.lua
	Точка входа VScript. Этот файл загружает движок при старте карты.

	Здесь только require и Activate(). Никакой игровой логики.
	Вся логика -- в core/game_mode.lua и ниже по системам.

	Порядок require важен: сначала утилиты, потом состояние,
	потом ядро, потом пул героев (его использует HeroManager),
	потом режимы (они используют ядро).
]]

-- Утилиты
require( "utils.debug" )
require( "utils.random" )

-- Состояние
require( "core.game_state" )

-- Ядро
require( "core.team_manager" )
require( "core.hero_manager" )

-- Снимок имён героев из itembuilds. Загружается раньше hero_pool:
-- тот использует его как fallback-источник.
require( "draft.hero_names" )

-- Статический mapping primary attributes для героев из hero_names.
-- Runtime LoadKeyValues("scripts/npc/npc_heroes.txt") категории не
-- заполнил (план, раздел 5), поэтому атрибуты живут в проекте.
require( "draft.hero_attributes" )

-- Пул героев -- единственный источник истины по списку героев
require( "draft.hero_pool" )

-- Драфт. Идёт после пула: он берёт предложения из HeroPool.
require( "draft.draft_manager" )

-- Режимы
require( "modes.random_clash" )
require( "modes.draft_clash" )

-- Контроллер. Объявление класса CHeroClashGameMode создаётся в этом файле.
require( "core.game_mode" )

--[[
	Прекеш ресурсов.
	На Phase 1 используются только стандартные ассеты Dota,
	поэтому здесь пусто. Когда понадобятся свои модели/звуки/частицы --
	добавлять PrecacheResource( "model", "*.vmdl", context ) и т.п.
]]
function Precache( context )
end

-- Вызывается движком один раз при старте карты
function Activate()
	GameRules.HeroClashTurbo = CHeroClashGameMode()
	GameRules.HeroClashTurbo:Init()
end