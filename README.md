# HERO CLASH TURBO (Dota 2 custom game)

Кастомный режим Dota 2: обе команды голосуют за одного общего героя — все 5 игроков получают победившего героя (Radiant = 5x Pudge, Dire = 5x Juggernaut).

## Структура

Репозиторий содержит проект **в двух видах**:

- `addoninfo.txt`, `scripts/` — распакованная версия для чтения кода на GitHub, диффов и review;
- `HERO_CLASH_TURBO.zip` — полная версия для Workshop Tools (включая бинарные `tools_*` файлы).

> Правки Lua-кода делаются в `scripts/vscripts/...`, затем изменения переносятся в `HERO_CLASH_TURBO.zip` (именно zip используется при сборке аддона).

## Код (Lua, Source 2)

```
scripts/vscripts/
├── addon_game_mode.lua        # точка входа, require всех модулей
├── core/
│   ├── game_mode.lua          # игровой цикл и состояния (OPTIONS->VOTE->WINNER->...)
│   ├── game_state.lua         # глобальное состояние: mode/state/teamHeroes/draft
│   ├── hero_manager.lua       # SetTeamHero/GetTeamHero, ReplaceHeroWith
│   ├── team_manager.lua       # игроки команд, player IDs
│   └── random_clash.lua       # старый random-режим (не трогать)
├── draft/
│   ├── draft_manager.lua      # драфт: options, ReceiveVote, победитель, тестовые голоса
│   ├── hero_pool.lua          # пул героев + генерация 4+1 options
│   ├── hero_attributes.lua    # статический mapping 127 героев -> primary attribute
│   └── hero_names.lua         # основной roster source (127 героев)
├── modes/
│   ├── draft_clash.lua        # MVP DRAFT_CLASH
│   └── random_clash.lua
└── utils/                     # random.lua, debug.lua
```

## Текущее состояние

- [x] Draft/Vote MVP (server-side валидация, подсчёт голосов, tie-break)
- [x] teamHeroes, переходы DRAFT -> HERO_ASSIGNMENT -> PRE_GAME
- [x] ReplaceHeroWith: 10/10 replacement проверен
- [x] Источник атрибутов: `draft/hero_attributes.lua` (offline-проверен; Dota runtime-тест — в процессе)
- [ ] Panorama vote UI, таймер драфта, disconnect handling, полный match flow
