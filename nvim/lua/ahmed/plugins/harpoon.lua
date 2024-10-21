return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local harpoon = require("harpoon")

    harpoon.setup({})

    -- -- basic telescope configuration
    -- local conf = require("telescope.config").values
    -- local function toggle_telescope(harpoon_files)
    -- 	local file_paths = {}
    -- 	for _, item in ipairs(harpoon_files.items) do
    -- 		table.insert(file_paths, item.value)
    -- 	end
    --
    -- 	require("telescope.pickers")
    -- 		.new({}, {
    -- 			prompt_title = "Harpoon",
    -- 			finder = require("telescope.finders").new_table({
    -- 				results = file_paths,
    -- 			}),
    -- 			previewer = conf.file_previewer({}),
    -- 			sorter = conf.generic_sorter({}),
    -- 		})
    -- 		:find()
    -- end

    -- vim.keymap.set("n", "<C-e>", function()
    -- 	toggle_telescope(harpoon:list())
    -- end, { desc = "Open harpoon window" })
    vim.keymap.set("n", "<C-e>", function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end, { desc = "Open harpoon window" })
    vim.keymap.set("n", "<leader>a", function()
      harpoon:list():add()
    end, { desc = "Add to harpoon list" })

    vim.keymap.set("n", "<C-q>", function()
      harpoon:list():select(1)
    end, { desc = "1st harpoon" })
    vim.keymap.set("n", "<C-t>", function()
      harpoon:list():select(2)
    end, { desc = "2nd harpoon" })
    vim.keymap.set("n", "<C-y>", function()
      harpoon:list():select(3)
    end, { desc = "3rd harpoon" })
    vim.keymap.set("n", "<C-,>", function()
      harpoon:list():select(4)
    end, { desc = "4th harpoon" })

    vim.keymap.set("n", "<C-p>", function()
      harpoon:list():prev()
    end, { desc = "previous harpoon" })
    vim.keymap.set("n", "<C-n>", function()
      harpoon:list():next()
    end, { desc = "next harpoon" })
  end,
}
