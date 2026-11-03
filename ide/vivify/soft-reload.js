/* Превью vivify обновляется мягко и само. Инжектится в КАЖДУЮ страницу через
 * "scripts" в config.json — поэтому работает и для файлов, открытых не через
 * Space m, а переходом по ссылке внутри превью.
 *
 * Чинит две беды разом.
 *
 * 1) ЖЁСТКАЯ ПЕРЕЗАГРУЗКА. vivify на изменение файла шлёт клиенту «RELOAD: 1»,
 *    а client.mjs делает window.location.reload(): моргание, развёрнутые
 *    <details> схлопываются, mermaid/katex считаются заново. И прилетает это
 *    ровно тогда, когда на превью смотришь: hx пишет файл на каждую потерю
 *    фокуса (editor.auto-save.focus-lost) — то есть на любой попап
 *    (C-Space Space/D/B//), смену пейна/окна и alt-tab в браузер.
 *
 * 2) МЁРТВЫЙ ВОТЧЕР. hx пишет файл АТОМАРНО: временный файл + rename, то есть
 *    новый inode на каждое сохранение (проверено: inode до/после :w разные).
 *    fs.watch на macOS привязан к inode, и после первого же сохранения из hx
 *    события перестают приходить совсем — превью молча застывает. Выглядит
 *    это как «обновления работают через раз», а лечится обычно рефлексом
 *    «нажму Space m ещё раз», отчего viv переоткрывает URL: вот она,
 *    перезагрузка с выдёргиванием окна браузера на передний план.
 *
 * КАК. Патчить location.reload нельзя: члены Location помечены в HTML-спеке
 * как [LegacyUnforgeable] — non-writable/non-configurable. Зато можно подменить
 * транспорт: этот файл инлайнится как ОБЫЧНЫЙ <script>, а client.mjs — как
 * <script type="module">, то есть отложенный. Наш код гарантированно
 * выполняется раньше и успевает завернуть window.WebSocket, перехватив
 * обработчик сообщений.
 *
 * Дальше свежесть мы обеспечиваем сами: пока вкладка видима, раз в POLL_MS
 * тянем страницу фетчем и сравниваем разметку тела. Изменилась — отдаём её
 * перехваченному обработчику под видом «UPDATE: <html>», того самого
 * сообщения, которое vivify шлёт редакторным плагинам (vivify.vim): он
 * подменяет innerHTML, прогоняет mermaid.run() и переисполняет <script> из
 * новой разметки. Страница не перезагружается — скролл остаётся на месте.
 * Поллинг не зависит от inode, так что атомарные записи hx больше не теряются.
 * Прилетевший «RELOAD» (если вотчер жив) просто ускоряет ближайшую сверку.
 *
 * Любая осечка (нет #body-content — картинка/бинарник/renderHTML, сервер
 * ответил не 200) → ничего не делаем, перезагрузка остаётся за vivify.
 *
 * ВАЖНО: vivify читает конфиг только при старте. После правки этого файла —
 * pkill -f vivify-server, иначе в страницы уйдёт старая версия.
 */

(function () {
    const CONTAINER = 'body-content';
    // раз в столько миллисекунд сверяемся с сервером, пока вкладка видима;
    // рендер markdown на localhost стоит доли миллисекунды, зато превью
    // шевелится сразу за сохранением, не дожидаясь fs.watch (который мёртв)
    const POLL_MS = 600;
    const ERROR_BACKOFF_MS = 5000;

    // Разметка ровно в том виде, в каком её отдал сервер. Снимается СИНХРОННО,
    // до того как client.mjs (отложенный модуль) впишет в неё svg от mermaid —
    // иначе сравнение с ответом сервера всегда давало бы «изменилось».
    let serverHTML = document.getElementById(CONTAINER)?.innerHTML ?? null;

    // обработчик сообщений client.mjs: умеет UPDATE (innerHTML + mermaid +
    // переисполнение <script>). Ловим его в патче WebSocket ниже.
    let clientListener = null;
    let syncing = false;

    /* ── <details> ──────────────────────────────────────────────────────
     * Живут в разметке самого markdown; подмена innerHTML их пересоздаёт, и
     * открытые секции закрылись бы. Ключ — текст <summary> плюс порядковый
     * номер одинаковых: переживает правку текста вокруг, но не переезд секции. */

    const foldKey = (node, seen) => {
        const title = (node.querySelector('summary')?.textContent ?? '').trim();
        const n = seen.get(title) ?? 0;
        seen.set(title, n + 1);
        return `${n} ${title}`;
    };

    const snapshotFolds = () => {
        const seen = new Map();
        const state = new Map();
        document.querySelectorAll(`#${CONTAINER} details`).forEach((node) => {
            state.set(foldKey(node, seen), node.open);
        });
        return state;
    };

    const restoreFolds = (state) => {
        if (!state.size) return;
        const seen = new Map();
        document.querySelectorAll(`#${CONTAINER} details`).forEach((node) => {
            const was = state.get(foldKey(node, seen));
            if (was !== undefined) node.open = was;
        });
    };

    /* ── сверка с сервером ──────────────────────────────────────────── */

    const sync = async () => {
        if (syncing || serverHTML === null || !clientListener) return;
        syncing = true;
        try {
            const res = await fetch(location.href, {
                headers: { Accept: 'text/html' },
                cache: 'no-store',
            });
            if (!res.ok) throw new Error(`HTTP ${res.status}`);

            const doc = new DOMParser().parseFromString(await res.text(), 'text/html');
            const fresh = doc.getElementById(CONTAINER);
            if (!fresh) throw new Error('no container'); // не live-рендерится

            if (fresh.innerHTML === serverHTML) return;
            serverHTML = fresh.innerHTML;

            const folds = snapshotFolds();
            // client.mjs ставит innerHTML синхронно, до первого await внутри
            // своего обработчика, — значит к возврату DOM уже новый
            await clientListener({ data: `UPDATE: ${serverHTML}` });
            restoreFolds(folds);

            if (doc.title) document.title = doc.title;
        } finally {
            syncing = false;
        }
    };

    let timer = null;
    const schedule = (delay) => {
        clearTimeout(timer);
        timer = setTimeout(tick, delay);
    };
    const tick = async () => {
        if (document.hidden) return schedule(POLL_MS);
        try {
            await sync();
            schedule(POLL_MS);
        } catch {
            schedule(ERROR_BACKOFF_MS);
        }
    };

    // вкладку только что открыли/вернули — не ждать полный интервал
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden) schedule(0);
    });
    schedule(POLL_MS);

    /* ── перехват транспорта ────────────────────────────────────────── */

    const Native = window.WebSocket;
    if (!Native) return;

    function Patched(...args) {
        const ws = new Native(...args);
        const add = ws.addEventListener.bind(ws);

        ws.addEventListener = function (type, listener, options) {
            if (type !== 'message' || typeof listener !== 'function') {
                return add(type, listener, options);
            }
            clientListener = listener;
            add(
                'message',
                (event) => {
                    // вотчер жив и просит перезагрузку — вместо неё сверка
                    if (String(event.data).startsWith('RELOAD')) schedule(0);
                    else listener(event);
                },
                options,
            );
        };

        return ws;
    }
    Patched.prototype = Native.prototype;
    ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach((k) => (Patched[k] = Native[k]));

    window.WebSocket = Patched;
})();
