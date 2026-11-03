--- @sync entry
-- Не пускать `h` (leave) выше корня проекта.
-- Корень передаётся через env YAZI_ROOT (его выставляют tmux-бинды e/E).
-- Без YAZI_ROOT ведёт себя как обычный leave.
return {
	entry = function()
		local root = os.getenv("YAZI_ROOT")
		if root then
			root = root:gsub("/+$", "")
			local cwd = tostring(cx.active.current.cwd):gsub("/+$", "")
			if cwd == root then
				ya.notify { title = "yazi", content = "корень проекта", timeout = 1, level = "info" }
				return
			end
		end
		ya.emit("leave", {})
	end,
}
