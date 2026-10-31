local BUILD_TIMEOUT = 300000
local PARSER_TIMEOUT = 600000
local BUILD_COMMANDS = {
  LuaSnip = 'make install_jsregexp',
  ['telescope-fzf-native.nvim'] = 'make',
  ['nvim-treesitter'] = ':TSUpdate',
}

local PARSER_SOURCES = {
  ['bash'] = 'https://github.com/tree-sitter/tree-sitter-bash',
  ['c'] = 'https://github.com/tree-sitter/tree-sitter-c',
  ['diff'] = 'https://github.com/tree-sitter-grammars/tree-sitter-diff',
  ['fortran'] = 'https://github.com/stadelmanma/tree-sitter-fortran',
  ['html'] = 'https://github.com/tree-sitter/tree-sitter-html',
  ['latex'] = 'https://github.com/latex-lsp/tree-sitter-latex',
  ['lua'] = 'https://github.com/tree-sitter-grammars/tree-sitter-lua',
  ['luadoc'] = 'https://github.com/tree-sitter-grammars/tree-sitter-luadoc',
  ['markdown'] = 'https://github.com/tree-sitter-grammars/tree-sitter-markdown',
  ['markdown_inline'] = 'https://github.com/tree-sitter-grammars/tree-sitter-markdown',
  ['nu'] = 'https://github.com/nushell/tree-sitter-nu',
  ['python'] = 'https://github.com/tree-sitter/tree-sitter-python',
  ['query'] = 'https://github.com/tree-sitter-grammars/tree-sitter-query',
  ['vim'] = 'https://github.com/tree-sitter-grammars/tree-sitter-vim',
  ['vimdoc'] = 'https://github.com/neovim/tree-sitter-vimdoc',
  ['cpp'] = 'https://github.com/tree-sitter/tree-sitter-cpp',
  ['git_config'] = 'https://github.com/the-mikedavis/tree-sitter-git-config',
  ['git_rebase'] = 'https://github.com/the-mikedavis/tree-sitter-git-rebase',
  ['gitignore'] = 'https://github.com/shunsambongi/tree-sitter-gitignore',
  ['make'] = 'https://github.com/tree-sitter-grammars/tree-sitter-make',
  ['matlab'] = 'https://github.com/acristoffers/tree-sitter-matlab',
  ['powershell'] = 'https://github.com/airbus-cert/tree-sitter-powershell',
  ['ssh_config'] = 'https://github.com/tree-sitter-grammars/tree-sitter-ssh-config',
}

local function fail(message)
  error(message, 0)
end

local function read_file(path)
  local file, err = io.open(path, 'rb')
  if not file then
    fail(err)
  end
  local data = file:read '*a'
  file:close()
  return data
end

local function check_directory(path)
  local stat = vim.uv.fs_lstat(path)
  if not stat or stat.type ~= 'directory' then
    fail('Expected a regular directory: ' .. path)
  end
end

local function read_manifest(path)
  local manifest = vim.json.decode(read_file(path))
  if type(manifest) ~= 'table' or type(manifest.plugins) ~= 'table' or type(manifest.parsers) ~= 'table' then
    fail('Invalid Neovim manifest.')
  end
  if not vim.islist(manifest.parsers) or type(manifest.nvim_version) ~= 'string' or manifest.nvim_version == '' then
    fail('Invalid Neovim manifest metadata.')
  end
  local seen = {}
  for _, lang in ipairs(manifest.parsers) do
    if type(lang) ~= 'string' or not lang:match '^[a-z][a-z0-9_]*$' or seen[lang] then
      fail('Invalid or duplicate parser name.')
    end
    seen[lang] = true
  end
  for name, plugin in pairs(manifest.plugins) do
    if type(name) ~= 'string' or not name:match '^[%w_.-]+$' or name == '.' or name == '..' then
      fail('Invalid plugin name.')
    end
    if type(plugin) ~= 'table' or type(plugin.commit) ~= 'string' or not plugin.commit:match '^%x+$' or #plugin.commit ~= 40 then
      fail('Invalid plugin commit: ' .. name)
    end
    if type(plugin.url) ~= 'string' or plugin.url == '' then
      fail('Missing plugin URL: ' .. name)
    end
  end
  if not manifest.plugins['lazy.nvim'] or not manifest.plugins['nvim-treesitter'] then
    fail('Manifest must include lazy.nvim and nvim-treesitter.')
  end
  return manifest
