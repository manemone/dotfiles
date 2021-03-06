" Python path ----------------------------
if $PYENV_ROOT != ""
  " Python 2
  if filereadable($PYENV_ROOT . "/versions/neovim2/bin/python")
    let g:python_host_prog = $PYENV_ROOT . "/versions/neovim2/bin/python"
  endif

  " Python 3
  if filereadable($PYENV_ROOT . "/versions/neovim3/bin/python")
    let g:python3_host_prog = $PYENV_ROOT . "/versions/neovim3/bin/python"
  else
    let g:python3_host_prog = system('echo -n "$(pyenv root)/versions/$(cat $(pyenv root)/version | head -n 1)/bin/python" || echo -n $(which python)')
  endif
endif
" ----------------------------------------

" dein Scripts ---------------------------
if &compatible
  set nocompatible               " Be iMproved
endif

" Required:
set runtimepath+=$HOME/.cache/dein/repos/github.com/Shougo/dein.vim

" Required:
if dein#load_state($HOME . '/.cache/dein')
  call dein#begin($HOME . '/.cache/dein')

  call dein#load_toml($HOME . '/.config/nvim/dein.toml', { 'lazy': 0 })
  call dein#load_toml($HOME . '/.config/nvim/dein_lazy.toml', { 'lazy': 1 })

  " Required:
  call dein#end()
  call dein#save_state()
endif

" Required:
filetype plugin indent on
syntax enable

" If you want to install not installed plugins on startup.
if dein#check_install()
  call dein#install()
endif
" End dein Scripts -----------------------

" Appearance -----------------------------
" Set color mode to 256
set t_Co=256

" Use syntax hilighting
syntax on

" Colorscheme
colorscheme molokai

" Show line number
set number
" ----------------------------------------

" Indent ---------------------------------
" Number of spaces to be displayed for every tab character
set tabstop=2

" Number of spaces to be inserted on tapping tab key
set softtabstop=2

" Number of spaces to be inserted on autoindent
set shiftwidth=2

" Modify indent automatically on inserting newlines
set autoindent

" Insert spaces instead of tab character on tapping the key
set expandtab

" Modify indent width to a multiple of shiftwidth
set shiftround
" ----------------------------------------

" Copy yanked text onto clipboard
set clipboard=unnamed

" Search ---------------------------------
" Highlight matched text incrementally
set incsearch

" Keep matched text highlighted after search
set hls

" Ignore case for keyword in lower-cased
set ignorecase

" Do not ignore case for keyword with upper case
set smartcase

" Return to head of document after hitting the tail
set wrapscan

" Show paired surrounding element
set showmatch
set matchtime=1

" [NeoVim] Show the replacemnt result interactively
set inccommand=split
" ----------------------------------------

" Key mapping ----------------------------
" Map Leader key
let mapleader = "\<Space>"

" Open new file
nnoremap <Leader>o :CtrlP<CR>

" Save current buffer
nnoremap <Leader>w :w<CR>

" Copy current selected text to system clipboard
vmap <Leader>y "+y
vmap <Leader>d "+d
nmap <Leader>p "+p
nmap <Leader>P "+P
vmap <Leader>p "+p
vmap <Leader>P "+P

" Change to visual line mode
nmap <Leader><Leader> V

" Go to end op pasted text automatically
vnoremap <silent> y y`]
vnoremap <silent> p p`]
nnoremap <silent> p p`]

" Select pasted text quickly
noremap gV `[v`]

" Buffer swithing
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
nnoremap <Leader>h <C-w>h
nnoremap <Leader>j <C-w>j
nnoremap <Leader>k <C-w>k
nnoremap <Leader>l <C-w>l

nnoremap <Leader>d :Denite -mode=normal buffer file/rec<CR>
nnoremap <Leader>g :Denite grep -mode=normal<CR>

" Buffer resizing / moving
nnoremap <Leader>+ <C-w>+
nnoremap <Leader>- <C-w>-
nnoremap <Leader>vm <C-w>_
nnoremap <Leader>hm <C-w>|
nnoremap <Leader>H <C-w>H
nnoremap <Leader>J <C-w>J
nnoremap <Leader>K <C-w>K
nnoremap <Leader>L <C-w>L

" Back to command mode from ternimal mode
tnoremap <A-;> <C-\><C-n>
tnoremap … <C-\><C-n>
" ----------------------------------------

" vp doesn't replace paste buffer --------
function! RestoreRegister()
  let @" = s:restore_reg
  return ''
endfunction
function! s:Repl()
  let s:restore_reg = @"
  return "p@=RestoreRegister()\<cr>"
endfunction
vmap <silent> <expr> p <sid>Repl()
" ----------------------------------------
