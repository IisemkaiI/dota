--[[
	utils/debug.lua
	Единая точка для всех консольных сообщений.

	Весь вывод идёт с префиксом [HCT], чтобы его было легко найти в консоли игры
	и в логе. Глобал назван HCTDebug, чтобы гарантированно не пересечься
	с глобалами движка (Debug).
]]

HCT_LOG_PREFIX = "[HCT] "

if HCTDebug == nil then
	HCTDebug = {}
end

-- Простой однострочный лог
function HCTDebug:Log( message )
	print( HCT_LOG_PREFIX .. tostring( message ) )
end

-- Лог из нескольких аргументов, склеенных пробелом.
-- Использование: HCTDebug:LogParts( "player", playerID, "team", team )
function HCTDebug:LogParts( ... )
	local parts = {}
	local count = select( "#", ... )
	for i = 1, count do
		parts[ i ] = tostring( ( select( i, ... ) ) )
	end
	print( HCT_LOG_PREFIX .. table.concat( parts, " " ) )
end

-- Лог сразу с уровнем WARNING, из нескольких аргументов
function HCTDebug:WarnParts( ... )
	self:Warn( self:Join( ... ) )
end

-- Лог сразу с уровнем ERROR, из нескольких аргументов
function HCTDebug:ErrorParts( ... )
	self:Error( self:Join( ... ) )
end

-- Склейка аргументов в строку через пробел
function HCTDebug:Join( ... )
	local parts = {}
	local count = select( "#", ... )
	for i = 1, count do
		parts[ i ] = tostring( ( select( i, ... ) ) )
	end
	return table.concat( parts, " " )
end

-- Разделитель для читаемого лога
function HCTDebug:Header( title )
	print( "" )
	print( HCT_LOG_PREFIX .. "=== " .. tostring( title ) .. " ===" )
end

--[[
	Раскрытый дамп таблицы. depth ограничивает вложенность,
	чтобы случайно не напечатать весь GameState целиком.
]]
function HCTDebug:LogTable( title, tbl, depth )
	depth = depth or 1
	self:Log( tostring( title ) )

	if type( tbl ) ~= "table" then
		self:Log( "  (не таблица: " .. type( tbl ) .. " = " .. tostring( tbl ) .. ")" )
		return
	end

	local keys = {}
	for key in pairs( tbl ) do
		keys[ #keys + 1 ] = key
	end
	table.sort( keys, function( a, b ) return tostring( a ) < tostring( b ) end )

	for _, key in ipairs( keys ) do
		local value = tbl[ key ]
		if type( value ) == "table" and depth > 0 then
			self:Log( "  " .. tostring( key ) .. ":" )
			self:LogTable( "", value, depth - 1 )
		elseif type( value ) == "table" then
			self:Log( "  " .. tostring( key ) .. ": { ... }" )
		else
			self:Log( "  " .. tostring( key ) .. " = " .. tostring( value ) )
		end
	end
end

function HCTDebug:Warn( message )
	self:Log( "WARNING: " .. tostring( message ) )
end

function HCTDebug:Error( message )
	self:Log( "ERROR: " .. tostring( message ) )
end