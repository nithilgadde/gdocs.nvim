if exists('g:loaded_gdocs')
  finish
endif
let g:loaded_gdocs = 1

augroup GDocsAutoSetup
  autocmd!
  autocmd VimEnter * ++once lua if not require('gdocs')._state.initialized then require('gdocs').setup() end
augroup END
