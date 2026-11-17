local M = {}

local function read_proc(pid, file)
  local proc_file = io.open(("/proc/%d/%s"):format(pid, file), "r")
  if not proc_file then
    return nil
  end
  local contents = proc_file:read("*a")
  proc_file:close()
  return contents
end

local function foreground_pid(pid)
  local stat = read_proc(pid, "stat")
  -- The parenthesized command name can itself contain spaces or parentheses.
  local tpgid = stat and tonumber(stat:match("^%d+ %(.+%) %S+ %-?%d+ %-?%d+ %-?%d+ %-?%d+ (%-?%d+) "))
  if tpgid and tpgid > 0 then
    return tpgid
  end
  return pid
end

local function process_info(term)
  local job_id = term:get_state("job_id")
  if not job_id or job_id <= 0 or vim.fn.has("linux") ~= 1 then
    return nil, nil
  end
  local ok, pid = pcall(vim.fn.jobpid, job_id)
  if not ok or pid <= 0 then
    return nil, nil
  end
  local foreground = foreground_pid(pid)
  local comm = read_proc(foreground, "comm")
  local cwd = vim.uv.fs_readlink(("/proc/%d/cwd"):format(foreground))
    or vim.uv.fs_readlink(("/proc/%d/cwd"):format(pid))
  return comm and comm:gsub("\n$", ""), cwd
end

local function worktree_root(cwd)
  -- Walk literal paths: vim.fs.root may expand environment variables in them.
  cwd = vim.uv.fs_realpath(cwd) or cwd
  if vim.uv.fs_stat(vim.fs.joinpath(cwd, ".git")) then
    return cwd
  end
  for dir in vim.fs.parents(cwd) do
    if vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then
      return dir
    end
  end
  return cwd
end

---@param term Terminal
---@return string
function M.format(term)
  local command, cwd = process_info(term)
  cwd = cwd or term:cwd()
  local directory = cwd and worktree_root(cwd)
  local location = directory and vim.fn.fnamemodify(directory, ":~") or "?"
  local label = ("%s %s  |  %s  |  %s"):format(term:get_status_icon(), term.name, command or term.cmd, location)
  return vim.fn.strtrans(label)
end

return M
