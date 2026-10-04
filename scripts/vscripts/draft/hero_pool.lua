--[[
	draft/hero_pool.lua
	ЕДИНСТВЕННЫЙ источник истины по списку героев и их атрибутам.

	Подтверждено реальным запуском (Phase 1):
		- глобальной таблицы DOTAHeroes в этой сборке НЕТ (DOTAHeroes = nil)
		- обхода всех героев нет ни в штатных .lua игры, ни в бот-скриптах Valve

	Найдено в CDesc (класс CScriptHeroList):
		GetAllHeroes, GetHero, GetHeroCount
	Найдено в FDesc:
		CreateHeroForPlayer(string, handle)
	CreateHeroForPlayer НЕ ВЫЗЫВАЕТСЯ -- он создаёт героя игроку.
	Только печатается как факт.

	ВАЖНО: наличие метода в CDesc НЕ является доказательством наличия
	объекта. Поэтому объект ищется в рантайме, а его работоспособность
	подтверждается фактическим вызовом под pcall.

	Слои:
		1 -- DOTAHeroes           (таблица; в текущей сборке отсутствует)
		2 -- CScriptHeroList      (объект ищется и проверяется в рантайме)
		3 -- DiagnoseApi()        (подробный отчёт, если слои 1-2 пусты)

	Атрибуты НЕ выдумываются. Строка атрибута подставляется только если
	движок сам отдал индекс И в глобалах есть соответствующие константы
	DOTA_ATTRIBUTE_*. Индекс движка сохраняется всегда, в поле
	primaryAttribute. Если констант нет -- attribute остаётся nil.

	Формат возврата не меняется:
		{ { name = "npc_dota_hero_x", attribute = nil, primaryAttribute = 0 }, ... }
]]

HCT_ATTRIBUTE = {
	STRENGTH		= "strength",
	AGILITY			= "agility",
	INTELLIGENCE	= "intelligence",
	UNIVERSAL		= "universal",
}

-- Атрибут команды по умолчанию для Draft Clash (Phase 4 переопределит).
HCT_TEAM_DEFAULT_ATTRIBUTE = {
	[ DOTA_TEAM_GOODGUYS ] = HCT_ATTRIBUTE.STRENGTH,
	[ DOTA_TEAM_BADGUYS ] = HCT_ATTRIBUTE.STRENGTH,
}

HCT_DRAFT_MAIN_COUNT = 4
HCT_DRAFT_EXTRA_COUNT = 1

-- Префикс unit name любого героя в Dota 2.
HCT_HERO_NAME_PREFIX = "npc_dota_hero_"

-- Классы, чей список методов печатается ЦЕЛИКОМ: от них зависит проект.
HCT_DIAGNOSTIC_FULL_CLASSES = { "gamerules", "playerresource" }

-- Класс из CDesc, который по runtime-логу отдаёт список героев.
HCT_HERO_LIST_CLASS = "CScriptHeroList"

-- Сколько методов печатать максимум на один класс.
HCT_DIAGNOSTIC_METHOD_LIMIT = 140

-- Сколько Get*Hero* кандидатов пробовать вызовом.
HCT_DIAGNOSTIC_PROBE_LIMIT = 25

-- Бюджет обхода таблиц, чтобы диагностика не зависла на огромном творе.
HCT_DIAGNOSTIC_SCAN_BUDGET = 4000

--[[
	Сколько героев считать "полным списком".
	В Dota 2 сейчас больше сотни героев. Если CScriptHeroList вернул
	десяток -- это, вероятно, не полный список (например, только герои
	матча), и подключать его как источник нельзя.
]]
HCT_HERO_LIST_MIN_COUNT = 50

--[[
	РАЗРЕШЕНИЕ НА ПЕРЕКЛЮЧЕНИЕ Build() НА CScriptHeroList.

	По умолчанию false. Build() НЕ переключается на HeroList сам,
	даже если рантайм уже подтвердил список (count >= 50).
	Включается одной строкой после того, как подтверждение будет
	принято как рабочий источник.
]]
HCT_HERO_LIST_ALLOW_SOURCE = false

-- Задержки таймера lifecycle-пробы HeroList: сразу, ~1с, ~3с, ~5с.
HCT_TIMING_DELAYS = { 0, 1, 3, 5 }

if HeroPool == nil then
	HeroPool = {
		cache = nil,
		source = "none",
		diagnosed = false,
		heroListProbed = false,
		heroListResult = nil,
		heroListConfirmed = false,
		heroListConfirmedCount = nil,
		timingStarted = false,
		timingListenerRegistered = false,
		scanBudget = 0,
	}
end

----------------------------------------------------------------------------
-- Вспомогательные функции диагностики
----------------------------------------------------------------------------

-- Достать текст описания биндинга (в FDesc это таблица с полем desc).
function HeroPool:DescribeBinding( value )
	if type( value ) == "table" and value.desc ~= nil then
		return tostring( value.desc )
	end
	return tostring( value )
end

-- Является ли строка unit name героя.
function HeroPool:IsHeroUnitName( value )
	if type( value ) ~= "string" then
		return false
	end
	return string.find( value, "^" .. HCT_HERO_NAME_PREFIX ) ~= nil
end

--[[
	Найти все строки вида npc_dota_hero_* внутри произвольного значения.
	Ограничена глубиной и бюджетом обхода, чтобы не зависнуть.
	Возвращает множество (table где ключ -- имя героя, значение = true).
]]
function HeroPool:CollectHeroNames( value, depth, out )
	out = out or {}

	if value == nil or depth < 0 then
		return out
	end

	if self.scanBudget <= 0 then
		return out
	end

	if type( value ) == "string" then
		if self:IsHeroUnitName( value ) and out[ value ] == nil then
			out[ value ] = true
		end
		return out
	end

	if type( value ) ~= "table" then
		return out
	end

	for key, item in pairs( value ) do
		self.scanBudget = self.scanBudget - 1
		self:CollectHeroNames( key, depth - 1, out )
		self:CollectHeroNames( item, depth - 1, out )
		if self.scanBudget <= 0 then
			return out
		end
	end

	return out
end

function HeroPool:CountKeys( tbl )
	local count = 0
	for _ in pairs( tbl ) do
		count = count + 1
	end
	return count
end

-- Короткое описание произвольного значения для лога.
function HeroPool:Summarize( value )
	local valueType = type( value )

	if valueType == "table" then
		local names = self:CollectHeroNames( value, 2 )
		local nameCount = self:CountKeys( names )
		local text = "table, entries = " .. self:CountKeys( value )

		if nameCount > 0 then
			return text .. ", hero names = " .. nameCount
		end

		return text
	end

	if valueType == "string" then
		if self:IsHeroUnitName( value ) then
			return "string (hero unit name) = " .. value
		end

		local clipped = value
		if #clipped > 60 then
			clipped = string.sub( clipped, 1, 60 ) .. "..."
		end
		return "string = " .. clipped
	end

	return valueType .. " = " .. tostring( value )
end

-- Найти глобальный объект, которому принадлежит класс из CDesc.
function HeroPool:ResolveInstance( className )
	local lower = string.lower( className )

	if string.find( lower, "playerresource", 1, true ) ~= nil then
		return PlayerResource, "PlayerResource"
	end

	if string.find( lower, "gamerules", 1, true ) ~= nil then
		return GameRules, "GameRules"
	end

	return nil, nil
end

