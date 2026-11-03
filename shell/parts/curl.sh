# off % symbol at the end of curl response
# https://superuser.com/questions/645599/why-is-a-percent-sign-appearing-before-each-prompt-on-zsh-in-windows
setopt PROMPT_CR
setopt PROMPT_SP
export PROMPT_EOL_MARK=""

alias myip='curl ifconfig.me'
