--[[
	draft/hero_attributes.lua
	Статический mapping: npc_dota_hero_* -> primary attribute.

	ЗАЧЕМ: в Dota runtime LoadKeyValues("scripts/npc/npc_heroes.txt")
	не заполнил категории в VScript (см. план, раздел 5). HeroList как
	источник не используется (план, раздел 13). Поэтому атрибуты
	хранятся здесь, как проектный источник данных.

	Источник данных: AttributePrimary из npc_heroes.txt (VPK Dota 2),
	проверен offline; все 127 героев hero_names.lua покрыты.

	Маппинг значений DOTA_ATTRIBUTE_* на строковые ключи HeroPool:
		DOTA_ATTRIBUTE_STRENGTH     -> "strength"
		DOTA_ATTRIBUTE_AGILITY      -> "agility"
		DOTA_ATTRIBUTE_INTELLECT    -> "intelligence"
		DOTA_ATTRIBUTE_UNIVERSAL    -> "universal"

	Формат: плоская hash-таблица { [unit name] = attribute string }.
]]

if HeroAttributes == nil then
	HeroAttributes = {}
end

HeroAttributes.MAP = {
	["npc_dota_hero_abaddon"] = "strength",
	["npc_dota_hero_abyssal_underlord"] = "universal",
	["npc_dota_hero_alchemist"] = "strength",
	["npc_dota_hero_ancient_apparition"] = "intelligence",
	["npc_dota_hero_antimage"] = "agility",
	["npc_dota_hero_arc_warden"] = "agility",
	["npc_dota_hero_axe"] = "strength",
	["npc_dota_hero_bane"] = "universal",
	["npc_dota_hero_batrider"] = "intelligence",
	["npc_dota_hero_beastmaster"] = "strength",
	["npc_dota_hero_bird_samurai"] = "agility",
	["npc_dota_hero_bloodseeker"] = "agility",
	["npc_dota_hero_bounty_hunter"] = "agility",
	["npc_dota_hero_brewmaster"] = "strength",
	["npc_dota_hero_bristleback"] = "strength",
	["npc_dota_hero_broodmother"] = "agility",
	["npc_dota_hero_centaur"] = "strength",
	["npc_dota_hero_chaos_knight"] = "strength",
	["npc_dota_hero_chen"] = "universal",
	["npc_dota_hero_clinkz"] = "agility",
	["npc_dota_hero_crystal_maiden"] = "intelligence",
	["npc_dota_hero_dark_seer"] = "intelligence",
	["npc_dota_hero_dark_willow"] = "agility",
	["npc_dota_hero_dawnbreaker"] = "strength",
	["npc_dota_hero_dazzle"] = "intelligence",
	["npc_dota_hero_death_prophet"] = "intelligence",
	["npc_dota_hero_disruptor"] = "intelligence",
	["npc_dota_hero_doom_bringer"] = "strength",
	["npc_dota_hero_dragon_knight"] = "strength",
	["npc_dota_hero_drow_ranger"] = "agility",
	["npc_dota_hero_earth_spirit"] = "strength",
	["npc_dota_hero_earthshaker"] = "strength",
	["npc_dota_hero_elder_titan"] = "strength",
	["npc_dota_hero_ember_spirit"] = "agility",
	["npc_dota_hero_enchantress"] = "intelligence",
	["npc_dota_hero_enigma"] = "intelligence",
	["npc_dota_hero_faceless_void"] = "agility",
	["npc_dota_hero_furion"] = "intelligence",
	["npc_dota_hero_grimstroke"] = "intelligence",
	["npc_dota_hero_gyrocopter"] = "agility",
	["npc_dota_hero_hoodwink"] = "agility",
	["npc_dota_hero_huskar"] = "strength",
	["npc_dota_hero_invoker"] = "universal",
	["npc_dota_hero_jakiro"] = "intelligence",
	["npc_dota_hero_juggernaut"] = "agility",
	["npc_dota_hero_keeper_of_the_light"] = "intelligence",
	["npc_dota_hero_kunkka"] = "strength",
	["npc_dota_hero_largo"] = "agility",
	["npc_dota_hero_legion_commander"] = "strength",
	["npc_dota_hero_leshrac"] = "intelligence",
	["npc_dota_hero_lich"] = "intelligence",
	["npc_dota_hero_life_stealer"] = "strength",
	["npc_dota_hero_lina"] = "intelligence",
	["npc_dota_hero_lion"] = "intelligence",
	["npc_dota_hero_lone_druid"] = "agility",
	["npc_dota_hero_luna"] = "agility",
	["npc_dota_hero_lycan"] = "strength",
	["npc_dota_hero_magnataur"] = "strength",
	["npc_dota_hero_marci"] = "universal",
	["npc_dota_hero_mars"] = "strength",
	["npc_dota_hero_medusa"] = "agility",
	["npc_dota_hero_meepo"] = "agility",
	["npc_dota_hero_mirana"] = "universal",
	["npc_dota_hero_monkey_king"] = "agility",
	["npc_dota_hero_morphling"] = "agility",
	["npc_dota_hero_muerta"] = "intelligence",
	["npc_dota_hero_naga_siren"] = "agility",
	["npc_dota_hero_necrolyte"] = "intelligence",
	["npc_dota_hero_nevermore"] = "agility",
	["npc_dota_hero_night_stalker"] = "strength",
	["npc_dota_hero_nyx_assassin"] = "agility",
	["npc_dota_hero_obsidian_destroyer"] = "intelligence",
	["npc_dota_hero_ogre_magi"] = "strength",
	["npc_dota_hero_omniknight"] = "strength",
	["npc_dota_hero_oracle"] = "intelligence",
	["npc_dota_hero_pangolier"] = "agility",
	["npc_dota_hero_phantom_assassin"] = "agility",
	["npc_dota_hero_phantom_lancer"] = "agility",
	["npc_dota_hero_phoenix"] = "strength",
	["npc_dota_hero_primal_beast"] = "strength",
	["npc_dota_hero_puck"] = "intelligence",
	["npc_dota_hero_pudge"] = "strength",
	["npc_dota_hero_pugna"] = "intelligence",
	["npc_dota_hero_queenofpain"] = "intelligence",
	["npc_dota_hero_rattletrap"] = "strength",
	["npc_dota_hero_razor"] = "agility",
	["npc_dota_hero_riki"] = "agility",
	["npc_dota_hero_ringmaster"] = "agility",
	["npc_dota_hero_rubick"] = "intelligence",
	["npc_dota_hero_sand_king"] = "strength",
	["npc_dota_hero_shadow_demon"] = "intelligence",
	["npc_dota_hero_shadow_shaman"] = "intelligence",
	["npc_dota_hero_shredder"] = "agility",
	["npc_dota_hero_silencer"] = "intelligence",
	["npc_dota_hero_skeleton_king"] = "strength",
	["npc_dota_hero_skywrath_mage"] = "intelligence",
	["npc_dota_hero_slardar"] = "strength",
	["npc_dota_hero_slark"] = "agility",
	["npc_dota_hero_snapfire"] = "universal",
	["npc_dota_hero_sniper"] = "agility",
	["npc_dota_hero_spectre"] = "agility",
	["npc_dota_hero_spirit_breaker"] = "strength",
	["npc_dota_hero_storm_spirit"] = "intelligence",
	["npc_dota_hero_sven"] = "strength",
	["npc_dota_hero_techies"] = "intelligence",
	["npc_dota_hero_templar_assassin"] = "agility",
	["npc_dota_hero_terrorblade"] = "agility",
	["npc_dota_hero_tidehunter"] = "strength",
	["npc_dota_hero_tinker"] = "intelligence",
	["npc_dota_hero_tiny"] = "strength",
	["npc_dota_hero_treant"] = "strength",
	["npc_dota_hero_troll_warlord"] = "agility",
	["npc_dota_hero_tusk"] = "strength",
	["npc_dota_hero_undying"] = "strength",
	["npc_dota_hero_ursa"] = "agility",
	["npc_dota_hero_vengefulspirit"] = "universal",
	["npc_dota_hero_venomancer"] = "agility",
	["npc_dota_hero_viper"] = "agility",
	["npc_dota_hero_visage"] = "universal",
	["npc_dota_hero_void_spirit"] = "agility",
	["npc_dota_hero_warlock"] = "intelligence",
	["npc_dota_hero_weaver"] = "agility",
	["npc_dota_hero_windrunner"] = "intelligence",
	["npc_dota_hero_winter_wyvern"] = "universal",
	["npc_dota_hero_wisp"] = "strength",
	["npc_dota_hero_witch_doctor"] = "intelligence",
	["npc_dota_hero_zuus"] = "intelligence",
}

-- Количество записей (для самопроверок и логов).
function HeroAttributes.Count()
	local count = 0
	for _ in pairs( HeroAttributes.MAP ) do
		count = count + 1
	end
	return count
end

-- Получить атрибут по имени героя; nil, если героя нет в mapping.
function HeroAttributes.Get( heroName )
	return HeroAttributes.MAP[ heroName ]
end