--[[
	Печать кандидата в едином формате и БЕЗОПАСНЫЙ вызов.
	Вызов идёт только если метод реально существует (type == "function")
	и только под pcall. Неизвестные методы не вызываются.

	Возвращает: usable (bool), result (что вернул вызов)
]]
function HeroPool:PrintCandidate( label, instance, methodName, ... )
	HCTDebug:LogParts( "candidate:", label )

	if instance == nil then
		HCTDebug:Log( "  callable: false (нет глобального объекта-владельца)" )
		HCTDebug:Log( "  result: -" )
		HCTDebug:Log( "  usable: false" )
		return false, nil
	end

	-- Индексирование обёрнуто в pcall: на C++ сущностях отсутствующий
	-- ключ может бросить ошибку, а не вернуть nil.
	local okIndex, fn = pcall( function() return instance[ methodName ] end )

	if not okIndex or type( fn ) ~= "function" then
		HCTDebug:Log( "  callable: false" )
		HCTDebug:Log( "  result: -" )
		HCTDebug:Log( "  usable: false" )
		return false, nil
	end

	HCTDebug:Log( "  callable: true" )

	local argCount = select( "#", ... )
	local ok, result

	if argCount == 0 then
		ok, result = pcall( fn, instance )
	else
		local unpackArgs = unpack or table.unpack
		local args = { ... }
		ok, result = pcall( fn, instance, unpackArgs( args, 1, argCount ) )
	end

	if not ok then
		HCTDebug:Log( "  result: runtime error -> " .. tostring( result ) )
		HCTDebug:Log( "  usable: false" )
		return false, nil
	end

	local names = {}
	if type( result ) == "table" then
		names = self:CollectHeroNames( result, 2 )
	elseif self:IsHeroUnitName( result ) then
		names[ result ] = true
	end

	local nameCount = self:CountKeys( names )

	HCTDebug:Log( "  result: " .. self:Summarize( result ) )
	HCTDebug:Log( "  usable: " .. tostring( nameCount > 0 ) .. " (hero names found: " .. nameCount .. ")" )

	return nameCount > 0, result
end

