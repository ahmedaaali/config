return {
	"numToStr/Comment.nvim",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		"JoosepAlviste/nvim-ts-context-commentstring",
	},
	config = function()
		local comment = require("Comment")
		local ts_context_commentstring = require("ts_context_commentstring.integrations.comment_nvim")

		comment.setup({
			pre_hook = ts_context_commentstring.create_pre_hook(),
			-- Set commentstring for .txt files
			padding = true,
			ignore = nil,
		})

		-- Set commentstring for text files
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "text",
			callback = function()
				vim.opt_local.commentstring = "# %s"
			end,
		})
	end,
}
