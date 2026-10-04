--[[
	utils/random.lua
	Вспомогательные функции для случайного выбора.
	Используются HeroPool, RandomClash и DraftManager.
	Вся случайность идёт только через этот модуль.
]]

if HCTRandom == nil then
	HCTRandom = {}
end

-- Случайный элемент массива. nil, если массив пуст или nil.
function HCTRandom:PickFromArray( array )
	if array == nil or #array == 0 then
		return nil
	end
	return array[ math.random( 1, #array ) ]
end

-- Копия массива, перемешанная по алгоритму Фишера-Йетса.
-- Исходный массив не меняется.
function HCTRandom:ShuffledCopy( array )
	local result = {}
	if array == nil then
		return result
	end

	for i = 1, #array do
		result[ i ] = array[ i ]
	end

	for i = #result, 2, -1 do
		local j = math.random( 1, i )
		result[ i ], result[ j ] = result[ j ], result[ i ]
	end

	return result
end

--[[
	count уникальных элементов из array.
	exclude (необязательно) -- массив значений, которые нельзя брать.
	Возвращает массив длиной min(count, доступных уникальных элементов).
]]
function HCTRandom:PickUnique( array, count, exclude )
	local pool = {}

	for _, value in ipairs( array or {} ) do
		local blocked = false

		if exclude ~= nil then
			for _, excluded in ipairs( exclude ) do
				if excluded == value then
					blocked = true
					break
				end
			end
		end

		if not blocked then
			pool[ #pool + 1 ] = value
		end
	end

	local shuffled = self:ShuffledCopy( pool )
	local result = {}

	for i = 1, math.min( count, #shuffled ) do
		result[ i ] = shuffled[ i ]
	end

	return result
end