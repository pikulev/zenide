-- Запасной nvim в облике hx-сетапа. ОДИН файл, НОЛЬ плагинов — переносится
-- на любую машину с nvim 0.11+ простым копированием. Что сознательно НЕ
-- повторено из hx (без плагинов не бывает): git-гуттер, пикеры, дифф-темы.
-- Клавиши тут НЕ настраиваются — свои добавляй в секции в конце файла.

-- ── поведение (как в hx config.toml) ───────────────────────────────
vim.o.termguicolors = true
vim.o.number = true
vim.o.cursorline = true          -- якорь для глаза
vim.o.scrolloff = 4
vim.o.signcolumn = "yes"
vim.o.wrap = false               -- soft-wrap по умолчанию выключен
vim.o.undofile = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.showmode = false           -- режим показывает статусбар
vim.o.laststatus = 2
vim.o.guicursor = "n-v:block,i-ci:ver25"   -- NOR блок, INS — bar (как в hx)

-- indent guides «│» без плагина: leadmultispace по ширине отступа буфера
local function indent_guides()
  local sw = vim.bo.shiftwidth > 0 and vim.bo.shiftwidth or vim.bo.tabstop
  vim.opt_local.list = true
  vim.opt_local.listchars = { leadmultispace = "│" .. string.rep(" ", sw - 1), tab = "  " }
end
vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, { callback = indent_guides })

-- авто-сохранение при потере фокуса (tmux focus-events уже включён)
vim.api.nvim_create_autocmd("FocusLost", { command = "silent! wa" })

-- подсветка янка — дешёвый ориентир, встроено
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank({ timeout = 120 }) end,
})

-- ── палитра Monokai Pro Spectrum (как monokai-custom в hx) ──────────
local p = {
  bg = "#222222", fg = "#f7f1ff", dim = "#69676c", sel = "#525053",
  line = "#2a292b", red = "#fc618d", orange = "#fd9353", yellow = "#fce566",
  green = "#7bd88f", cyan = "#5ad4e6", purple = "#948ae3", faint = "#3a393b",
}
local function hl(g, o) vim.api.nvim_set_hl(0, g, o) end
hl("Normal",       { fg = p.fg, bg = p.bg })
hl("CursorLine",   { bg = p.line })
hl("CursorLineNr", { fg = p.fg, bg = p.line })
hl("LineNr",       { fg = p.dim })
hl("Visual",       { bg = p.sel })
hl("Comment",      { fg = p.dim, italic = true })
hl("String",       { fg = p.yellow })
hl("Number",       { fg = p.purple })
hl("Constant",     { fg = p.purple })
hl("Identifier",   { fg = p.fg })
hl("Function",     { fg = p.green })
hl("Statement",    { fg = p.red })
hl("Operator",     { fg = p.red })
hl("Type",         { fg = p.cyan, italic = true })
hl("PreProc",      { fg = p.red })
hl("Special",      { fg = p.orange })
hl("MatchParen",   { bg = p.sel, bold = true })
hl("Search",       { fg = p.bg, bg = p.yellow })
hl("IncSearch",    { fg = p.bg, bg = p.orange })
hl("Pmenu",        { fg = p.fg, bg = p.faint })
hl("PmenuSel",     { fg = p.fg, bg = p.sel })
hl("Whitespace",   { fg = p.faint })          -- indent guides
hl("NonText",      { fg = p.faint })
hl("WinSeparator", { fg = p.sel })
hl("DiagnosticError", { fg = p.red })
hl("DiagnosticWarn",  { fg = p.yellow })
hl("DiagnosticInfo",  { fg = p.cyan })
hl("DiagnosticHint",  { fg = p.dim })
hl("DiffAdd",    { fg = p.green })
hl("DiffChange", { fg = p.yellow })
hl("DiffDelete", { fg = p.red })

-- ── статусбар (лейаут как в hx) ────────────────────────────────────
-- режимные цвета: NOR зелёный / INS жёлтый / SEL фиолетовый
hl("StlNOR", { fg = p.bg, bg = p.green,  bold = true })
hl("StlINS", { fg = p.bg, bg = p.yellow, bold = true })
hl("StlSEL", { fg = p.bg, bg = p.purple, bold = true })
hl("StatusLine",   { fg = p.fg, bg = p.bg })
hl("StatusLineNC", { fg = p.dim, bg = p.bg })

-- ветка git: кэш на буфер, обновление при входе/записи
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
  callback = function(a)
    local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(a.buf))
    if dir == "" then return end
    vim.system({ "git", "-C", dir, "branch", "--show-current" }, {},
      vim.schedule_wrap(function(r)
        vim.b[a.buf].branch = (r.code == 0) and vim.trim(r.stdout or "") or ""
      end))
  end,
})

function _G.Stl()
  local m = vim.api.nvim_get_mode().mode
  local mode, mhl = "NOR", "StlNOR"
  if m:find("^i") then mode, mhl = "INS", "StlINS"
  elseif m:find("^[vV\22]") then mode, mhl = "SEL", "StlSEL" end
  local mod = vim.bo.modified and " [+]" or ""
  local branch = vim.b.branch and vim.b.branch ~= "" and (" " .. vim.b.branch) or ""
  local diag = ""
  local n = #vim.diagnostic.get(0)
  if n > 0 then diag = "● " .. n .. " │ " end
  return "%#" .. mhl .. "# " .. mode .. " %#StatusLine#" .. mod .. branch
      .. "  %f %= " .. diag .. "%l:%c │ %L │ %p%% │ %{&filetype} "
end
vim.o.statusline = "%!v:lua.Stl()"

-- ── диагностика: текст скрыт (как в hx), только значки ──────────────
vim.diagnostic.config({ virtual_text = false, severity_sort = true })

-- ── LSP: те же серверы, что в hx languages.toml (nvim 0.11+ natively) ─
local servers = {
  ts_ls    = { cmd = { "typescript-language-server", "--stdio" },
               filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
               root_markers = { "package.json", ".git" } },
  rust     = { cmd = { "rust-analyzer" }, filetypes = { "rust" },
               root_markers = { "Cargo.toml" } },
  ruff     = { cmd = { "ruff", "server" }, filetypes = { "python" },
               root_markers = { "pyproject.toml", ".git" } },
  ty       = { cmd = { "ty", "server" }, filetypes = { "python" },
               root_markers = { "pyproject.toml", ".git" } },
  bashls   = { cmd = { "bash-language-server", "start" }, filetypes = { "sh", "bash" },
               root_markers = { ".git" } },
  marksman = { cmd = { "marksman", "server" }, filetypes = { "markdown" },
               root_markers = { ".git" } },
  clangd   = { cmd = { "clangd" }, filetypes = { "c", "cpp" },
               root_markers = { "compile_commands.json", ".git" } },
  jsonls   = { cmd = { "vscode-json-language-server", "--stdio" }, filetypes = { "json" },
               root_markers = { ".git" } },
}
for name, cfg in pairs(servers) do
  -- включать только найденные бинари: на серверах LSP обычно нет,
  -- и конфиг должен молча работать без них (переносимость)
  if vim.fn.executable(cfg.cmd[1]) == 1 then
    vim.lsp.config(name, cfg)
    vim.lsp.enable(name)
  end
end

-- формат вручную: :Fmt (LSP-форматтер; prettier-цепочки hx тут нет — честно)
vim.api.nvim_create_user_command("Fmt", function() vim.lsp.buf.format() end, {})

-- ── ТВОИ КЛАВИШИ ────────────────────────────────────────────────────
-- сюда — привычные бинды; конфиг выше клавиш не трогает
