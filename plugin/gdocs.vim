" gdocs.nvim - Edit Google Docs in Neovim
" Maintainer: Your Name
" License: MIT

if exists('g:loaded_gdocs')
  finish
endif
let g:loaded_gdocs = 1

" Auto-setup with default config if user doesn't call setup()
augroup GDocsAutoSetup
  autocmd!
  autocmd VimEnter * ++once lua if not require('gdocs')._state.initialized then require('gdocs').setup() end
augroup END
