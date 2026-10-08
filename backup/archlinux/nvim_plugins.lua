local BUILD_TIMEOUT = 300000
local PARSER_TIMEOUT = 600000
local BUILD_COMMANDS = {
  LuaSnip = 'make install_jsregexp',
  ['telescope-fzf-native.nvim'] = 'make',
  ['nvim-treesitter'] = ':TSUpdate',
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
  for name in pairs(manifest.plugins) do
    check_directory(plugin_root .. '/' .. name)
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
  local spec = require('lazy.core.plugin').Spec.new({ { import = 'plugins' }, { 'folke/lazy.nvim' } }, { pkg = false })
  for _, notice in ipairs(spec.notifs) do
    if notice.level >= vim.log.levels.WARN then
      fail(notice.msg)
    end
  end

  local names = vim.tbl_keys(spec.plugins)
  table.sort(names)
  for _, name in ipairs(names) do
    local plugin = spec.plugins[name]
    local locked = manifest.plugins[name]
    if not plugin.url or plugin.dev or plugin.virtual or plugin.dir ~= plugin_root .. '/' .. name then
      fail('Unsupported local plugin: ' .. name)
    end
    if not locked or normalize_url(plugin.url) ~= normalize_url(locked.url) then
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
  for name in pairs(manifest.plugins) do
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
  vim.opt.rtp:append(data_dir .. '/lazy/nvim-treesitter')
  local treesitter = require 'nvim-treesitter'
  treesitter.setup { install_dir = data_dir .. '/site' }
  local registry = require 'nvim-treesitter.parsers'
  for _, lang in ipairs(manifest.parsers) do
    local parser = registry[lang]
    if not parser or parser.tier == 4 or not parser.install_info or not parser.install_info.revision or parser.install_info.path then
      fail('Unsupported or unpinned parser: ' .. lang)
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
    local task = treesitter.install(manifest.parsers, { force = true, max_jobs = 4, summary = true })
    if task:wait(PARSER_TIMEOUT) ~= true then
      fail('Treesitter parser installation failed.')
    end
  end
end

local function verify_parsers(data_dir, manifest, registry)
  local site = data_dir .. '/site'
  for _, lang in ipairs(manifest.parsers) do
    local revision = read_file(site .. '/parser-info/' .. lang .. '.revision')
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

local function main()
  if #arg ~= 4 or (arg[1] ~= 'build' and arg[1] ~= 'verify') then
    fail('Usage: nvim -u NONE -i NONE -n -l nvim_plugins.lua build|verify CONFIG_DIR DATA_DIR MANIFEST_JSON')
  end
  local mode, config_dir, data_dir = arg[1], vim.fs.normalize(arg[2]), vim.fs.normalize(arg[3])
  if config_dir:sub(1, 1) ~= '/' or data_dir:sub(1, 1) ~= '/' then
    fail('Configuration and data paths must be absolute.')
  end
  local manifest = read_manifest(arg[4])
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
