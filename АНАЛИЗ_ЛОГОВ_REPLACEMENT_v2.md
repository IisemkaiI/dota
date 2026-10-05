# АНАЛИЗ: логи.txt (актуальная версия с GitHub, 1543 строки) — после фикса атрибутов

Дата: 05.10.2026. Источник: origin/main:логи.txt + код на main. Dota НЕ запускалась — только лог и код.

---

## ДИАГНОЗ (одна строка)

ReplaceHeroWith работает 10/10; ошибки RESOURCE_TYPE_MODEL/nonresident — проблема загрузки
ассетов движком (в т.ч. для базовых sven.vmdl/axe.vmdl), а не отказ замены; механику менять не нужно.

---

## 1. Все model/resource/nonresident ошибки в логе

### 1.1 Базовые модели героев (WARNING "not in the system / Missing from a manifest?")
| Строка | Ресурс | Кому |
|---|---|---|
| 742 | models/heroes/sven/sven.vmdl (F686C3D3999D4C78) | Radiant (sven) |
| 749, 756, 763, 770 | ERROR: sven.vmdl "is not loaded and may have been deleted" | игроки 1-4 |
| 782 | models/heroes/axe/axe.vmdl (8862AFECE0D9D7F4) | Dire (axe) |
| 789, 796, 803, 810 | ERROR: axe.vmdl "is not loaded and may have been deleted" | игроки 6-9 |

### 1.2 Asserts network serializer (последствие незагруженных моделей)
- 839-840: Assertion Failed networkserializer.cpp(1294) Serialize(): **Serialized nonresident asset models/heroes/sven/sven.vmdl** (+ minidump);
- 842-843: Assertion Failed networkserializer.cpp(1320) Unserialize(): **Unserialized nonresident asset models/heroes/axe/axe.vmdl status [1]** (+ minidump).

