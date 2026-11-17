local M = {}

local function read_file(path, format)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local contents = file:read(format)
  file:close()
  return contents
end

local function read_proc(pid, file)
  return read_file(("/proc/%d/%s"):format(pid, file), "*a")
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
end

local function worktree_branch(root)
  local git_dir = vim.fs.joinpath(root, ".git")
  local stat = vim.uv.fs_stat(git_dir)
  if not stat then
    return nil
  elseif stat.type == "file" then
    -- Linked worktrees keep their own HEAD in the directory named by the gitfile.
    local gitfile = read_file(git_dir, "*l")
    git_dir = gitfile and gitfile:gsub("\r$", ""):match("^gitdir: (.+)$")
    if not git_dir then
      return nil
    end
    local absolute = git_dir:sub(1, 1) == "/"
      or (vim.fn.has("win32") == 1 and (git_dir:match("^\\") or git_dir:match("^%a:[/\\]")))
    if not absolute then
      git_dir = vim.fs.joinpath(root, git_dir)
    end
  elseif stat.type ~= "directory" then
    return nil
  end

  local head_path = vim.fs.joinpath(git_dir, "HEAD")
  local head_stat = vim.uv.fs_stat(head_path)
  local head = head_stat and head_stat.type == "file" and read_file(head_path, "*l")
  if not head then
    return nil
  end
  head = head:gsub("\r$", "")
  if (#head == 40 or #head == 64) and head:match("^%x+$") then
    return "detached@" .. head:sub(1, 7)
  end
  return head:match("^ref: refs/heads/(.+)$")
end

---@param term Terminal
---@return string
function M.format(term)
  local command, cwd = process_info(term)
  cwd = cwd or term:cwd()
  local root = cwd and worktree_root(cwd)
  local branch = root and worktree_branch(root)
  local directory = root or cwd
  local location = branch and (vim.fs.basename(root) .. ":" .. branch)
    or (directory and vim.fn.fnamemodify(directory, ":~") or "?")
  local label = ("%s %s  |  %s  |  %s"):format(term:get_status_icon(), term.name, command or term.cmd, location)
  return vim.fn.strtrans(label)
end

return M