end

local function normalize_url(url)
  return url:gsub('^git@github.com:', 'https://github.com/'):gsub('%.git$', ''):gsub('/$', '')
end

local function load_specs(config_dir, data_dir, manifest)
  local plugin_root = data_dir .. '/lazy'
  check_directory(plugin_root)
  if manifest then
    for name in pairs(manifest.plugins) do
      check_directory(plugin_root .. '/' .. name)
    end
  end

  -- Read specs without plugin startup.
  vim.opt.rtp = { config_dir, plugin_root .. '/lazy.nvim', vim.env.VIMRUNTIME }
  vim.g.have_nerd_font = true
  local config = require 'lazy.core.config'
  config.setup {
    root = plugin_root,
    lockfile = config_dir .. '/lazy-lock.json',
    local_spec = false,
    install = { missing = false },
    pkg = { enabled = false },
    rocks = { enabled = false },
    checker = { enabled = false },
    change_detection = { enabled = false },
    readme = { enabled = false, root = data_dir .. '/lazy/readme' },
    performance = { reset_packpath = true, rtp = { reset = false } },
  }
  local specs = require 'plugin_specs'
  local spec = require('lazy.core.plugin').Spec.new({ specs, { 'folke/lazy.nvim' } }, { pkg = false })
  for _, notice in ipairs(spec.notifs) do
    if notice.level >= vim.log.levels.WARN then
      fail(notice.msg)
    end
  end

  local names = vim.tbl_keys(spec.plugins)
  table.sort(names)
  for _, name in ipairs(names) do
    local plugin = spec.plugins[name]
    local locked = manifest and manifest.plugins[name]
    if not plugin.url or plugin.dev or plugin.virtual or plugin.dir ~= plugin_root .. '/' .. name then
      fail('Unsupported local plugin: ' .. name)
    end
    if manifest and (not locked or normalize_url(plugin.url) ~= normalize_url(locked.url)) then
      fail('Plugin spec does not match the manifest: ' .. name)
    end
    if plugin.build ~= nil and plugin.build ~= false and plugin.build ~= BUILD_COMMANDS[name] then
      fail('Unsupported build hook: ' .. name)
    end
    if BUILD_COMMANDS[name] and plugin.build ~= BUILD_COMMANDS[name] then
      fail('Required build hook is unavailable: ' .. name .. ' (check make).')
    end
    if plugin.build == nil and (vim.uv.fs_stat(plugin.dir .. '/build.lua') or vim.uv.fs_stat(plugin.dir .. '/build/init.lua')) then
      fail('Unsupported implicit build hook: ' .. name)
    end
  end
  for name in pairs(manifest and manifest.plugins or {}) do
    local plugin = spec.plugins[name] or spec.disabled[name]
    if not plugin or not plugin.url or plugin.dir ~= plugin_root .. '/' .. name then
      fail('Manifest plugin is absent from the specs: ' .. name)
    end
    if normalize_url(plugin.url) ~= normalize_url(manifest.plugins[name].url) then
      fail('Plugin URL does not match the manifest: ' .. name)
    end
  end
  return spec.plugins, names
end

local function load_treesitter(data_dir, manifest)
  vim.opt.rtp:append(data_dir .. '/site')
  vim.opt.rtp:append(data_dir .. '/lazy/nvim-treesitter')
  local treesitter = require 'nvim-treesitter'
  treesitter.setup { install_dir = data_dir .. '/site' }
  local registry = require 'nvim-treesitter.parsers'
  for _, lang in ipairs(manifest.parsers) do
    local parser = registry[lang]
    if not parser or parser.tier == 4 or not parser.install_info or not parser.install_info.revision or parser.install_info.path then
      fail('Unsupported or unpinned parser: ' .. lang)
    end
    if parser.install_info.url ~= PARSER_SOURCES[lang] then
      fail('Parser source changed; review the new URL: ' .. lang)
    end
  end
  return treesitter, registry
