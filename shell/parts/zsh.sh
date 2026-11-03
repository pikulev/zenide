export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=ultima

plugins=(
  z
  fzf
  forgit
  dotenv
  macos
)

bindkey -e
bindkey "^[[1;3D" backward-word     # ⌥←
bindkey "^[[1;3C" forward-word      # ⌥→
bindkey "^[[1;9D" beginning-of-line # cmd+←
bindkey "^[[1;9C" end-of-line       # cmd+→

source $ZSH/oh-my-zsh.sh