function HeroPool:PrintList( title, list, limit )
	limit = limit or 40

	if #list == 0 then
		HCTDebug:Log( "  " .. title .. ": ничего не найдено" )
		return
	end

	HCTDebug:Log( "  " .. title .. " (" .. #list .. "):" )
	for i = 1, math.min( #list, limit ) do
		HCTDebug:Log( "    " .. list[ i ] )
	end

	if #list > limit then
		HCTDebug:Log( "    ... и ещё " .. ( #list - limit ) )
	end
end

-- Отсортировать список строк по ключу, заданному функцией.
function HeroPool:SortedNames( tbl, keyword )
	local result = {}

	if type( tbl ) ~= "table" then
		return result
	end

	for name in pairs( tbl ) do
		if type( name ) == "string" and
			( keyword == nil or string.find( string.lower( name ), keyword, 1, true ) ~= nil ) then
			result[ #result + 1 ] = name
		end
	end

	table.sort( result )
	return result
end

----------------------------------------------------------------------------
-- Слой 1: DOTAHeroes
----------------------------------------------------------------------------

function HeroPool:BuildFromDotAHeroes()
	local list = {}

	if type( DOTAHeroes ) ~= "table" then
		return list
	end

	for name, info in pairs( DOTAHeroes ) do
		if self:IsHeroUnitName( name ) then
			-- Атрибут берётся ТОЛЬКО если источник его отдал.
			-- Отсутствующий атрибут остаётся nil -- ничего не домысливаем.
			local attribute = nil
			if type( info ) == "table" and info.attribute ~= nil then
				attribute = info.attribute
			end

			list[ #list + 1 ] = {
				name = name,
				attribute = attribute,
			}
		end
	end

	if #list > 0 then
		self.source = "DOTAHeroes"
	end

	return list
end

--[[
	Слой 3: снимок имён из draft/hero_names.lua.

	Ни DOTAHeroes, ни CScriptHeroList в VScript не дают полного списка.
	hero_names.lua генерируется из поля "hero" файлов itembuilds --
	единственный распакованный список имён героев на диске.

	Атрибутов в этом источнике нет, поэтому у всех записей attribute = nil.
	Этого достаточно для Random Clash (нужно только имя), но недостаточно
	для GetDraftOptions() -- там фильтр по атрибуту вернёт пустоту.

	Функция ничего не меняет в существующих источниках и вызывается
	только когда слои 1-2 вернули пустой список.
]]
function HeroPool:BuildFromHeroNames()
	local list = {}

	if type( HeroNames ) ~= "table" or type( HeroNames.LIST ) ~= "table" then
		return list
	end

	-- Повторная защита от дублей, даже если список пересоберут вручную.
	local seen = {}

	for _, heroName in ipairs( HeroNames.LIST ) do
		if self:IsHeroUnitName( heroName ) and seen[ heroName ] == nil then
			seen[ heroName ] = true

			-- Атрибут берётся из проектного static mapping
			-- (draft/hero_attributes.lua). Если героя там нет -- nil,
			-- ничего не домысливаем.
			local attribute = nil
			if type( HeroAttributes ) == "table" and type( HeroAttributes.MAP ) == "table" then
				attribute = HeroAttributes.MAP[ heroName ]
			end

			list[ #list + 1 ] = {
				name = heroName,
				attribute = attribute,
			}
		end
	end

	if #list > 0 then
		self.source = "hero_names"
	end

	return list
end

----------------------------------------------------------------------------
-- CScriptHeroList: работа с сущностями
----------------------------------------------------------------------------

--[[
	Безопасное чтение метода у объекта.
	Индексация C++ сущности может бросить ошибку, поэтому через pcall.
]]
function HeroPool:SafeMethod( object, methodName )
	if object == nil then
		return nil
	end

	local ok, fn = pcall( function() return object[ methodName ] end )

	if not ok or type( fn ) ~= "function" then
		return nil
	end

	return fn
end

-- Безопасный вызов метода объекта. Возвращает ok, result.
function HeroPool:SafeCall( object, methodName, ... )
	local fn = self:SafeMethod( object, methodName )

	if fn == nil then
		return false, nil
	end

	local argCount = select( "#", ... )

	if argCount == 0 then
		return pcall( fn, object )
	end

	local unpackArgs = unpack or table.unpack
	local args = { ... }
	return pcall( fn, object, unpackArgs( args, 1, argCount ) )
end

--[[
	Достать unit name героя из сущности.
	Порядок источников:
		1) если это уже строка -- вернуть как есть
		2) GetClassname() -- для героев это и есть npc_dota_hero_xxx
		3) GetUnitName()  -- запасной вариант
	Ничего не конструируется и не угадывается.
]]
function HeroPool:ClassnameOf( entity )
	if entity == nil then
		return nil
	end

	if type( entity ) == "string" then
		return entity
	end

	local ok, name = self:SafeCall( entity, "GetClassname" )

	if ok and type( name ) == "string" then
		return name
	end

	return nil
end

function HeroPool:HeroNameOf( entity )
	local classname = self:ClassnameOf( entity )

	if classname ~= nil and self:IsHeroUnitName( classname ) then
		return classname
	end

	local ok, unitName = self:SafeCall( entity, "GetUnitName" )

	if ok and self:IsHeroUnitName( unitName ) then
		return unitName
	end

	-- Ничего не подходит -- возвращаем nil, а не придуманное имя.
	return nil
end

-- Подробная проверка одного hero entity из списка.
function HeroPool:InspectHeroEntity( entity, label )
	HCTDebug:LogParts( "hero entity:", label, "| lua type =", type( entity ) )

	local classname = self:ClassnameOf( entity )
	HCTDebug:LogParts( "  GetClassname() ->", tostring( classname ) )

	local okUnit, unitName = self:SafeCall( entity, "GetUnitName" )
	if okUnit then
		HCTDebug:LogParts( "  GetUnitName() ->", tostring( unitName ) )
	end

	local okHeroID, heroID = self:SafeCall( entity, "GetHeroID" )
	if okHeroID then
		HCTDebug:LogParts( "  GetHeroID() ->", tostring( heroID ) )
	else
		HCTDebug:Log( "  GetHeroID() -> метода нет" )
	end

	-- Атрибут: пробуем только реально существующие методы
	local attributeGetters = {
		"GetPrimaryAttribute",
		"GetHeroAttribute",
		"GetAttribute",
	}

	for _, getter in ipairs( attributeGetters ) do
		if self:SafeMethod( entity, getter ) ~= nil then
			local okAttr, attrIndex = self:SafeCall( entity, getter )
			HCTDebug:LogParts( "  " .. getter .. "() ->", tostring( attrIndex ),
				"| engine name:", tostring( self:GetAttributeNameByIndex( attrIndex ) ) )
		else
			HCTDebug:LogParts( "  " .. getter .. "() -> метода нет" )
		end
	end

	return classname
end

----------------------------------------------------------------------------
-- Атрибут: имя подставляется ТОЛЬКО из констант движка
----------------------------------------------------------------------------

--[[
	Построить соответствие индекс -> имя из констант движка.
	Если DOTA_ATTRIBUTE_* недоступны, соответствие пустое и имена
	атрибутов не подставляются -- остаётся только сырой индекс.
]]
function HeroPool:GetAttributeMap()
	if self.attributeMap ~= nil then
		return self.attributeMap
	end

	local map = {}
	local wanted = {
		{ DOTA_ATTRIBUTE_STRENGTH,		HCT_ATTRIBUTE.STRENGTH },
		{ DOTA_ATTRIBUTE_AGILITY,		HCT_ATTRIBUTE.AGILITY },
		{ DOTA_ATTRIBUTE_INTELLIGENCE,	HCT_ATTRIBUTE.INTELLIGENCE },
		{ DOTA_ATTRIBUTE_UNIVERSAL,		HCT_ATTRIBUTE.UNIVERSAL },
	}

	for _, pair in ipairs( wanted ) do
		if type( pair[ 1 ] ) == "number" then
			map[ pair[ 1 ] ] = pair[ 2 ]
		end
	end

	self.attributeMap = map
	return map
end

function HeroPool:GetAttributeNameByIndex( index )
	if type( index ) ~= "number" then
		return nil
	end

	return self:GetAttributeMap()[ index ]
end

-- Напечатать, что движок знает про константы атрибутов.
function HeroPool:LogAttributeConstants()
	local names = {
		{ "DOTA_ATTRIBUTE_STRENGTH", type( DOTA_ATTRIBUTE_STRENGTH ) },
		{ "DOTA_ATTRIBUTE_AGILITY", type( DOTA_ATTRIBUTE_AGILITY ) },
		{ "DOTA_ATTRIBUTE_INTELLIGENCE", type( DOTA_ATTRIBUTE_INTELLIGENCE ) },
		{ "DOTA_ATTRIBUTE_UNIVERSAL", type( DOTA_ATTRIBUTE_UNIVERSAL ) },
	}

	for _, entry in ipairs( names ) do
		HCTDebug:LogParts( "  " .. entry[ 1 ] .. " =", entry[ 2 ], "->", tostring( _G[ entry[ 1 ] ] ) )
	end

	local map = self:GetAttributeMap()
	HCTDebug:LogParts( "  подтверждённых индексов в движке:", self:CountKeys( map ) )

	if self:CountKeys( map ) == 0 then
		HCTDebug:Warn( "Константы атрибутов недоступны -- имена атрибутов подставляться не будут." )
	end
end

----------------------------------------------------------------------------
-- CScriptHeroList: поиск объекта в рантайме
----------------------------------------------------------------------------

-- Шаг A: что CDesc вообще знает о классе
function HeroPool:DescribeHeroListClass()
	if type( CDesc ) ~= "table" then
		HCTDebug:Log( "  CDesc: недоступен (нужен developer-режим)" )
		return false
	end

	local classDesc = CDesc[ HCT_HERO_LIST_CLASS ]

	if type( classDesc ) ~= "table" or type( classDesc.FDesc ) ~= "table" then
		HCTDebug:LogParts( "  CDesc." .. HCT_HERO_LIST_CLASS .. ": класса нет" )
		return false
	end

	local methods = self:SortedNames( classDesc.FDesc, nil )
	HCTDebug:LogParts( "  CDesc." .. HCT_HERO_LIST_CLASS .. ": найден, методов =", #methods )
	self:PrintList( "методы класса", methods, 60 )

	return true
end

-- Шаг B: CreateHeroForPlayer только печатается, не вызывается
function HeroPool:DescribeCreateHero()
	if type( FDesc ) ~= "table" then
		HCTDebug:Log( "  FDesc: недоступен" )
		return
	end

	local binding = FDesc[ "CreateHeroForPlayer" ]

	if binding == nil then
		HCTDebug:Log( "  FDesc CreateHeroForPlayer: нет" )
		return
	end

	HCTDebug:LogParts( "  FDesc CreateHeroForPlayer ->", self:DescribeBinding( binding ) )
	HCTDebug:Warn( "CreateHeroForPlayer НЕ вызывается: он создаёт героя игроку." )
end

--[[
	Шаг C: глобалы, в имени которых есть "herolist".
	Имена не угадываются -- сканируется весь _G.
]]
function HeroPool:FindHeroListGlobals()
	local found = {}

	for name, value in pairs( _G ) do
		if type( name ) == "string" and
			string.find( string.lower( name ), "herolist", 1, true ) ~= nil then
			found[ #found + 1 ] = name .. " (" .. type( value ) .. ")"
		end
	end

	table.sort( found )
	self:PrintList( "globals with *herolist*", found, 40 )

	return found
end

--[[
	Шаг D: поиск объекта по поведению, а не по имени.
	Любой глобал, у которого callable GetAllHeroes и GetHeroCount,
	кандидат на CScriptHeroList. Это главный способ найти объект,
	потому что он не зависит от того, как объект назван.
]]
function HeroPool:FindHeroListByDuckType()
	local found = {}

	for name, value in pairs( _G ) do
		if type( name ) == "string" and value ~= nil then
			if self:SafeMethod( value, "GetAllHeroes" ) ~= nil and
				self:SafeMethod( value, "GetHeroCount" ) ~= nil then
				found[ #found + 1 ] = name
			end
		end
	end

	table.sort( found )
	self:PrintList( "globals with GetAllHeroes+GetHeroCount", found, 20 )

	return found
end

--[[
	Шаг E: поиск через методы GameRules / PlayerResource.
	Вызываются только Get* без аргументов, каждый под pcall,
	и только те, в имени которых есть "hero" или "list".
]]
function HeroPool:FindHeroListByAccessors()
	local found = {}
	local tried = 0

	for _, className in ipairs( { "GameRules", "PlayerResource" } ) do
		local instance = _G[ className ]

		if type( CDesc ) == "table" and instance ~= nil then
			local classDesc = nil

			for cname, cdesc in pairs( CDesc ) do
				if type( cname ) == "string" and string.lower( cname ) == string.lower( className ) then
					classDesc = cdesc
				end
			end

			if type( classDesc ) == "table" and type( classDesc.FDesc ) == "table" then
				for methodName in pairs( classDesc.FDesc ) do
					if tried < HCT_DIAGNOSTIC_PROBE_LIMIT and type( methodName ) == "string" then
						local lower = string.lower( methodName )

						if string.find( lower, "^get", 1, true ) ~= nil and
							( string.find( lower, "hero", 1, true ) ~= nil or
							  string.find( lower, "list", 1, true ) ~= nil ) then

							tried = tried + 1
							local ok, result = self:SafeCall( instance, methodName )

							if ok and result ~= nil and
								self:SafeMethod( result, "GetAllHeroes" ) ~= nil then
								found[ #found + 1 ] = className .. ":" .. methodName .. "()"
							end
						end
					end
				end
			end
		end
	end

	self:PrintList( "accessors returning hero list object", found, 20 )

	if tried == 0 then
		HCTDebug:Log( "  подходящих Get* методов не найдено" )
	end

	return found
end

----------------------------------------------------------------------------
-- CScriptHeroList: проверка работоспособности
----------------------------------------------------------------------------

-- Определить индексацию GetHero: 0-based или 1-based.
function HeroPool:DetectHeroListIndexing( object, heroCount )
	if heroCount == nil or type( heroCount ) ~= "number" or heroCount < 1 then
		return nil, "неизвестно (heroCount = " .. tostring( heroCount ) .. ")"
	end

	local okZero, zero = self:SafeCall( object, "GetHero", 0 )
	local okOne, one = self:SafeCall( object, "GetHero", 1 )
	local okCount, atCount = self:SafeCall( object, "GetHero", heroCount )

	zero = okZero and zero or nil
	one = okOne and one or nil
	atCount = okCount and atCount or nil

	HCTDebug:LogParts( "  GetHero(0) ->", tostring( zero ) )
	HCTDebug:LogParts( "  GetHero(1) ->", tostring( one ) )
	HCTDebug:LogParts( "  GetHero(" .. heroCount .. ") ->", tostring( atCount ) )

	if zero ~= nil and atCount == nil then
		return 0, "0-based (валидны 0.." .. ( heroCount - 1 ) .. ")"
	end

	if zero == nil and atCount ~= nil then
		return 1, "1-based (валидны 1.." .. heroCount .. ")"
	end

	if zero ~= nil and atCount ~= nil then
		return nil, "неоднозначно: валидны и 0, и " .. heroCount
	end

	return nil, "индексация не определилась"
end

--[[
	Полная проверка объекта-кандидата CScriptHeroList.
	Возвращает результат: { label, names = {...}, heroCount, baseIndex, sample }
]]
function HeroPool:ProbeHeroListObject( object, label )
	local result = {
		label = label,
		names = {},
		nameSet = {},
		heroCount = nil,
		baseIndex = nil,
		sample = {},
		entity = nil,
		attributeIndex = nil,
		attributeIndexByName = {},
	}

	HCTDebug:LogParts( "candidate:", label )

	-- 1) GetHeroCount
	local okCount, heroCount = self:SafeCall( object, "GetHeroCount" )
	result.heroCount = okCount and type( heroCount ) == "number" and heroCount or nil
	HCTDebug:Log( "  callable: true" )
	HCTDebug:LogParts( "  GetHeroCount() ->", tostring( heroCount ), "| GetHeroCount callable:", tostring( self:SafeMethod( object, "GetHeroCount" ) ~= nil ) )

	-- 2) GetAllHeroes
	local okAll, allHeroes = self:SafeCall( object, "GetAllHeroes" )
	HCTDebug:LogParts( "  GetAllHeroes() callable:", tostring( self:SafeMethod( object, "GetAllHeroes" ) ~= nil ) )

	if not okAll then
		HCTDebug:LogParts( "  result: runtime error ->", tostring( allHeroes ) )
		HCTDebug:Log( "  usable: false" )
		return result
	end

	if type( allHeroes ) ~= "table" then
		HCTDebug:LogParts( "  result:", self:Summarize( allHeroes ) )
		HCTDebug:Log( "  usable: false (GetAllHeroes вернул не таблицу)" )
		return result
	end

	HCTDebug:LogParts( "  result: table, entries =", self:CountKeys( allHeroes ) )

	-- Lua-типы первых элементов: важно различить entity-объекты и числа-хэндлы
	local typeSamples = {}
	local sampleIndex = 0

	for _, item in pairs( allHeroes ) do
		sampleIndex = sampleIndex + 1
		if sampleIndex <= 10 then
			typeSamples[ #typeSamples + 1 ] = type( item )
		end
	end

	HCTDebug:LogParts( "  lua type первых элементов:", table.concat( typeSamples, "," ) )
	HCTDebug:Log( "  (если это числа, а не object/userdata -- нужны entity-объекты, не хэндлы)" )

	-- 3) Перебор элементов: берём classname, оставляем только героев
	-- Сначала собираем entity+classname один раз, чтобы сортировка
	-- не дёргала C++ методы на каждом сравнении.
	local scanned = {}

	for _, item in pairs( allHeroes ) do
		if item ~= nil then
			local classname = self:ClassnameOf( item )
			scanned[ #scanned + 1 ] = { entity = item, classname = classname }
		end
	end

	table.sort( scanned, function( a, b )
		local ca = a.classname or ""
		local cb = b.classname or ""
		return ca < cb
	end )

	local kept = 0
	local attributeIndexByName = {}
	local attributeSample = {}
	local withAttribute = 0

	for _, entry in ipairs( scanned ) do
		local name = self:HeroNameOf( entry.entity )

		if name ~= nil and result.nameSet[ name ] == nil then
			result.nameSet[ name ] = true
			result.names[ #result.names + 1 ] = name
			result.entity = entry.entity
			kept = kept + 1

			--[[
				Индекс атрибута берём из того же entity, которое уже
				отдало classname. Имя атрибута не подставляется здесь --
				только позже, через константы движка.
			]]
			local okAttr, attrIndex = self:SafeCall( entry.entity, "GetPrimaryAttribute" )

			if okAttr and type( attrIndex ) == "number" then
				attributeIndexByName[ name ] = attrIndex
				withAttribute = withAttribute + 1

				if #attributeSample < 5 then
					attributeSample[ #attributeSample + 1 ] = name .. "=" .. tostring( attrIndex ) ..
						" (" .. tostring( self:GetAttributeNameByIndex( attrIndex ) ) .. ")"
				end
			end
		end
	end

	result.attributeIndexByName = attributeIndexByName

	-- Первый герой задаёт пример для вердикта
	if result.attributeIndexByName[ result.names[ 1 ] ] ~= nil then
		result.attributeIndex = result.attributeIndexByName[ result.names[ 1 ] ]
	end

	HCTDebug:LogParts( "  элементов в таблице:", #scanned, "| из них npc_dota_hero_*:", kept )
	HCTDebug:LogParts( "  GetPrimaryAttribute получен для", withAttribute, "героев из", kept )

	if #attributeSample > 0 then
		HCTDebug:Log( "  примеры атрибутов:" )
		for _, sample in ipairs( attributeSample ) do
			HCTDebug:LogParts( "    " .. sample )
		end
	end

	-- 4) Примеры classname
	for i = 1, math.min( 10, #result.names ) do
		result.sample[ #result.sample + 1 ] = result.names[ i ]
		HCTDebug:LogParts( "    [" .. i .. "]", result.names[ i ] )
	end

	-- 5) Индексация GetHero
	local baseIndex, note = self:DetectHeroListIndexing( object, result.heroCount )
	result.baseIndex = baseIndex
	HCTDebug:LogParts( "  индексация GetHero:", note )

	-- 6) Первый элемент через GetHero -- проверяем, что он герой
	local probeIndex = baseIndex
	if probeIndex == nil then
		probeIndex = 1
	end

	local okGet, heroEntity = self:SafeCall( object, "GetHero", probeIndex )
	if okGet and heroEntity ~= nil then
		HCTDebug:LogParts( "  GetHero(" .. probeIndex .. ") вернул сущность, проверяю:" )
		self:InspectHeroEntity( heroEntity, label .. ".GetHero(" .. probeIndex .. ")" )
	else
		HCTDebug:LogParts( "  GetHero(" .. probeIndex .. ") ->", tostring( heroEntity ) )
	end

	HCTDebug:Log( "  usable: " .. tostring( #result.names > 0 ) )

	return result
end

--[[
	Полная проба CScriptHeroList. Одноразовая.
	Ищет объект в рантайме и проверяет его поведением.
	CreateHeroForPlayer не вызывается.
]]
function HeroPool:ProbeHeroListApi()
	if self.heroListProbed then
		return self.heroListResult
	end
	self.heroListProbed = true

	HCTDebug:Log( "CScriptHeroList: RUNTIME PROBE" )

	HCTDebug:LogParts( "  CDesc =", type( CDesc ), "| FDesc =", type( FDesc ) )

	HCTDebug:Log( "  --- класс в CDesc ---" )
	local classExists = self:DescribeHeroListClass()

	HCTDebug:Log( "  --- CreateHeroForPlayer (не вызывается) ---" )
	self:DescribeCreateHero()

	HCTDebug:Log( "  --- атрибуты: константы движка ---" )
	self:LogAttributeConstants()

	HCTDebug:Log( "  --- поиск глобала по имени *herolist* ---" )
	local namedGlobals = self:FindHeroListGlobals()

	HCTDebug:Log( "  --- поиск объекта по поведению (GetAllHeroes + GetHeroCount) ---" )
	local duckGlobals = self:FindHeroListByDuckType()

	HCTDebug:Log( "  --- поиск через accessors GameRules / PlayerResource ---" )
	local accessors = self:FindHeroListByAccessors()

	----------------------------------------------------------------------------
	-- Собираем уникальные кандидаты и проверяем каждый
	----------------------------------------------------------------------------

	local candidates = {}
	local seen = {}

	local function addCandidate( key, object )
		if object == nil or seen[ key ] then
			return
		end
		seen[ key ] = true
		candidates[ #candidates + 1 ] = { key = key, object = object }
	end

	-- прямые обращения по имени, только если глобал реально есть
	for _, name in ipairs( { "HeroList", HCT_HERO_LIST_CLASS } ) do
		if _G[ name ] ~= nil then
			addCandidate( "global:" .. name, _G[ name ] )
		end
	end

	-- найденные глобалы
	for _, entry in ipairs( namedGlobals ) do
		local name = string.match( entry, "^([^ ]+)" )
		if name ~= nil and _G[ name ] ~= nil then
			addCandidate( "global:" .. name, _G[ name ] )
		end
	end

	for _, name in ipairs( duckGlobals ) do
		addCandidate( "global:" .. name, _G[ name ] )
	end

	-- accessors
	for _, accessor in ipairs( accessors ) do
		local ownerName, methodName = string.match( accessor, "^([^:]+):(.+)%(" )
		if ownerName ~= nil and methodName ~= nil then
			local instance = _G[ ownerName ]
			local ok, result = self:SafeCall( instance, methodName )
			if ok and result ~= nil then
				addCandidate( accessor, result )
			end
		end
	end

	----------------------------------------------------------------------------
	-- Проверяем кандидатов
	----------------------------------------------------------------------------

	local best = nil

	if #candidates == 0 then
		HCTDebug:Warn( "Объект CScriptHeroList в рантайме НЕ НАЙДЕН." )

		if classExists then
			HCTDebug:Warn( "Класс есть в CDesc, но ни один глобал не выглядит его экземпляром." )
			HCTDebug:Warn( "Нужен другой путь доступа -- возможно, из C++ или Panorama."
				.. " Список атрибутов класса уже напечатан выше." )
		end
	end

	for _, candidate in ipairs( candidates ) do
		HCTDebug:Header( "проверка кандидата: " .. candidate.key )

		local result = self:ProbeHeroListObject( candidate.object, candidate.key )

		if #result.names > 0 then
			if best == nil or #result.names > #best.names then
				best = result
			end
		end
	end

	if best ~= nil then
		HCTDebug:Header( "CScriptHeroList: ИТОГ ПРОБЫ" )
		HCTDebug:LogParts( "  объект:", best.label )
		HCTDebug:LogParts( "  GetHeroCount() =", tostring( best.heroCount ) )
		HCTDebug:LogParts( "  героев найдено:", #best.names )
		HCTDebug:LogParts( "  пример:", tostring( best.sample[ 1 ] ) )

		if best.heroCount ~= nil and best.heroCount < HCT_HERO_LIST_MIN_COUNT then
			HCTDebug:Warn( "Это меньше " .. HCT_HERO_LIST_MIN_COUNT ..
				" -- вероятно, не полный список всех героев. Как источник НЕ подключается." )
		end
	else
		HCTDebug:Log( "Ни один кандидат не вернул npc_dota_hero_*." )
	end

	self.heroListResult = best
	return best
end

--[[
	Слой 2: построение пула из CScriptHeroList.
	Подключается ТОЛЬКО если проба подтвердила полный список
	И включён явный флаг HCT_HERO_LIST_ALLOW_SOURCE.
]]
function HeroPool:BuildFromHeroList()
	if HCT_HERO_LIST_ALLOW_SOURCE ~= true then
		return {}
	end

	local best = self:ProbeHeroListApi()

	if best == nil or #best.names == 0 then
		return {}
	end

	-- Строгая проверка: список должен быть полным
	if best.heroCount ~= nil and best.heroCount < HCT_HERO_LIST_MIN_COUNT then
		return {}
	end

	local list = {}
	local attributeIndexByName = best.attributeIndexByName or {}

	for _, name in ipairs( best.names ) do
		list[ #list + 1 ] = {
			name = name,
			attribute = self:GetAttributeNameByIndex( attributeIndexByName[ name ] ),
			primaryAttribute = attributeIndexByName[ name ],
		}
	end

	self.source = "CScriptHeroList"
	return list
end

----------------------------------------------------------------------------
-- CScriptHeroList: lifecycle / timing проба
--
-- Рантайм-факт: глобальный HeroList существует, но GetHeroCount()
-- и GetAllHeroes() отдают 0. Стандартный выбор героев позже работает.
-- Значит вопрос не "какой API", а "когда наполняется".
--
-- CreateHeroForPlayer не вызывается нигде в этом блоке.
----------------------------------------------------------------------------

-- Лог с точным префиксом [HCT][HeroListTiming]
function HeroPool:TimingLog( ... )
	print( "[HCT][HeroListTiming] " .. HCTDebug:Join( ... ) )
end

--[[
	Игровое время для метки t=...
	GetGameTime живёт на CDOTAGameRules (метод есть в CDesc из лога),
	а НЕ на игровой сущности режима. Поэтому сначала пробуем GameRules,
	и только потом сущность режима. Если недоступно оба -- печатается "?".
]]
function HeroPool:GetGameTimeSafe()
	if type( GameRules ) == "nil" then
		return "?"
	end

	local okTime, value = pcall( function() return GameRules:GetGameTime() end )

	if okTime and type( value ) == "number" then
		return tostring( value )
	end

	local okEntity, entity = pcall( function() return GameRules:GetGameModeEntity() end )

	if not okEntity or entity == nil then
		return "?"
	end

	local fn = self:SafeMethod( entity, "GetGameTime" )

	if fn == nil then
		return "?"
	end

	local okTime2, value2 = pcall( fn, entity )

	if okTime2 and type( value2 ) == "number" then
		return tostring( value2 )
	end

	return "?"
end

--[[
	Одна проба HeroList в конкретный момент времени.
	Всё через pcall. Вердикт: EMPTY_TOO_EARLY / POPULATED / NOT_FOUND.
]]
function HeroPool:ProbeHeroListTiming( reason, delay )
	local heroList = _G[ "HeroList" ]

	self:TimingLog( "t=" .. self:GetGameTimeSafe(),
		"| reason=" .. tostring( reason ),
		"| delay=" .. tostring( delay ) )

	if heroList == nil then
		self:TimingLog( "VERDICT: NOT_FOUND (глобаль HeroList отсутствует)" )
		return
	end

	-- 1) GetHeroCount
	local okCount, rawCount = self:SafeCall( heroList, "GetHeroCount" )
	local count = nil

	if okCount and type( rawCount ) == "number" then
		count = rawCount
	end

	self:TimingLog( "count=" .. tostring( count ),
		"| GetHeroCount ok=" .. tostring( okCount ),
		"| raw=" .. tostring( rawCount ) )

	-- 2) GetAllHeroes
	local okAll, allHeroes = self:SafeCall( heroList, "GetAllHeroes" )
	local size = 0

	if okAll and type( allHeroes ) == "table" then
		size = self:CountKeys( allHeroes )
	end

	self:TimingLog( "GetAllHeroes ok=" .. tostring( okAll ),
		"| type=" .. type( allHeroes ),
		"| size=" .. tostring( size ) )

	-- 3) первые 3-5 элементов: GetClassname() и GetUnitName()
	if okAll and type( allHeroes ) == "table" then
		local items = {}

		for _, item in pairs( allHeroes ) do
			items[ #items + 1 ] = item
			if #items >= 5 then
				break
			end
		end

		if #items == 0 then
			self:TimingLog( "  элементов в таблице нет" )
		end

		for i = 1, #items do
			local item = items[ i ]
			local classname = self:ClassnameOf( item )
			local okUnit, unitName = self:SafeCall( item, "GetUnitName" )

			self:TimingLog( "  item[" .. i .. "]",
				"luaType=" .. type( item ),
				"| GetClassname()=" .. tostring( classname ),
				"| GetUnitName()=" .. tostring( okUnit and unitName or "<метода нет>" ) )
		end
	end

	-- 4) если список наполнен -- глубокая проверка
	if count ~= nil and count > 0 then
		self:TimingLog( "count > 0 -- глубокая проверка" )

		local baseIndex, note = self:DetectHeroListIndexing( heroList, count )
		self:TimingLog( "индексация GetHero: " .. tostring( note ) )

		local probeIndex = baseIndex
		if probeIndex == nil then
			probeIndex = 1
		end

		local okHero, heroEntity = self:SafeCall( heroList, "GetHero", probeIndex )

		if okHero and heroEntity ~= nil then
			self:InspectHeroEntity( heroEntity, "HeroList.GetHero(" .. probeIndex .. ")" )
		else
			self:TimingLog( "  GetHero(" .. probeIndex .. ") ->", tostring( heroEntity ) )
		end

		self:TimingLog( "VERDICT: POPULATED" )

		if count >= HCT_HERO_LIST_MIN_COUNT then
			self.heroListConfirmed = true
			self.heroListConfirmedCount = count
			self:TimingLog( "count >= " .. HCT_HERO_LIST_MIN_COUNT ..
				" -- HeroList ПОДТВЕРЖДЁН как источник полного пула героев" )
			self:TimingLog( "Build() НЕ переключается автоматически: HCT_HERO_LIST_ALLOW_SOURCE = false" )
		else
			self:TimingLog( "count < " .. HCT_HERO_LIST_MIN_COUNT ..
				" -- список неполный, подтверждения нет" )
		end

		return
	end

	-- 5) список пуст
	if count ~= nil then
		self:TimingLog( "VERDICT: EMPTY_TOO_EARLY (объект есть, count = 0)" )
	else
		self:TimingLog( "VERDICT: NOT_FOUND (GetHeroCount не вернул число: " .. tostring( rawCount ) .. ")" )
	end
end

-- Отложить пробу через SetContextThink игровой сущности.
function HeroPool:ScheduleTimingProbe( reason, delay )
	if delay <= 0 then
		self:ProbeHeroListTiming( reason, delay )
		return
	end

	if type( GameRules ) == "nil" then
		self:TimingLog( "GameRules недоступен -- проба delay=" .. tostring( delay ) .. " пропущена" )
		return
	end

	local okEntity, entity = pcall( function() return GameRules:GetGameModeEntity() end )

	if not okEntity or entity == nil then
		self:TimingLog( "GetGameModeEntity() недоступна -- проба delay=" .. tostring( delay ) .. " пропущена" )
		return
	end

	local contextName = "HeroClashHeroListTiming_" .. tostring( delay )

	local ok, err = pcall( function()
		entity:SetContextThink( contextName, function()
			self:ProbeHeroListTiming( reason, delay )
		end, delay )
	end )

	if not ok then
		self:TimingLog( "SetContextThink упал для delay=" .. tostring( delay ) .. ": " .. tostring( err ) )
	end
end

--[[
	Обработчик события game_rules_state_change.

	Подписан через Dynamic_Wrap с context = HeroPool, поэтому движок
	передаёт первым аргументом сам HeroPool (сигнатура с двоеточием).

	Интересует только DOTA_GAMERULES_STATE_HERO_SELECTION:
	в этот момент стандартный выбор героев уже идёт, и список
	должен быть наполнен. Любое другое состояние тоже даёт
	немедленную пробу -- это дешёвый способ поймать момент later.
]]
function HeroPool:OnTimingStateChange( event )
	local okState, state = pcall( function() return GameRules:State_Get() end )

	if not okState then
		state = nil
	end

	if state == DOTA_GAMERULES_STATE_HERO_SELECTION then
		self:TimingLog( "EVENT HERO_SELECTION -> probe" )
		self:ProbeHeroListTiming( "state:HERO_SELECTION", 0 )

		-- Дополнительная отложенная проверка через 2 секунды после HERO_SELECTION.
		self:ScheduleTimingProbe( "state:HERO_SELECTION+2s", 2 )
	else
		self:TimingLog( "событие game_rules_state_change -> state=" .. tostring( state ) ..
			" -- немедленная проба" )
		self:ProbeHeroListTiming( "state_change", 0 )
	end
end

--[[
	Подписка на смену состояния игры.

	ListenToGameEvent в этом движке требует РОВНО 3 аргумента:
		ListenToGameEvent( eventName, callback, context )
	Со вторым набором идёт ошибка движка:
		"ListenToGameEvent called with 2 arguments - expected 3"

	Штатный шаблон Valve (Conquest, hero_demo, last_hit_trainer):
		ListenToGameEvent( "game_rules_state_change",
		                   Dynamic_Wrap( self, "OnGameRulesStateChange" ), self )

	Context -- сам HeroPool, чтобы обработчик вызывал его методы.
]]
function HeroPool:RegisterTimingListener()
	if self.timingListenerRegistered == true then
		return
	end

	if type( ListenToGameEvent ) ~= "function" then
		self:TimingLog( "ListenToGameEvent недоступен -- перехват состояния отключён" )
		return
	end

	if type( Dynamic_Wrap ) ~= "function" then
		self:TimingLog( "Dynamic_Wrap недоступен -- перехват состояния отключён" )
		return
	end

	self.timingListenerRegistered = true

	local ok, err = pcall( function()
		ListenToGameEvent(
			"game_rules_state_change",
			Dynamic_Wrap( HeroPool, "OnTimingStateChange" ),
			HeroPool
		)
	end )

	if not ok then
		self:TimingLog( "ListenToGameEvent упал: " .. tostring( err ) )
		self.timingListenerRegistered = false
		return
	end

	self:TimingLog( "подписка game_rules_state_change установлена (context = HeroPool)" )
end

-- Запустить цепочку проб: 0 / 1 / 3 / 5 секунд. Одноразово.
function HeroPool:StartTimingProbe( reason )
	reason = reason or "start"

	if self.timingStarted == true then
		self:ProbeHeroListTiming( reason .. "(повтор)", 0 )
		return
	end

	self.timingStarted = true

	self:TimingLog( "=== старт lifecycle-пробы (reason=" .. tostring( reason ) .. ") ===" )

	self:RegisterTimingListener()

	for _, delay in ipairs( HCT_TIMING_DELAYS ) do
		self:ScheduleTimingProbe( reason, delay )
	end
end

----------------------------------------------------------------------------
-- Слой 3: подробная диагностика API
----------------------------------------------------------------------------

-- Шаг 1: глобалы, в имени которых есть "hero"
function HeroPool:DiagnoseGlobals()
	local globals = {}

	for name in pairs( _G ) do
		if type( name ) == "string" and string.find( string.lower( name ), "hero", 1, true ) ~= nil then
			globals[ #globals + 1 ] = name .. " (" .. type( _G[ name ] ) .. ")"
		end
	end

	table.sort( globals )
	self:PrintList( "globals with *hero*", globals, 60 )
end

-- Шаг 2: свободные функции движка (FDesc), в имени которых есть "hero"
function HeroPool:DiagnoseFreeFunctions()
	if type( FDesc ) ~= "table" then
		HCTDebug:Log( "  FDesc: недоступен" )
		return {}
	end

	local found = {}
	local foundNames = {}

	for name, desc in pairs( FDesc ) do
		if type( name ) == "string" and string.find( string.lower( name ), "hero", 1, true ) ~= nil then
			found[ #found + 1 ] = name .. "  --  " .. self:DescribeBinding( desc )
			foundNames[ name ] = true
		end
	end

	table.sort( found )
	self:PrintList( "FDesc: functions *hero*", found, 40 )

	return foundNames
end

-- Шаг 3+4+5: классы из CDesc
function HeroPool:DiagnoseClasses()
	if type( CDesc ) ~= "table" then
		HCTDebug:Log( "  CDesc: недоступен" )
		return
	end

	local classCount = self:CountKeys( CDesc )
	HCTDebug:LogParts( "  CDesc classes total:", classCount )

	local heroClasses = {}
	local fullClasses = {}

	for className, classDesc in pairs( CDesc ) do
		if type( className ) == "string" and type( classDesc ) == "table" and type( classDesc.FDesc ) == "table" then
			local lower = string.lower( className )

			if string.find( lower, "hero", 1, true ) ~= nil then
				heroClasses[ #heroClasses + 1 ] = className
			end

			for _, wanted in ipairs( HCT_DIAGNOSTIC_FULL_CLASSES ) do
				if string.find( lower, wanted, 1, true ) ~= nil then
					fullClasses[ #fullClasses + 1 ] = className
					break
				end
			end
		end
	end

	table.sort( heroClasses )
	table.sort( fullClasses )

	self:PrintList( "CDesc: class names with *hero*", heroClasses, 40 )

	for _, className in ipairs( fullClasses ) do
		local methods = self:SortedNames( CDesc[ className ].FDesc, nil )
		self:PrintList( "CDesc." .. className .. ": ALL methods", methods, HCT_DIAGNOSTIC_METHOD_LIMIT )
	end

	for _, className in ipairs( heroClasses ) do
		local methods = self:SortedNames( CDesc[ className ].FDesc, "hero" )
		if #methods > 0 then
			self:PrintList( "CDesc." .. className .. ": methods *hero*", methods, 40 )
		end
	end

	return heroClasses
end

--[[
	Шаг 6: автопроба найденных методов.
	Вызываются ТОЛЬКО Get*Hero* без аргументов -- такие геттеры
	не могут изменить состояние игры. Каждый вызов под pcall.
]]
function HeroPool:ProbeDiscoveredProviders()
	if type( CDesc ) ~= "table" then
		HCTDebug:Warn( "CDesc недоступен -- автопроба Get*Hero* пропущена (нужен developer-режим)" )
		return {}
	end

	local tried = 0
	local foundList = {}

	for className, classDesc in pairs( CDesc ) do
		if tried >= HCT_DIAGNOSTIC_PROBE_LIMIT then
			break
		end

		if type( className ) == "string" and type( classDesc ) == "table" and type( classDesc.FDesc ) == "table" then
			local instance, instanceLabel = self:ResolveInstance( className )

			if instance ~= nil then
				for methodName in pairs( classDesc.FDesc ) do
					if tried >= HCT_DIAGNOSTIC_PROBE_LIMIT then
						break
					end

					local lower = string.lower( methodName )
					local okIndex, fn = pcall( function() return instance[ methodName ] end )

					if type( methodName ) == "string" and
						okIndex and
						string.find( lower, "^get", 1, true ) ~= nil and
						string.find( lower, "hero", 1, true ) ~= nil and
						type( fn ) == "function" then

						tried = tried + 1

						local usable, result = self:PrintCandidate(
							instanceLabel .. ":" .. methodName,
							instance,
							methodName
						)

						if usable then
							foundList[ #foundList + 1 ] = instanceLabel .. ":" .. methodName .. " -> " .. self:Summarize( result )
						end
					end
				end
			end
		end
	end

	if tried == 0 then
		HCTDebug:Log( "  нет вызываемых Get*Hero* методов у GameRules / PlayerResource" )
	end

	return foundList
end

-- Шаг 7: целевые пробы с настоящими аргументами
function HeroPool:ProbeTargeted()
	HCTDebug:Header( "STEP 7: целевые пробы с аргументами" )

	-- Подтверждённые рабочие API: получаем реальный playerID
	if type( PlayerResource ) == "nil" then
		HCTDebug:Warn( "PlayerResource недоступен -- целевые пробы с аргументами пропущены" )
		return
	end

	local ids = {}
	-- Штатный обход playerID от 0 до DOTA_MAX_TEAM_PLAYERS-1 с проверкой
	-- наличия контроллера. PlayerResource:GetAllPlayerIDs() в движке нет.
	for playerID = 0, ( DOTA_MAX_TEAM_PLAYERS - 1 ) do
		local hPlayer = PlayerResource:GetPlayer( playerID )

		if hPlayer then
			ids[ #ids + 1 ] = playerID
		end
	end

	local idList = {}
	for _, playerID in pairs( ids ) do
		idList[ #idList + 1 ] = tostring( playerID )
	end
	table.sort( idList )
	self:PrintList( "перебор playerID (PlayerResource:GetPlayer)", idList, 20 )

	local firstID = ids[ 1 ]

	if firstID == nil then
		HCTDebug:Warn( "нет ни одного playerID -- целевые пробы с аргументами пропущены" )
		return
	end

	self:PrintCandidate( "PlayerResource:GetPlayerTeam(" .. firstID .. ")", PlayerResource, "GetPlayerTeam", firstID )
	self:PrintCandidate( "PlayerResource:GetNumPlayersOnTeam(DOTA_TEAM_GOODGUYS)", PlayerResource, "GetNumPlayersOnTeam", DOTA_TEAM_GOODGUYS )
	self:PrintCandidate( "PlayerResource:GetNumPlayers()", PlayerResource, "GetNumPlayers" )

	-- Перепроверка методов, которых нет на GameRules
	self:PrintCandidate( "GameRules:GetTeamPlayers(DOTA_TEAM_GOODGUYS)", GameRules, "GetTeamPlayers", DOTA_TEAM_GOODGUYS )
	self:PrintCandidate( "GameRules:GetPlayerTeam(" .. firstID .. ")", GameRules, "GetPlayerTeam", firstID )
	self:PrintCandidate( "GameRules:GetPlayerCountForTeam(DOTA_TEAM_GOODGUYS)", GameRules, "GetPlayerCountForTeam", DOTA_TEAM_GOODGUYS )

	-- Возможный источник списка героев: sibling из лога игры SetPossibleHeroSelection
	local _, possible = self:PrintCandidate(
		"PlayerResource:GetPossibleHeroSelection(" .. firstID .. ")",
		PlayerResource,
		"GetPossibleHeroSelection",
		firstID
	)

	if possible ~= nil then
		self:PrintList( "GetPossibleHeroSelection content", self:SortedNames( possible, "npc_dota_hero_" ), 200 )
	end

	-- Реальная hero entity: можно ли узнать атрибут из героя
	local _, heroEntity = self:PrintCandidate(
		"PlayerResource:GetPlayerHero(" .. firstID .. ")",
		PlayerResource,
		"GetPlayerHero",
		firstID
	)

	if heroEntity == nil then
		HCTDebug:Warn( "GetPlayerHero вернул nil -- атрибут героя проверить нечем (герой ещё не выбран)" )
		return
	end

	local heroMethods = {
		"GetUnitName",
		"IsHero",
		"GetPrimaryAttribute",
		"GetHeroLevel",
		"GetTeam",
		"GetPlayerOwnerID",
	}

	for _, methodName in ipairs( heroMethods ) do
		self:PrintCandidate( "hero entity:" .. methodName, heroEntity, methodName )
	end
end

--[[
	Полная диагностика источников списка героев.
	Одноразовая. Печатает только то, что реально есть в рантайме.
]]
function HeroPool:DiagnoseApi()
	if self.diagnosed then
		return
	end
	self.diagnosed = true

	HCTDebug:Log( "HERO API DIAGNOSTIC" )

	HCTDebug:LogParts( "DOTAHeroes =", type( DOTAHeroes ), "| FDesc =", type( FDesc ), "| CDesc =", type( CDesc ) )
	HCTDebug:Log( "FDesc/CDesc заполняются движком только в developer-режиме." )
	HCTDebug:Log( "Если здесь nil -- введи в консоли: developer 1" )

	self.scanBudget = HCT_DIAGNOSTIC_SCAN_BUDGET

	HCTDebug:Header( "STEP 1: globals *hero*" )
	self:DiagnoseGlobals()

	HCTDebug:Header( "STEP 2: FDesc functions *hero*" )
	local freeFunctions = self:DiagnoseFreeFunctions()

	HCTDebug:Header( "STEP 3-5: CDesc classes" )
	self:DiagnoseClasses()

	-- Отдельная проба найденного класса. Идемпотентна.
	HCTDebug:Header( "CScriptHeroList" )
	self:ProbeHeroListApi()

	HCTDebug:Header( "STEP 6: автопроба Get*Hero* без аргументов" )
	local providers = self:ProbeDiscoveredProviders()

	HCTDebug:Header( "STEP 7: целевые пробы с аргументами" )
	self:ProbeTargeted()

	----------------------------------------------------------------------------
	-- Вердикт
	----------------------------------------------------------------------------

	HCTDebug:Header( "STEP 8: VERDICT" )

	if #providers > 0 then
		HCTDebug:Log( "Провайдеры списка героев найдены:" )
		self:PrintList( "provider", providers, 20 )
	else
		HCTDebug:Warn( "Ни один Get*Hero* метод не вернул npc_dota_hero_* -- источник списка НЕ НАЙДЕН." )
	end

	if #freeFunctions > 0 then
		HCTDebug:Warn( "В FDesc есть функции с *hero*: см. STEP 2, они вызываются только вручную." )
	end

	local best = self.heroListResult

	if best ~= nil and #best.names > 0 then
		HCTDebug:Log( "VERDICT: source CScriptHeroList НАЙДЕН" )
		HCTDebug:LogParts( "VERDICT: героев =", #best.names, "| GetHeroCount() =", tostring( best.heroCount ) )
		HCTDebug:LogParts( "VERDICT: пример classname =", tostring( best.sample[ 1 ] ) )

		local probeAttribute = self:GetAttributeNameByIndex( best.attributeIndex )
		HCTDebug:LogParts( "VERDICT: attribute =", tostring( probeAttribute ),
			"(engine index =", tostring( best.attributeIndex ), ")" )
	else
		HCTDebug:Log( "VERDICT: source CScriptHeroList НЕ НАЙДЕН" )
		HCTDebug:Log( "VERDICT: количество героев = 0" )
		HCTDebug:Log( "VERDICT: пример classname = нет" )
		HCTDebug:Log( "VERDICT: attribute = нет данных" )
	end

	HCTDebug:Log( "Чтобы расширить поиск: console script_help all" )
end

----------------------------------------------------------------------------
-- Сборка пула
----------------------------------------------------------------------------

function HeroPool:Build()
	if self.cache ~= nil then
		return self.cache
	end

	--[[
		При первом обращении к пулу запускаем lifecycle-пробу HeroList.
		Build() вызывается из самопроверки Phase 1, поэтому это самый
		ранний доступный момент без правки других файлов.
	]]
	self:StartTimingProbe( "Build" )

	self.source = "none"
	self.scanBudget = HCT_DIAGNOSTIC_SCAN_BUDGET

	-- Слой 1: DOTAHeroes
	local list = self:BuildFromDotAHeroes()

	-- Слой 2: CScriptHeroList -- объект ищется и проверяется в рантайме
	if #list == 0 then
		list = self:BuildFromHeroList()
	end

	-- Слой 3: снимок имён героев из itembuilds (draft/hero_names.lua)
	if #list == 0 then
		list = self:BuildFromHeroNames()
	end

	-- Слой 4: подробный отчёт, если источник не найден
	if #list == 0 then
		self:DiagnoseApi()
	end

	-- Стабильный порядок, чтобы логи и дебаг были предсказуемыми
	table.sort( list, function( a, b ) return a.name < b.name end )

	self.cache = list

	HCTDebug:LogParts( "HeroPool: героев =", #list, "| источник =", self.source )

	if #list == 0 then
		HCTDebug:Warn( "Пул пуст: подтверждённого источника героев пока нет. Хардкод НЕ подставляется." )
	end

	return self.cache
end

----------------------------------------------------------------------------
-- Публичный интерфейс (не менялся)
----------------------------------------------------------------------------

function HeroPool:GetAllHeroes()
	return self:Build()
end

function HeroPool:Contains( heroName )
	if heroName == nil then
		return false
	end

	for _, hero in ipairs( self:GetAllHeroes() ) do
		if hero.name == heroName then
			return true
		end
	end

	return false
end

function HeroPool:GetHeroAttribute( heroName )
	for _, hero in ipairs( self:GetAllHeroes() ) do
		if hero.name == heroName then
			return hero.attribute
		end
	end

	return nil
end

function HeroPool:GetHeroesByAttribute( attribute )
	local result = {}

	for _, hero in ipairs( self:GetAllHeroes() ) do
		if hero.attribute ~= nil and hero.attribute == attribute then
			result[ #result + 1 ] = hero
		end
	end

	return result
end

function HeroPool:GetRandomHero( exclude )
	local pool = {}

	for _, hero in ipairs( self:GetAllHeroes() ) do
		pool[ #pool + 1 ] = hero.name
	end

	if #pool == 0 then
		return nil
	end

	local picked = HCTRandom:PickUnique( pool, 1, exclude )
	return picked[ 1 ]
end

--[[
	Предложение для Draft Clash по правилу 4 + 1 (ТЗ §24, §25):
		count случайных уникальных героев атрибута attribute,
		плюс extraCount случайных героев из общего пула,
		не совпадающих с уже выбранными.
]]
function HeroPool:GetDraftOptions( attribute, count, extraCount )
	count = count or HCT_DRAFT_MAIN_COUNT
	extraCount = extraCount or HCT_DRAFT_EXTRA_COUNT

	local byAttribute = {}
	for _, hero in ipairs( self:GetHeroesByAttribute( attribute ) ) do
		byAttribute[ #byAttribute + 1 ] = hero.name
	end

	local options = HCTRandom:PickUnique( byAttribute, count )
	local exclude = {}

	for _, name in ipairs( options ) do
		exclude[ #exclude + 1 ] = name
	end

	if extraCount > 0 then
		local allNames = {}
		for _, hero in ipairs( self:GetAllHeroes() ) do
			allNames[ #allNames + 1 ] = hero.name
		end

		local extra = HCTRandom:PickUnique( allNames, extraCount, exclude )
		for _, name in ipairs( extra ) do
			options[ #options + 1 ] = name
			exclude[ #exclude + 1 ] = name
		end
	end

	return options
end

function HeroPool:LogSummary()
	local all = self:GetAllHeroes()

	HCTDebug:LogParts( "HeroPool: всего", #all, "героев | источник", self.source )
	HCTDebug:LogParts( "  strength     =", #self:GetHeroesByAttribute( HCT_ATTRIBUTE.STRENGTH ) )
	HCTDebug:LogParts( "  agility      =", #self:GetHeroesByAttribute( HCT_ATTRIBUTE.AGILITY ) )
	HCTDebug:LogParts( "  intelligence =", #self:GetHeroesByAttribute( HCT_ATTRIBUTE.INTELLIGENCE ) )
	HCTDebug:LogParts( "  universal    =", #self:GetHeroesByAttribute( HCT_ATTRIBUTE.UNIVERSAL ) )

	-- Проверка покрытия атрибутов: сколько героев остались без атрибута.
	local missing = 0
	for _, hero in ipairs( all ) do
		if hero.attribute == nil then
			missing = missing + 1
		end
	end
	HCTDebug:LogParts( "  без атрибута =", missing )
	if missing > 0 then
		HCTDebug:Warn( "Не у всех героев определён primary attribute: проверь draft/hero_attributes.lua" )
	end
end