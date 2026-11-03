-- Регистрация плагина git.yazi (показывает git-статус у файлов).
require("git"):setup {
	order = 1500, -- позиция значка статуса в строке файла
}

-- Статус-бар: вместо имени файла — путь относительно корня проекта
-- (каталога, из которого запущен yazi; наш C-Space e стартует из git root).
local status_root
function Status:name()
	local h = self._current.hovered
	if not h then
		return ""
	end
	status_root = status_root or tostring(cx.active.current.cwd) -- фиксируем стартовый каталог при первом рендере
	local p = tostring(h.url)
	if p:sub(1, #status_root + 1) == status_root .. "/" then
		p = p:sub(#status_root + 2)
	end
	return ui.Line(" " .. p)
end

-- Кастомный linemode: дата модификации + размер, например «12 Jun, 26, 10:12  4.5K».
-- (встроенные linemode умеют либо size, либо mtime — не вместе)
function Linemode:size_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	local timestr = time == 0 and "" or os.date("%d %b, %y, %H:%M", time)

	local size = self._file:size()
	local sizestr = size and ya.readable_size(size) or ""

	if timestr == "" and sizestr == "" then
		return ""
	end
	-- фиксированные колонки: дата 17 симв. + размер по правому краю в 6 симв.
	-- (иначе переменная ширина размера «возит» дату влево-вправо)
	return string.format("%17s %6s", timestr, sizestr)
end

-- sshfs.yazi: маунт ssh-хостов из ~/.ssh/config (бинд M в keymap.toml).
-- Маунты в ~/mnt/<host>. default_mount_point=auto → пикер «Mount where?»:
-- home/root/custom + пути ниже (при "home" пикер не показывается вовсе).
-- global_paths — для всех хостов (вся лаба = deploy, проекты в /stacks);
-- host_paths — точечно: host_paths = { ["caddy.sh1"] = "/etc/caddy" }
require("sshfs"):setup({
	default_mount_point = "auto",
	global_paths = { "/stacks" },
})
