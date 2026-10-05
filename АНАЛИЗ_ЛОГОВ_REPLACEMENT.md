# АНАЛИЗ: логи.txt (Dota runtime) — ReplaceHeroWith и model/resource asserts

Дата анализа: 05.10.2026. Источник: логи.txt из репозитория (1224 строки) + код на main.
Важно: анализ только по предоставленному логу и коду. Dota НЕ запускалась.

---

## ГЛАВНЫЙ ВЫВОД (читать первым)

**Этот лог — НЕ тест после фикса атрибутов.** В нём HeroPool снова пуст по категориям
(strength/agility/intelligence/universal = 0, строки 319-322), хотя в коде на GitHub
(коммит 458e040) уже есть применение HeroAttributes.MAP к любому источнику.
Причина: локальная копия аддона не обновлена — фикс в репозитории есть, в рантайме его нет.
Нужно синхронизировать файлы и повторить тест.

**ReplaceHeroWith НЕ сломан.** Код в логе подтверждает успех для ВСЕХ 10 игроков
(см. раздел «Фактический результат замены»). Механику менять НЕЛЬЗЯ (пункты 5-6 ТЗ).

**Model/resource ошибки — отдельная проблема загрузки ассетов**, а не отказ замены.
(пункт 14 плана: не трогать replacement из-за этих сообщений).

---

## 1. Все model/resource/nonresident ошибки в логе

### 1.1 Base-модели героев (не найдены системой)
| Строка | Тип | Ресурс |
|---|---|---|
| 732 | WARNING RESOURCE_TYPE_MODEL | models/heroes/muerta/muerta_base.vmdl (2725AE615C278D00) "requested but is not in the system. (Missing from a manifest?)" |
| 739, 746, 753, 760 | ERROR RESOURCE_TYPE_MODEL | muerta_base.vmdl "is not loaded and may have been deleted" (по одной на каждого игрока Radiant 0-4) |
| 772 | WARNING RESOURCE_TYPE_MODEL | models/heroes/slardar/slardar.vmdl (15178CE255C0C1AF) "not in the system" |
| 779, 786, 793, 800 | ERROR RESOURCE_TYPE_MODEL | slardar.vmdl "not loaded and may have been deleted" (игроки Dire 5-9) |

### 1.2 Asserts network serializer (последствие 1.1)
| Строка | Содержание |
|---|---|
| 829-831 | Assertion Failed networkserializer.cpp(1294) CNetSerializerStrongHandle::Serialize(): **Serialized nonresident asset models/heroes/muerta/muerta_base.vmdl** + "Calling Steam to write a minidump for the assert" |
| 833-834 | Assertion Failed networkserializer.cpp(1320) Unserialize(): **Unserialized nonresident asset ... status [1]** + minidump |

Assert'ы относятся ТОЛЬКО к muerta_base.vmdl. Для slardar assert'ов нет.

