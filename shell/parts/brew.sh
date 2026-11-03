# homebrew PATH init
eval "$(/opt/homebrew/bin/brew shellenv)"
# Заменяем системный curl (не всегда это хорошая идея, но можно выключить, если что)
export PATH="/opt/homebrew/opt/curl/bin:$PATH"