end

local function build_plugins(plugins, names, treesitter, manifest)
  for _, name in ipairs(names) do
    local plugin = plugins[name]
    local command = plugin.build
    if command and command ~= ':TSUpdate' then
      io.stdout:write('  -> Building ' .. name .. '...\n')
      local result = vim.system({ '/bin/bash', '-c', command }, { cwd = plugin.dir, text = true }):wait(BUILD_TIMEOUT)
      if result.code ~= 0 or result.signal ~= 0 then
        fail('Build failed for ' .. name .. ': ' .. vim.trim((result.stderr or '') .. '\n' .. (result.stdout or '')))
      end
    end
    local docs = plugin.dir .. '/doc'
    if vim.fn.isdirectory(docs) == 1 and #vim.fn.glob(docs .. '/*.txt', false, true) > 0 then
      vim.cmd('helptags ' .. vim.fn.fnameescape(docs))
    end
  end
  if #manifest.parsers > 0 then
    io.stdout:write('  -> Building Treesitter parsers...\n')
    local task = treesitter.install(manifest.parsers, { force = not manifest.reuse_parser_artifacts, max_jobs = 4, summary = true })
    if task:wait(PARSER_TIMEOUT) ~= true then
      fail('Treesitter parser installation failed.')
    end
  end
end

local function verify_parsers(data_dir, manifest, registry)
  local site = data_dir .. '/site'
  for _, lang in ipairs(manifest.parsers) do
    local revision = read_file(site .. '/parser-info/' .. lang .. '.revision')
    if manifest.grammars and (not manifest.grammars[lang]
        or manifest.grammars[lang].revision ~= registry[lang].install_info.revision
        or manifest.grammars[lang].url ~= registry[lang].install_info.url) then
      fail('Grammar provenance differs from the selected plugin: ' .. lang)
    end
    if revision ~= registry[lang].install_info.revision then
      fail('Parser revision does not match the locked plugin: ' .. lang)
    end
    local parser_path = site .. '/parser/' .. lang .. '.so'
    local stat = vim.uv.fs_lstat(parser_path)
    if not stat or stat.type ~= 'file' then
      fail('Missing regular parser library: ' .. parser_path)
    end
    vim.treesitter.language.add(lang, { path = parser_path })
    local trees = vim.treesitter.get_string_parser('', lang):parse()
    if not trees or not trees[1] then
      fail('Parser returned no syntax tree: ' .. lang)
    end
    if not vim.treesitter.query.get(lang, 'highlights') then
      fail('Missing Treesitter highlights: ' .. lang)
    end
  end
end

local function verify_native_plugins(plugins)
  if plugins.LuaSnip then
    local path = plugins.LuaSnip.dir .. '/deps/luasnip-jsregexp.so'
    local loader, err = package.loadlib(path, 'luaopen_jsregexp_core')
    if not loader then
      fail('LuaSnip regex library failed to load: ' .. tostring(err))
    end
  end
  if plugins['telescope-fzf-native.nvim'] then
    vim.opt.rtp:append(plugins['telescope-fzf-native.nvim'].dir)
    require 'fzf_lib'
  end
end