### 1.3 Nonresident-модели косметики слотов героев (строки 845+)
- sven_sword.vmdl (Def 17 #DOTA_Item_Svens_Sword), sven_mask.vmdl (Def 16 #DOTA_Item_Svens_Mask) и др.;
- аналогичные попытки привязки для axe; owner 0 — дефолтные слоты предметов героя;
- всего строк со «nonresident»: 102 (в прошлом прогоне с Muerta/Slardar было 46).

### 1.4 Прочее (не относится к heroes)
- 64: steamnetworkingsockets assert m_hSteamPipe == 0 — сетевой слой;
- хвост лога: shader warnings bristleback/dark_carnival — фон.

---

## 2. Причина или следствие? — СЛЕДСТВИЕ, замена не сломана

Доказательства из лога:
1. Каждая model-ошибка идёт парой к УСПЕШНОЙ строке SetSelectedHero того же игрока
   (пример: 742 WARNING sven -> 740 PR:SetSelectedHero 0 ... npc_dota_hero_sven(18) -> 743 HCT игрок 0 -> sven);
2. Итоги HeroManager (тройная проверка ok+table+GetSelectedHeroName):
   - 772: `итог: Radiant | герой = npc_dota_hero_sven | применено = 5 | отказов = 0`;
   - 812: `итог: Dire | герой = npc_dota_hero_axe | применено = 5 | отказов = 0`;
3. В логе НОЛЬ «ОТКАЗ» и ноль «получил ... вместо» (grep подтверждён);
4. После assert'ов матч живёт: GAME_IN_PROGRESS достигнут (733-734), лог продолжается до конца без краха.

КЛЮЧЕВОЕ: теперь ошибки появляются даже для sven/axe — самых базовых героев Dota. Значит дело
НЕ в специфике Muerta/Slardar/DLC-контента, а в системной загрузке ресурсов при ReplaceHeroWith
в этом окружении (custom game, локальное тестирование). Это engine/resource issue (пункт 14 плана).

---

## 3. Фактический результат ReplaceHeroWith — все 10 игроков

После драфта победители: Radiant = npc_dota_hero_sven (2 голоса), Dire = npc_dota_hero_axe (2 голоса).

| playerID | команда | после замены (PR:SetSelectedHero + GetSelectedHeroName==teamHero) | строки |
|---|---|---|---|
| 0 | Radiant | npc_dota_hero_sven (heroID 18) | 739-740, HCT 743 |
| 1 | Radiant | npc_dota_hero_sven | 744-745, HCT 750 |
| 2 | Radiant | npc_dota_hero_sven | 751-752, HCT 757 |
| 3 | Radiant | npc_dota_hero_sven | 758-759, HCT 764 |
| 4 | Radiant | npc_dota_hero_sven | 765-766, HCT 771 |
| 5 | Dire | npc_dota_hero_axe (heroID 2) | 777-778, HCT 781 |
| 6 | Dire | npc_dota_hero_axe | 784-785, HCT 788 |
| 7 | Dire | npc_dota_hero_axe | 791-792, HCT 795 |
| 8 | Dire | npc_dota_hero_axe | 798-799, HCT 802 |
| 9 | Dire | npc_dota_hero_axe | 805-806, HCT 809 |

Строки «до» (стартовые герои до BotPopulate, PR:SetSelectedHero до замены) в актуальном логе
не содержат явных имён «до->после» для этих ID в секции замены; факт успеха фиксируется
условием applied == teamHero внутри AssignHeroToPlayer (иначе была бы строка ОТКАЗ — их нет).

**ИТОГ: 10/10 успешно, 0 отказов.**

Бонус по драфту (задача №1 ПОДТВЕРЖДЕНА этим же логом):
- 319-323: strength=39, agility=42, intelligence=36, universal=10, без атрибута=0;
- 474/483: предложений = 5 для обеих команд, warning «получено 1 из 5» отсутствует;
- голоса распределены между разными вариантами (sven 2, earthshaker 1, primal_beast 1, leshrak 1) — реальный подсчёт работает.

---

## 4. Текущая реализация HeroManager (код, main)

AssignHeroToPlayer:
- источник истины GameState.teamHeroes; сверка heroName;
- pcall(PlayerResource:ReplaceHeroWith(playerID, teamHero, 0, 0));
- успех = ok AND type(result)=="table" AND GetSelectedHeroName(playerID)==teamHero;
- вызов только на GAME_IN_PROGRESS (раньше движок отказывает — проверено ранее).

SpawnTeamHeroes: обход GetTeamPlayers, счётчик applied, итоговая строка, возврат assigned==#players.

ВЫВОД: реализация корректна, полностью согласуется с логом. Код НЕ изменялся (пункты 5-6 ТЗ).

---

## 5. Минимальное решение проблемы моделей (без касания replacement)

Проблема лежит в слое загрузки ассетов движка, поэтому:
1. Проверить целостность файлов Dota 2 (Steam -> Verify integrity) — исключить повреждение VPK.
2. Проверить, видны ли юниты в игре фактически (невидимые модели = мешает; если видимы —
   это просто шум в консоли, можно оставить как есть до полировки).
3. Если мешает — единственный минимальный аддон-уровневый шаг: предзагрузка перед заменой,
   PrecacheUnitByNameAsync(heroName, callback, teamNumber) на PRE_GAME для обоих teamHeroes,
   затем SpawnTeamHeroes в колбэке. ReplaceHeroWith НЕ трогаем.
4. Assert'ы CNetSerializerStrongHandle на nonresident asset — известное поведение Source2
   (пишется minidump, матч не падает). Не блокер для дальнейшего контента.

---

## 6. Что реально сломано / что НЕ сломано

НЕ СЛОМАНО:
- атрибут-источник (задача №1 закрыта рантайм-подтверждением: 39/42/36/10, options 5);
- Draft/Vote/подсчёт/tie-break, teamHeroes, переходы состояний до GAME_IN_PROGRESS;
- ReplaceHeroWith: 10/10, отказов 0.

НЕ СЛОМАНО В ЛОГИКЕ, НО ШУМИТ:
- загрузка моделей (RESOURCE_TYPE_MODEL/nonresident asserts) — engine resource issue,
  воспроизводится даже на sven/axe.

СЛЕДУЮЩИЙ МИНИМАЛЬНЫЙ ШАГ:
Закрыть задачу №1 официально (критерии выполнены в этом логе) и перейти к приоритету 7 —
Panorama vote UI + client->server события голосования. Модельные asserts оставить в треке
полировки/окружения, не трогая replacement.
