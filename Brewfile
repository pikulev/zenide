# ЯДРО zenide — то, без чего сетап не работает.
#   brew bundle --file=Brewfile
# Полный личный стек (LSP, рантаймы, прочие тулы) — Brewfile.full.
# Что именно отвалится без каждого опционального тула — скажет `zenide doctor`.

# ── обязательное ───────────────────────────────────────
brew "tmux"           # шина: окна, попапы, хуки. Нужен ≥ 3.3
brew "helix"          # редактор в центре (слот editor)
brew "yazi"           # файловый менеджер в постоянном окне (слот files)
brew "lazygit"        # git-TUI (слот git_tui; альтернативы — gitui, tig)
brew "fzf"            # все попапы-пикеры; после установки: $(brew --prefix)/opt/fzf/install
cask "ghostty"        # терминал

# ── без них работает, но хуже ──────────────────────────
brew "fd"             # C-Space o: список файлов проекта
brew "ripgrep"        # подсветка и поиск в превью
brew "ripgrep-all"    # rga: C-Space / — live-grep, в том числе внутри PDF/Office/zip
brew "git-delta"      # пейджер диффов: попапы D и B, а также git-TUI
brew "bat"            # колонка кода в blame-попапе; без него попап работает, код без подсветки
brew "scooter"        # C-Space R: search & replace по проекту (слот search)
brew "zoxide"         # прыжок Z в файловом менеджере

# ── зависимости модулей ────────────────────────────────
# Нужен только модулю keyboard-force-latin (он по умолчанию выключен).
brew "laishulu/homebrew/macism"
