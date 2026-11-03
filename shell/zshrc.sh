PDIR=$SHELL_CONFIG_ROOT/parts

# System utilities
source $PDIR/unix.sh
source $PDIR/bin.sh

# Shell configuration
source $PDIR/zsh.sh
source $PDIR/eza.sh
source $PDIR/curl.sh
source $PDIR/fzf.sh
source $PDIR/tmux.sh
source $PDIR/zoxide.sh

# Git tools
source $PDIR/git.sh
source $PDIR/git-prompt.sh
source $PDIR/forgit.sh
source $PDIR/git-fzf.sh
source $PDIR/gitui.sh
source $PDIR/tig.sh
source $PDIR/lazygit.sh

# Diff tools
source $PDIR/difft.sh
source $PDIR/diff2html.sh

# Development environments
# node/pnpm/bun — под mise, он сорсится НИЖЕ (порядок важен, см. там же).
source $PDIR/go.sh
source $PDIR/pnpm.sh
source $PDIR/uv.sh
source $PDIR/bun.sh
source $PDIR/rust.sh

# Editors and IDEs
source $PDIR/vim.sh
source $PDIR/editor.sh

# Other tools
source $PDIR/slumber.sh
source $PDIR/brew.sh
source $PDIR/ssh.sh
source $PDIR/v2ray.sh

# Рантаймы — ПОСЛЕ brew.sh, и это не вкусовщина: `brew shellenv` препендит
# /opt/homebrew/bin, то есть любой тул, приехавший в brew зависимостью,
# затеняет версию из менеджера рантаймов. Так brew-овый node (прилетел как
# зависимость формулы) молча перебивал версию, запиненную в proto.
source $PDIR/mise.sh

# Личные фрагменты: всё из parts/private/ (под .gitignore). Здесь живёт то,
# что не должно попасть в публичную историю — рабочие хосты, токены, алиасы
# под NDA. Нет каталога — ничего не происходит.
if [ -d "$PDIR/private" ]; then
    for f in "$PDIR"/private/*.sh(N); do source "$f"; done
fi

clear