local function verify_lsp()
  local directory = vim.env.HOME .. '/lsp-check'
  vim.fn.mkdir(directory, 'p')
  vim.fn.writefile({}, directory .. '/.clangd')
  vim.fn.writefile({ '[project]', 'name = "managed-validation"', 'version = "0.0.0"' }, directory .. '/pyproject.toml')
  local samples = {
    { 'clangd', 'review.c', { 'int review_value(void) { return 42; }' } },
    { 'pylsp', 'review.py', { 'def review_value():', '    return 42' } },
  }
  for _, sample in ipairs(samples) do
    local path = directory .. '/' .. sample[2]
    vim.fn.writefile(sample[3], path)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local buffer = vim.api.nvim_get_current_buf()
    local client
    if not vim.wait(20000, function()
      for _, item in ipairs(vim.lsp.get_clients { bufnr = buffer, name = sample[1] }) do
        if item.initialized then client = item; return true end
      end
      return false
    end, 50) then
      fail('Language server did not initialize: ' .. sample[1])
    end
    local response, err = client:request_sync('textDocument/documentSymbol', {
      textDocument = vim.lsp.util.make_text_document_params(buffer),
    }, 10000, buffer)
    if err or not response or response.err or not vim.json.encode(response.result):find('review_value', 1, true) then
      fail('Language server documentSymbol request failed: ' .. sample[1])
    end
    client:stop(true)
    io.stdout:write('[OK] ' .. sample[1] .. ' initialized and returned document symbols.\n')
  end
end

local function verify_jukit()
  if vim.g.python3_host_prog ~= '/usr/bin/python3' or vim.g.jukit_shell_cmd ~= '/usr/bin/ipython3' then
    fail('Jukit must use the declared Arch system Python/IPython paths.')
  end
  if vim.fn.has 'python3' ~= 1 or vim.fn.py3eval '6 * 7' ~= 42 then
    fail('The real pynvim Python provider is unavailable.')
  end
  local directory = vim.env.HOME .. '/jukit-check'
  vim.fn.mkdir(directory, 'p')
  local source = directory .. '/core.py'
  vim.fn.writefile({ 'result = 6 * 7', 'print(result)' }, source)
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  local buffer, window = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.bo.filetype = 'python'
  vim.api.nvim_win_set_cursor(window, { 2, 0 })
  vim.fn['jukit#cells#split']()
  if not table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n'):find('|%%--%%|', 1, true) then
    fail('Jukit cell splitting did not create a marker.')
  end
  vim.api.nvim_win_set_cursor(window, { 1, 0 })
  vim.fn['jukit#cells#merge_below']()
  if table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n'):find('|%%--%%|', 1, true) then
    fail('Jukit cell merge left its marker behind.')
  end
  vim.cmd 'write'
  vim.g.jukit_terminal = 'nvimterm'
  vim.fn['jukit#splits#output']()
  local info = directory .. '/.jukit/.jukit_info.json'
  local imported = vim.wait(20000, function()
    local ok, value = pcall(function() return vim.json.decode(read_file(info)) end)
    return ok and value.import_complete == 1
  end, 50)
  if not imported then fail('Jukit IPython terminal did not initialize.') end
  vim.api.nvim_set_current_win(window)
  vim.api.nvim_set_current_buf(buffer)
  vim.api.nvim_win_set_cursor(window, { 1, 0 })
  vim.fn['jukit#send#section'](0)
  local history = directory .. '/.jukit/core_outhist.json'
  local saved = vim.wait(20000, function()
    local ok, value = pcall(read_file, history)
    return ok and value:find('42', 1, true) ~= nil
  end, 50)
  if not saved then fail('Jukit cell execution did not save its result.') end
  vim.fn['jukit#splits#close_output_split']()
  vim.api.nvim_set_current_win(window)
  vim.api.nvim_set_current_buf(buffer)
  vim.g.jukit_convert_overwrite_default = 1
  vim.g.jukit_convert_open_default = 0
  vim.fn['jukit#convert#notebook_convert']()
  local notebook = vim.json.decode(read_file(directory .. '/core.ipynb'))
  if not notebook.cells or #notebook.cells == 0 then fail('Jukit script-to-notebook conversion failed.') end
  vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/core.ipynb'))
  local moved, move_error = vim.uv.fs_rename(source, directory .. '/core-original.py')
  if not moved then fail('Could not preserve the conversion fixture: ' .. tostring(move_error)) end
  vim.fn['jukit#convert#notebook_convert']()
  if not read_file(source):find('print(result)', 1, true) then fail('Jukit notebook-to-script conversion failed.') end
  if vim.v.errmsg == 'E486: Pattern not found: ^"""°°°' then
    -- Jukit silently probes its legacy Markdown delimiter.
    vim.v.errmsg = ''
  end
  io.stdout:write('[OK] Jukit provider, cell split/merge, real IPython terminal, execution, saved output and round-trip conversion.\n')
