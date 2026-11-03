# lazygit — держим конфиг в ~/.config/lazygit (как gitui/tig), а не в
# ~/Library/Application Support. lazygit уважает XDG_CONFIG_HOME на macOS;
# выставляем его только для процесса lazygit, глобально не трогаем.
lazygit() {
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" command lazygit "$@"
}

alias lg=lazygit   # общепринятое короткое имя
