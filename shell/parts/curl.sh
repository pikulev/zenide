# off % symbol at the end of curl response
# https://superuser.com/questions/645599/why-is-a-percent-sign-appearing-before-each-prompt-on-zsh-in-windows
setopt PROMPT_CR
setopt PROMPT_SP
export PROMPT_EOL_MARK=""

# myip теперь исполняемая команда из shell/bin; снимаем старый алиас при source.
unalias myip 2>/dev/null || true
