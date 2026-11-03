# slumber на macOS читает ~/Library/Application Support/slumber/config.yml,
# мимо нашей ~/.config-схемы. Переменной перенаправляем его на слинкованный
# config/slumber (bootstrap делает ~/.config/slumber -> myconfig/config/slumber).
export SLUMBER_CONFIG_PATH="$HOME/.config/slumber/config.yml"
