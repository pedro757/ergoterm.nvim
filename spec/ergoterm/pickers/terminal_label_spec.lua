---@diagnostic disable: undefined-field

---@module "ergoterm.pickers.terminal_label"
local label = require("ergoterm.pickers.terminal_label")
---@module "ergoterm.pickers.p_vim_ui_select"
local picker = require("ergoterm.pickers.p_vim_ui_select")

describe("Terminal picker labels", function()
  local root, cwd, git_dir
  local buf, job
  local term

  before_each(function()
    root = vim.fn.tempname()
    cwd = root .. "/linked worktree $HOME/src"
    git_dir = root .. "/main/.git/worktrees/linked"
    vim.fn.mkdir(cwd, "p")
    vim.fn.mkdir(git_dir, "p")
    vim.fn.writefile({ "gitdir: ../main/.git/worktrees/linked" }, vim.fs.dirname(cwd) .. "/.git")
    vim.fn.writefile({ "ref: refs/heads/feature/terminal-label" }, git_dir .. "/HEAD")
    term = {
      cmd = "sh -i",
      name = "Shell",
      get_status_icon = function() return "▶" end,
      get_state = function(_, key) if key == "job_id" then return job end end,
      cwd = function() return cwd end,
    }
  end)

  after_each(function()
    if job then
      if vim.fn.jobwait({ job }, 0)[1] == -1 then
        vim.fn.jobstop(job)
        vim.fn.jobwait({ job }, 3000)
      end
      job = nil
    end
    if buf then
      vim.api.nvim_buf_delete(buf, { force = true })
      buf = nil
    end
    vim.fn.delete(root, "rf")
  end)

  it("falls back to the configured command and shows the linked worktree's own branch", function()
    assert.equal("▶ Shell  |  sh -i  |  linked worktree $HOME:feature/terminal-label", label.format(term))
  end)

  it("shows the main worktree's branch", function()
    vim.fn.writefile({ "ref: refs/heads/main" }, root .. "/main/.git/HEAD")
    term.cwd = function() return root .. "/main" end
    assert.equal("▶ Shell  |  sh -i  |  main:main", label.format(term))
  end)

  it("shows the abbreviated commit for a detached worktree", function()
    vim.fn.writefile({ ("a"):rep(40) }, git_dir .. "/HEAD")
    assert.equal("▶ Shell  |  sh -i  |  linked worktree $HOME:detached@aaaaaaa", label.format(term))
  end)

  it("shows the directory when it is outside Git", function()
    term.cwd = function() return root end
    assert.equal("▶ Shell  |  sh -i  |  " .. root, label.format(term))
  end)

  it("detects the live foreground process and its worktree on Linux", function()
    if vim.fn.has("linux") ~= 1 then
      return
    end

    term.cwd = function() return root end
    buf = vim.api.nvim_create_buf(false, false)
    job = vim.api.nvim_buf_call(buf, function()
      return vim.fn.jobstart({ "sh", "-i" }, { term = true, cwd = root, env = { ENV = "/dev/null" } })
    end)
    assert.is_true(job > 0)
    vim.fn.chansend(job, "cd '" .. cwd .. "' && sleep 1; exit\n")
    local expected = "▶ Shell  |  sleep  |  linked worktree $HOME:feature/terminal-label"
    assert.is_true(vim.wait(3000, function() return label.format(term) == expected end))
    assert.equal(0, vim.fn.jobwait({ job }, 3000)[1])
  end)

  it("preserves the selected terminal and ignores cancellation", function()
    local on_choice
    local stub_select = stub(vim.ui, "select", function(items, opts, cb)
      assert.same({ term }, items)
      assert.equal(label.format(term), opts.format_item(term))
      on_choice = cb
    end)
    local call = spy.new(function() end)
    picker.select({ term }, "Select a terminal", { default = { fn = call } })
    stub_select:revert()

    on_choice(nil)
    assert.spy(call).was_not_called()
    on_choice(term)
    assert.spy(call).was_called_with(term)
  end)
end)
