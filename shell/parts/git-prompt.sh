# Есть зависимость от git-prompt-init.sh

# Финальный результат выдает функиця gitprompt.
# В ultima theme есть замена оригинальной функции на эту

ZSH_GIT_PROMPT_FORCE_BLANK=1
ZSH_GIT_PROMPT_SHOW_UPSTREAM="no"

# Theming variables for primary prompt
ZSH_THEME_GIT_PROMPT_PREFIX="%F{237}on "
ZSH_THEME_GIT_PROMPT_SUFFIX=""
ZSH_THEME_GIT_PROMPT_SEPARATOR=" %F{237}› "
ZSH_THEME_GIT_PROMPT_DETACHED="%{$fg_no_bold[cyan]%}:"

ZSH_THEME_GIT_PROMPT_BRANCH="%F{85}"

ZSH_THEME_GIT_PROMPT_BEHIND="%F{243} %{↓%G%}"
ZSH_THEME_GIT_PROMPT_AHEAD="%F{white} %{🚀%G%}"

ZSH_THEME_GIT_PROMPT_STAGED="%F{white}%{📦%G%}"

ZSH_THEME_GIT_PROMPT_UNSTAGED="%{$fg[red]%}🎈"
ZSH_THEME_GIT_PROMPT_UNTRACKED="%F{red}%{…%G%}"
ZSH_THEME_GIT_PROMPT_UNMERGED="%{$fg[red]%}⛔️"
ZSH_THEME_GIT_PROMPT_STASHED="%{$fg[blue]%}🔖"

ZSH_THEME_GIT_PROMPT_UPSTREAM_SYMBOL="%{$fg_bold[yellow]%}⟳ "
ZSH_THEME_GIT_PROMPT_UPSTREAM_PREFIX="%{$fg[red]%}(%{$fg[yellow]%}"
ZSH_THEME_GIT_PROMPT_UPSTREAM_SUFFIX="%{$fg[red]%})"

ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg_bold[green]%}%{☘️%G%}"

# Theming variables for the secondary prompt
ZSH_THEME_GIT_PROMPT_SECONDARY_PREFIX=""
ZSH_THEME_GIT_PROMPT_SECONDARY_SUFFIX=""
ZSH_THEME_GIT_PROMPT_TAGS_SEPARATOR=", "
ZSH_THEME_GIT_PROMPT_TAGS_PREFIX="🏷 "
ZSH_THEME_GIT_PROMPT_TAGS_SUFFIX=""
ZSH_THEME_GIT_PROMPT_TAG="%{$fg_bold[magenta]%}"

# source shell code:
source $SHELL_CONFIG_ROOT/parts/git-prompt.zsh