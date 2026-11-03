
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# отключить flow control (Ctrl-S = XOFF «заморозка» терминала):
# ghostty шлёт Ctrl-S по Cmd+S для сохранения в hx — в шелле он не должен вешать вывод
[[ -t 0 ]] && stty -ixon

# off % symbol at the end of curl response
# https://superuser.com/questions/645599/why-is-a-percent-sign-appearing-before-each-prompt-on-zsh-in-windows
setopt PROMPT_CR
setopt PROMPT_SP
export PROMPT_EOL_MARK=""

alias c='clear'
alias rm='rm -i'
alias cp='cp -i'

alias lp='lsof +c 0 -nP -iTCP -sTCP:LISTEN'