end

local function verify_formatters()
  local directory = vim.env.HOME .. '/formatter-check'
  vim.fn.mkdir(directory, 'p')
  local nu = directory .. '/sample.nu'
  vim.fn.writefile({ 'let  value=42' }, nu)
  vim.cmd('edit ' .. vim.fn.fnameescape(nu))
  vim.bo.filetype = 'nu'
  local format_error
  require('conform').format({ async = false, timeout_ms = 10000, lsp_format = 'never' }, function(err)
    format_error = err
  end)
  if format_error or vim.api.nvim_get_current_line() ~= 'let value = 42' then
    fail('Conform Topiary Nu formatting failed: ' .. tostring(format_error))
  end
  vim.cmd 'write'
  local source = directory .. '/null.cpp'
  vim.fn.writefile({ 'int main() { int *p = nullptr; return *p; }' }, source)
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  vim.bo.filetype = 'cpp'
  local buffer, lint = vim.api.nvim_get_current_buf(), require 'lint'
  lint.try_lint 'clangtidy'
  if not vim.wait(15000, function()
    for _, diagnostic in ipairs(vim.diagnostic.get(buffer, { namespace = lint.get_namespace 'clangtidy' })) do
      if diagnostic.code == 'clang-analyzer-core.NullDereference' then return true end
    end
    return false
  end, 50) then fail('Clang-tidy did not return the baseline analyzer diagnostic.') end
  io.stdout:write('[OK] Conform Topiary Nu formatting and clang-tidy analyzer diagnostics.\n')
end

