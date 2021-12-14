local Path = require("plenary.path")
local Window = require("plenary.window.float")
local strings = require("plenary.strings")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local utils = require("telescope.utils")
local action_set = require("telescope.actions.set")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local git_worktree = require("git-worktree")

local get_worktree_path = function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    return selection.path
end

local switch_worktree = function(prompt_bufnr)
    local worktree_path = get_worktree_path(prompt_bufnr)
    actions.close(prompt_bufnr)
    if worktree_path ~= nil then
        git_worktree.switch_worktree(worktree_path)
    end
end

local offer_forced_deletion = function()
  local confirmation = vim.fn.input(
      string.format("Deletion failed, would you like to force delete? [y/n]: ")
  )

  if string.sub(string.lower(confirmation), 0, 1) == "y" then
      return true
  end

  return false
end

-- create_delete_failure_handler and delete_worktree need access to each other
-- so delete_worktree is initialized above create_delete_failure_handler
local delete_worktree

local create_delete_failure_handler = function(prompt_bufnr)
    return function(err)
        if offer_forced_deletion() then
            delete_worktree(prompt_bufnr, true)
        end
    end
end

delete_worktree = function(prompt_bufnr, force)
    local worktree_path = get_worktree_path(prompt_bufnr)
    actions.close(prompt_bufnr)
    if worktree_path ~= nil then
       git_worktree.delete_worktree(worktree_path, force, {
           on_failure = create_delete_failure_handler(prompt_bufnr),
       })
    end
end

local create_input_prompt = function()
    return vim.fn.input("Path to subtree > ")
end

local use_current_worktree_as_base_prompt = function()
    return vim.fn.confirm("Use current worktree as base?", "&Yes\n&No", 1) == 1
end

local get_base_branch = function(opts, name, branch)
    local base_branch_selection_opts = opts or {}
    base_branch_selection_opts.attach_mappings = function()
        actions.select_default:replace(function(prompt_bufnr, _)
            local selected_entry = action_state.get_selected_entry()
            local current_line = action_state.get_current_line()

            actions.close(prompt_bufnr)

            local base_branch = selected_entry ~= nil and selected_entry.value
                or current_line

            git_worktree.create_worktree(name, branch, nil, base_branch)
        end)

        -- do we need to replace other default maps?

        return true
    end
    require("telescope.builtin").git_branches(base_branch_selection_opts)
end

local create_worktree = function(opts)
    local branch_selection_opts = opts or {}
    branch_selection_opts.attach_mappings = function()
        actions.select_default:replace(function(prompt_bufnr, _)
            local selected_entry = action_state.get_selected_entry()
            local current_line = action_state.get_current_line()

            actions.close(prompt_bufnr)

            local branch = selected_entry ~= nil and selected_entry.value
                or current_line

            if branch == nil then
                return
            end

            local name = create_input_prompt()
            if name == "" then
                name = branch
            end

            local has_branch = git_worktree.has_branch(branch)

            if not has_branch then
                if use_current_worktree_as_base_prompt() then
                    git_worktree.create_worktree(name, branch)
                else
                    get_base_branch(opts, name, branch)
                end
            else
                git_worktree.create_worktree(name, branch)
            end
        end)

        -- do we need to replace other default maps?

        return true
    end
    require("telescope.builtin").git_branches(branch_selection_opts)
end

local telescope_git_worktree = function(opts)
    opts = opts or {}
    local output = utils.get_os_command_output({ "git", "worktree", "list" })
    local results = {}
    local widths = {
        path = 0,
        sha = 0,
        branch = 0,
    }

    local parse_line = function(line)
        local fields = vim.split(string.gsub(line, "%s+", " "), " ")
        local entry = {
            path = fields[1],
            sha = fields[2],
            branch = fields[3],
        }

        if entry.sha ~= "(bare)" then
            local index = #results + 1
            for key, val in pairs(widths) do
                if key == 'path' then
                    local new_path = utils.transform_path(opts, entry[key])
                    local path_len = strings.strdisplaywidth(new_path or "")
                    widths[key] = math.max(val, path_len)
                else
                    widths[key] = math.max(
                        val,
                        strings.strdisplaywidth(entry[key] or "")
                    )
                end
            end

            table.insert(results, index, entry)
        end
    end

    for _, line in ipairs(output) do
        parse_line(line)
    end

    if #results == 0 then
        return
    end

    local displayer = require("telescope.pickers.entry_display").create({
        separator = " ",
        items = {
            { width = widths.branch },
            { width = widths.path },
            { width = widths.sha },
        },
    })

    local make_display = function(entry)
        return displayer({
            { entry.branch, "TelescopeResultsIdentifier" },
            { utils.transform_path(opts, entry.path) },
            { entry.sha },
        })
    end

    pickers.new(opts or {}, {
        prompt_title = "Git Worktrees",
        finder = finders.new_table({
            results = results,
            entry_maker = function(entry)
                entry.value = entry.branch
                entry.ordinal = entry.branch
                entry.display = make_display
                return entry
            end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(_, map)
            action_set.select:replace(switch_worktree)

            map("i", "<c-d>", function(prompt_bufnr)
                delete_worktree(prompt_bufnr)
            end)
            map("n", "<c-d>", function(prompt_bufnr)
                delete_worktree(prompt_bufnr)
            end)

            return true
        end,
    }):find()
end

return require("telescope").register_extension({
    exports = {
        git_worktrees = telescope_git_worktree,
        create_git_worktree = create_worktree,
    },
})
