// HERO CLASH TURBO — панель драфта (минимальный слой).
//
// Задача этого файла: читать CustomNetTables "hct_draft" и показывать
// 5 предложений команды + состояние (open/finished/pick/счётчики голосов).
// Голосование кнопками подключается на следующем этапе — здесь только
// отображение, никаких send-event'ов.
//
// Схема записи net-таблицы (публикует сервер, core/net_tables.lua):
//   options: string[], open: 0|1, finished: 0|1, pick: string,
//   votes1..votes5: number, voterCount: number, teamSize: number

const NETTABLE_NAME = 'hct_draft';

// npc_dota_hero_axe -> "Axe". Для отладочного UI имени ключа достаточно;
// локализацию через Localize сознательно не используем — минимум кода.
function heroDisplayName(heroKey) {
    if (!heroKey) return '';
    const parts = heroKey.replace('npc_dota_hero_', '').split('_');
    return parts.map(p => p.charAt(0).toUpperCase() + p.slice(1)).join(' ');
}

function myTeamKey() {
    const me = Players.GetLocalPlayer();
    if (me === undefined || me < 0) return null;
    const team = Players.GetTeam(me);
    // DOTA_TEAM_GOODGUYS = 2, DOTA_TEAM_BADGUYS = 3
    if (team === DOTA_TEAM_GOODGUYS) return 'radiant';
    if (team === DOTA_TEAM_BADGUYS) return 'dire';
    return null;
}

function getRecord(key) {
    return CustomNetTables.GetTableValue(NETTABLE_NAME, key);
}

function renderOptions(panel, record) {
    panel.RemoveAndDeleteChildren();

    const options = (record && record.options) || [];
    for (let i = 0; i < options.length; i++) {
        // Сниппет HCTDraftOption объявлен в snippets.xml рядом с этим файлом.
        const row = $.CreatePanelFromSnippet(panel, 'file://{this}/snippets.xml#HCTDraftOption', '');
        if (!row) continue;

        const label = row.FindChildTraverse('HCTOptionName');
        if (label) label.text = (i + 1) + '. ' + heroDisplayName(options[i]);

        const votes = row.FindChildTraverse('HCTOptionVotes');
        if (votes) votes.text = 'голосов: ' + (record['votes' + (i + 1)] || 0);
    }
}

function renderStatus(label, record) {
    if (!record) {
        label.text = '';
        return;
    }
    if (record.finished === 1) {
        label.text = 'Выбран герой: ' + heroDisplayName(record.pick);
    } else if (record.open === 1) {
        label.text = 'Голосование открыто (' + record.voterCount + '/' + record.teamSize + ')';
    } else {
        label.text = 'Ожидание...';
    }
}

function refresh() {
    const panel = $.GetContextPanel();
    const draftPanel = panel.FindChildTraverse('hct_draft_panel');
    const teamLabel = panel.FindChildTraverse('HCT_DraftTeam');
    const optionsBox = panel.FindChildTraverse('HCT_Options');
    const statusLabel = panel.FindChildTraverse('HCT_DraftStatus');

    const key = myTeamKey();
    if (!key) {
        draftPanel.visible = false;
        return;
    }

    const record = getRecord(key);
    // Панель видна только когда драфт жив: есть options ИЛИ он ещё не закрыт.
    const show = !!record && (record.options.length > 0 || record.finished !== 1);
    draftPanel.visible = show;
    if (!show) return;

    teamLabel.text = key === 'radiant' ? 'Radiant' : 'Dire';
    renderOptions(optionsBox, record);
    renderStatus(statusLabel, record);
}

(function () {
    const panel = $.GetContextPanel();
    panel.RegisterForCustomNetTableUpdates(true);

    CustomNetTables.SubscribeNetTableListener(NETTABLE_NAME, () => refresh());

    $.Schedule(0.1, () => refresh());
})();
