# keyboard-force-latin

Форсит латинскую раскладку (`com.apple.keylayout.ABC`) при любом переходе по
tmux: между пейнами, окнами, сессиями.

**Проблема.** Хоткеи helix, yazi, lazygit — латинские буквы. Если осталась
включённой нелатинская раскладка, перейдя в окно yazi ты нажимаешь `g` и не
получаешь ничего. Лечится не дисциплиной, а переключением за тебя.

**Решение.** Три tmux-хука (`after-select-pane`, `session-window-changed`,
`client-session-changed`) зовут `abc.sh`, который просит `macism` поставить
input source фронт-приложения в ABC. Внутри окна и в попапах раскладку не
трогает — там можно печатать на любом языке.

**Зависимости:** `macism` (macOS), `brew install laishulu/homebrew/macism`.
Без него модуль молча ничего не делает — `zenide doctor` это покажет.

**Почему `after-select-pane`, а не `pane-focus-in`:** второй завязан на
focus-события терминала и приходит не всегда.

**Включить:** добавь `keyboard-force-latin` в `modules` в
`profile/modules.conf`.