### 1.3 Nonresident модели косметики Muerta (строки 835+)
- 'models/items/muerta/the_netherbutterfly_{head,back,armor,weapon}.vmdl' — item Def 30966-30969
  (#DOTA_Item_Mariposa_Mori__*), owner 1253347831 (хост-игрок, у него куплена косметика) — по 2 упоминания;
- 'models/heroes/muerta/muerta_{head,back,armor,weapons}.vmdl' — item Def 804/807/808/809
  (#DOTA_Item_Muertas_*), owner 0 — по 9 упоминаний (повторяющиеся попытки привязать модель к сущностям);
- всего «nonresident» в логе: 46 строк, почти все про Muerta.

### 1.4 Прочее (не относится к задаче)
- 731: SetParticleControlEnt: unable to lookup attachment "attach_hitloc" on model "" — следствие незагруженной модели;
- 65: steam networking assert (m_hSteamPipe == 0) — сетевой слой, к героям отношения не имеет;
- конец лога: shader warnings bristleback/dark_carnival — фон.

---

## 2. Причина или следствие?

**Следствие, а не причина сбоя замены.** Доказательства из лога:

1. Порядок событий: PR:SetSelectedHero (успешная смена героя) происходит ДО/ВОКРУГ каждой
   model-ошибки; ни одна ошибка не прервала цикл замены.
2. Итоговые строки HeroManager (проверка type(result)=="table" + GetSelectedHeroName):
   - 762: `итог: Radiant | герой = npc_dota_hero_muerta | применено = 5 | отказов = 0`
   - 802: `итог: Dire | герой = npc_dota_hero_slardar | применено = 5 | отказов = 0`
   - 805: `Radiant: true | Dire: true`
3. В логе НОЛЬ строк «ОТКАЗ» / «получил ... вместо ...» (единственные признаки отказа в AssignHeroToPlayer).
4. После asserts игра продолжила работать: строки 806-828 — отчёты HeroListTiming state=10,
   лог кончается обычными shader-предупреждениями, краха нет.

Минидампы Steam пишутся на assert, но это диагностика движка, не вылет матча.

---

## 3. Фактический результат ReplaceHeroWith — ВСЕ 10 игроков

До замены (стартовые герои, строки 418-450 PR:SetSelectedHero):

| playerID | команда | до | после | GetSelectedHeroName-подтверждение в логе |
|---|---|---|---|---|
| 0 | Radiant | storm_spirit (17) | muerta (138) | PR:SetSelectedHero 0 (null)(0) -> muerta(138), строки 729-730; HCT 733 |
| 1 | Radiant | warlock (37) | muerta (138) | 734-735; HCT 740 |
| 2 | Radiant | dragon_knight (49) | muerta (138) | 741-742; HCT 747 |
| 3 | Radiant | witch_doctor (30) | muerta (138) | 748-749; HCT 754 |
| 4 | Radiant | luna (48) | muerta (138) | 755-756; HCT 761 |
| 5 | Dire | jakiro (64) | slardar (28) | 767-768; HCT 773 |
| 6 | Dire | tidehunter (29) | slardar (28) | 774-775; HCT 780 |
| 7 | Dire | oracle (111) | slardar (28) | 781-782; HCT 787 |
| 8 | Dire | phantom_assassin (44) | slardar (28) | 788-789; HCT 794 |
| 9 | Dire | razor (15) | slardar (28) | 795-796; HCT 801 |

**Успешных замен: 10/10. Отказов: 0.**

Примечание про GetSelectedHeroName: сам метод возвращает имя внутри AssignHeroToPlayer и
используется как условие успеха (applied ~= teamHero => ОТКАЗ). Явных строк «в слоте: ...» в
логе нет, потому что они печатаются только при отказе. Косвенное подтверждение — парные
движковые строки `PR:SetSelectedHero N ... npc_dota_hero_muerta(138)/slardar(28)` точно для
10/10 игроков.

---

## 4. Проверка текущей реализации HeroManager (код на main)

AssignHeroToPlayer (core/hero_manager.lua):
- берёт teamHero из GameState.teamHeroes (источник истины), сверяет с переданным heroName;
- pcall(PlayerResource:ReplaceHeroWith(playerID, teamHero, 0, 0));
- успех = ok AND type(result)=="table" AND GetSelectedHeroName(playerID)==teamHero — тройная
  проверка, соответствующая пункту 7 плана;
- вызывается на GAME_IN_PROGRESS (правильно: раньше движок отказывает, см. комментарий в файле).

SpawnTeamHeroes: обходит TeamManager:GetTeamPlayers(team), считает applied, логирует итог,
возвращает assigned==#players. Реализация корректна и полностью согласуется с логом.

ВЫВОД: доказательств того, что ReplaceHeroWith сломан, НЕТ. По пунктам 5-6 ТЗ код НЕ изменён
(в этом цикле я ничего не коммитил в vscripts).

---

## 5. Минимальное решение для model/resource проблемы (если она мешает)

Проблема: модели muerta_base.vmdl / slardar.vmdl «requested but is not in the system
(Missing from a manifest?)» — ресурсы не резидентны на момент сериализации. Это типично для
custom games без подписанных предзагрузок: движок просит модель раньше, чем VPK-поток её
загрузил, либо клиент хоста не докачал часть DLC-контента (Mariposa Mori set у хоста).

Порядок действий (от дешёвого к дорогому), ничего в vscripts менять не нужно:
1. **Перезапуск/целостность**: проверить целостность файлов Dota 2 (Steam -> Properties ->
   Installed Files -> Verify). Убедиться, что контент Muerta доступен аккаунту хоста.
2. **Проверить воспроизводимость на других героях**: заменить дефолтный draft-результат на
   классических героев (axe/juggernaut). Если ошибок нет — проблема в конкретном контенте
   Muerta/Slardar на этом клиенте, а не в аддоне.
3. **Если ошибки остаются и мешают визуально** (невидимые юниты) — единственный допустимый
   минимальный тик в коде: предзагрузка моделей через PrecacheUnitByNameAsync("npc_dota_hero_muerta",
   callback, teamNumber) ДО вызова ReplaceHeroWith (например, на HERO_SELECTION/PRE_GAME).
   Сам ReplaceHeroWith при этом НЕ трогаем.
4. Assert'ы networkserializer на nonresident asset — известное поведение движка (minidump
   пишется, матч живёт). Пока замена 10/10 и юниты на карте — не является блокером.

---

## 6. Что реально сломано / что НЕ сломано

НЕ СЛОМАНО (подтверждено логом):
- Draft/Vote flow целиком (обе команды 5/5 голосов, победители, tie-break path не требовался);
- teamHeroes/winner assignment (Radiant=muerta, Dire=slardar);
- переходы DRAFT_SETUP -> HERO_ASSIGNMENT -> PRE_GAME -> GAME_IN_PROGRESS;
- ReplaceHeroWith: 10/10, отказов 0;
- стабильность матча после asserts.

СЛОМАНО / НЕ ПОДТВЕРЖДЕНО:
- источник атрибутов в ЭТОМ запуске: категории пула = 0, options = 1 из 5 (WARNING 462/468).
  Но фикс 458e040 существует в git и в этот запуск НЕ попал (в логе старое поведение слоя 3).
  Значит задача №1 по-прежнему ЖДЁТ ПОВТОРНОГО ТЕСТИГА с обновлёнными файлами.
- загрузка моделей Muerta/Slardar на этом клиенте (engine resource issue, вне логики аддона).

## 7. Минимальный следующий шаг

1. Обновить локальную копию аддона из GitHub (git pull --ff-only; ключевой файл
   scripts/vscripts/draft/hero_pool.lua из коммита 458e040) — сверить, что в Build() есть
   блок применения HeroAttributes.MAP.
2. Перезапустить тот же DRAFT test.
3. В новом логе проверить 3 критерия:
   a) `[HCT] strength = 39 | agility = 42 | intelligence = 36 | universal = 10` и «без атрибута = 0»;
   b) `предложений = 5` для обеих команд (нет WARNING «получено 1 из 5»);
   c) replacement по-прежнему 10/10.
4. Model-asserts в новом прогоне просто отметить как присутствующие/отсутствующие — они не
   влияют на вердикт по механике.
