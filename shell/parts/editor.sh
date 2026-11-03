# Редактор один на всё — helix. Блокирующий вызов (`git commit`, `crontab -e`)
# открывает hx в ТЕКУЩЕМ пейне и ждёт выхода: это правильное поведение для
# шелла. Отдать файл в УЖЕ работающий hx — отдельная операция, `zenide open`,
# и её используют TUI (lazygit, tig), а не $EDITOR.
export EDITOR=hx
export VISUAL=hx