local function verify_startup(config_dir, data_dir, manifest)
  if vim.fn.stdpath 'config' ~= config_dir or vim.fn.stdpath 'data' ~= data_dir then
    fail('Startup XDG paths do not point to the selected generation.')
  end
  if vim.env.NVIM_MANAGED_GENERATION ~= vim.fs.basename(vim.fs.dirname(vim.fs.dirname(config_dir))) then
    fail('Startup generation identity differs from the configuration tree.')
  end
  if not vim.uv.fs_stat(config_dir .. '/lua/plugin_specs.lua')
      or not vim.uv.fs_stat(config_dir .. '/lua/plugins/render-markdown.lua') then
    fail('Incomplete configuration tree: shared specs or Markdown module missing.')
  end
  if manifest.runtime_source then
    local root = vim.fs.dirname(vim.fs.dirname(config_dir))
    if vim.env.VIMRUNTIME ~= root .. '/runtime/share/nvim/runtime'
        or vim.uv.fs_realpath(vim.v.progpath) ~= vim.uv.fs_realpath(root .. '/runtime/bin/nvim') then
      fail('Executable or VIMRUNTIME leaves the selected generation.')
    end
  end
  local errors = {}
  local notify = vim.notify
  vim.notify = function(message, level, opts)
    if level and level >= vim.log.levels.ERROR then
      errors[#errors + 1] = tostring(message)
    end
    notify(message, level, opts)
  end
  vim.opt.rtp:prepend(config_dir)
  vim.o.loadplugins = true
  vim.cmd 'filetype plugin indent on'
  vim.cmd 'syntax enable'
  dofile(config_dir .. '/init.lua')
  local config = require 'lazy.core.config'
  if config.plugins['nvim-cmp'] then
    fail('Both completion engines are loaded.')
  end
  local names = vim.tbl_keys(config.plugins)
  table.sort(names)
  require('lazy').load { plugins = names, wait = true }
  vim.api.nvim_exec_autocmds('VimEnter', { modeline = false })
  vim.api.nvim_exec_autocmds('InsertEnter', { modeline = false })
  vim.wait(1000, function() return false end, 20)
  for _, name in ipairs(names) do
    local plugin = config.plugins[name]
    if name ~= 'lazy.nvim' and not plugin._.loaded then
      fail('Plugin did not load: ' .. name)
    end
  end
  local cmp = require 'blink.cmp'
  local capabilities = cmp.get_lsp_capabilities()
  if not capabilities.textDocument.completion.completionItem.snippetSupport then
    fail('Blink LSP snippet capabilities are missing.')
  end
  local opts = require('lazy.core.plugin').values(config.plugins['blink.cmp'], 'opts', false)
  if opts.keymap['<C-k>'][1] ~= 'select_prev' or not opts.signature.enabled then
    fail('Completion/signature key ownership differs from the configured contract.')
  end
  local snippets = require 'luasnip'
  snippets.add_snippets('all', {
    snippets.snippet('codex_snippet', { snippets.text_node('value='), snippets.insert_node(1, 'one'),
                                     snippets.text_node('; next='), snippets.insert_node(2, 'two') }),
  }, { key = 'managed-validation' })
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  vim.o.virtualedit = 'onemore'
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'codex_snippet' })
  vim.api.nvim_win_set_cursor(0, { 1, #'codex_snippet' })
  if not opts.keymap['<Tab>'][1](cmp) or not vim.api.nvim_get_current_line():find('value=one', 1, true) then
    fail('Tab did not expand the real LuaSnip snippet.')
  end
  if not opts.keymap['<Tab>'][1](cmp) then fail('Tab did not advance the snippet.') end
  if not opts.keymap['<S-Tab>'][1](cmp) then fail('Shift-Tab did not move back in the snippet.') end
  snippets.unlink_current()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  vim.o.virtualedit = ''
  if vim.v.errmsg == 'E117: Unknown function: repeat#set' and vim.fn.exists '*repeat#set' == 0 then
    -- LuaSnip intentionally probes optional vim-repeat with silent!.
    vim.v.errmsg = ''
  end
  io.stdout:write('[OK] Real LuaSnip Tab expansion/forward and Shift-Tab backward.\n')
  require('telescope').load_extension 'fzf'
  require('telescope').load_extension 'ui-select'
  local samples = {
    { 'lua', 'local value = 42' }, { 'python', 'value = 42' },
    { 'c', 'int value = 42;' }, { 'markdown', '# Heading\n\n$\\alpha + \\beta$' },
    { 'bash', 'echo hello' }, { 'nu', 'let value = 42' },
    { 'cpp', 'template <class T> T twice(T value) { return value + value; }' },
    { 'gitconfig', '[core]\n  editor = nvim' }, { 'gitrebase', 'pick 0123456 Example commit' },
    { 'gitignore', '# Ignore\n*.o\nbuild/' }, { 'make', 'all:\n\t@echo done' },
    { 'matlab', 'function value = review(x)\nvalue = x + 1;\nend' },
    { 'ps1', '$value = 42' }, { 'sshconfig', 'Host example\n  User researcher' },
  }
  for _, sample in ipairs(samples) do
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(sample[2], '\n'))
    vim.bo[buffer].filetype = sample[1]
    local parser = vim.treesitter.get_parser(buffer)
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.get(parser:lang(), 'highlights')
    local count = 0
    for _ in query:iter_captures(tree:root(), buffer) do count = count + 1 end
    if count == 0 then fail('No highlight captures: ' .. sample[1]) end
    io.stdout:write('[OK] highlights: ' .. sample[1] .. '\n')
  end
  for _, filetype in ipairs { 'dosini' } do
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { '[section]', 'value = 42' })
    vim.bo[buffer].filetype = filetype
    if vim.bo[buffer].syntax ~= filetype then fail('Vim syntax fallback missing: ' .. filetype) end
  end
  if vim.fn.executable 'latex2text' ~= 1 then
    fail('Missing latex2text; install Arch python-pylatexenc separately.')
  end
  local result = vim.system({ 'latex2text' }, { stdin = '$\\alpha + \\beta$', text = true }):wait(10000)
  if result.code ~= 0 or not result.stdout:find('α', 1, true) then
    fail('latex2text Unicode conversion failed.')
  end
  local render = require 'render-markdown'
  render.enable()
  render.disable()
  render.enable()
  vim.wait(300, function() return false end, 20)
  verify_lsp()
  verify_jukit()
  verify_formatters()
  if #errors > 0 then fail(table.concat(errors, '\n')) end
  if vim.v.errmsg ~= '' then fail(vim.v.errmsg) end
  io.stdout:write('[VALIDATION] ' .. vim.json.encode {
    lsp_validation = { passed = true, clangd = 'initialized-and-documentSymbol', pylsp = 'initialized-and-documentSymbol' },
    formatter_validation = { passed = true, topiary_nu = 'conform-offline-format', clangtidy = 'real-analyzer-diagnostic' },
    jukit_core_validation = { passed = true, level = 'real-isolated-integration',
      provider = 'passed', cell_edit = 'passed', cell_run = 'passed', output_save = 'passed',
      core_conversion = 'passed', python = vim.g.python3_host_prog, ipython = vim.g.jukit_shell_cmd },
  } .. '\n')
  io.stdout:write('[OK] Full startup, ' .. #names .. ' plugins, completion/LSP, native extensions, highlighting and rendering APIs.\n')
end

local function main()
  if #arg ~= 4 or not vim.tbl_contains({ 'specs', 'inventory', 'build', 'verify', 'startup' }, arg[1]) then
    fail('Usage: nvim -u NONE -i NONE -n -l nvim_plugins.lua specs|inventory|build|verify|startup CONFIG_DIR DATA_DIR MANIFEST_JSON')
  end
  local mode, config_dir, data_dir = arg[1], vim.fs.normalize(arg[2]), vim.fs.normalize(arg[3])
  if config_dir:sub(1, 1) ~= '/' or data_dir:sub(1, 1) ~= '/' then
    fail('Configuration and data paths must be absolute.')
  end
  if mode == 'specs' then
    local plugins = load_specs(config_dir, data_dir)
    local exported = {}
    for name, plugin in pairs(plugins) do
      exported[name] = { url = plugin.url, branch = plugin.branch, version = plugin.version,
                         commit = plugin.commit, tag = plugin.tag }
    end
    local ts = require('lazy.core.plugin').values(plugins['nvim-treesitter'], 'opts', false)
    io.stdout:write(vim.json.encode { plugins = exported, parsers = ts.parsers } .. '\n')
    return
  end
  local manifest = read_manifest(arg[4])
  if mode == 'startup' then
    verify_startup(config_dir, data_dir, manifest)
    return
  end
  local lock_path = config_dir .. '/lazy-lock.json'
  local lock_contents = read_file(lock_path)
  local lock = vim.json.decode(lock_contents)
  for name, plugin in pairs(manifest.plugins) do
    if not lock[name] or lock[name].commit ~= plugin.commit then
      fail('Lock file does not match the manifest: ' .. name)
    end
  end
  for name in pairs(lock) do
    if not manifest.plugins[name] then
      fail('Lock entry is absent from the manifest: ' .. name)
    end
  end
  local plugins, names = load_specs(config_dir, data_dir, manifest)
  local treesitter, registry = load_treesitter(data_dir, manifest)
  if mode == 'inventory' then
    local grammars = {}
    for _, lang in ipairs(manifest.parsers) do
      grammars[lang] = { url = registry[lang].install_info.url,
                         revision = registry[lang].install_info.revision }
    end
    io.stdout:write(vim.json.encode(grammars) .. '\n')
    return
  end
  if mode == 'build' then
    build_plugins(plugins, names, treesitter, manifest)
  else
    verify_native_plugins(plugins)
    verify_parsers(data_dir, manifest, registry)
  end
  if read_file(lock_path) ~= lock_contents then
    fail('Lock file changed during Neovim restoration.')
  end
  io.stdout:write('[OK] Neovim plugin ' .. mode .. ' completed.\n')
end

local ok, err = pcall(main)
if not ok then
  io.stderr:write('[ERROR] ' .. tostring(err) .. '\n')
  vim.cmd 'cquit 1'
end
