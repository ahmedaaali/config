vim.g.mapleader = " "

local keymap = vim.keymap

keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode with jk" })

keymap.set("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights" })

keymap.set("n", "<leader>+", "<C-a>", { desc = "Increment number" })
keymap.set("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split window vertically" })
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split window horizontally" })
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" })
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" })
keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" })
keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" })
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" })

-- Normal mode mappings
keymap.set("n", "Y", "yg$", { desc = "Yank to end of line" })
keymap.set("n", "n", "nzzzv", { desc = "Next search result centered" })
keymap.set("n", "N", "Nzzzv", { desc = "Previous search result centered" })
keymap.set("n", "J", "mzJ`z", { desc = "Join lines and keep cursor in place" })
keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Scroll down half a page and center" })
keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Scroll up half a page and center" })
keymap.set("n", "<leader>y", '"+y', { desc = "Yank to system clipboard" })
keymap.set("n", "<leader>dl", '"_d', { desc = "Delete without yanking" })
keymap.set("n", "<leader>dd", '"_dd', { desc = "Delete line without yanking" })
keymap.set("n", "<leader>d$", '"_d$', { desc = "Delete to end of line without yanking" })
keymap.set("n", "<leader>d0", '"_d0', { desc = "Delete to start of line without yanking" })
keymap.set("n", "<leader>D", '"_D', { desc = "Delete without yanking" })
keymap.set("n", "<leader>c", '"_c', { desc = "Change without yanking" })
keymap.set("n", "<leader>C", '"_C', { desc = "Change without yanking" })
keymap.set("n", "<leader>o", "o<Esc>", { desc = "Add a new line in Normal mode" })
keymap.set("n", "<leader>np", "o<Esc>p", { desc = "Add a new line and paste" })

-- Visual mode mappings
keymap.set("x", "<leader>p", '"_dP', { desc = "Pasting in visual mode without overwriting the clipboard" })
keymap.set("x", "<leader>y", '"+y', { desc = "Yank to system clipboard" })
keymap.set("x", "<leader>dl", '"_d', { desc = "Delete without yanking" })
keymap.set("x", "<leader>dd", '"_d', { desc = "Delete selection without yanking" })
keymap.set("x", "<leader>d$", '"_d$', { desc = "Delete to end of line without yanking" })
keymap.set("x", "<leader>d0", '"_d0', { desc = "Delete to start of line without yanking" })
keymap.set("x", "<leader>D", '"_D', { desc = "Delete without yanking" })
keymap.set("x", "<leader>c", '"_c', { desc = "Change without yanking" })
keymap.set("x", "<leader>C", '"_C', { desc = "Change without yanking" })
keymap.set("x", "jk", "<Esc>", { desc = "Exit visual mode" })

-- Insert mode mappings
-- keymap.set("i", "<C-c>", "<Esc>", { desc = "Escape with Ctrl+C" })
-- pcall(vim.api.nvim_del_keymap, "i", "<C-s>")
-- pcall(vim.api.nvim_del_keymap, "n", "<C-w>")
-- vim.api.nvim_del_keymap("n", "<C-w>")
-- vim.api.nvim_set_keymap("", "<C-w>", "<Nop>", { noremap = true, silent = true })
