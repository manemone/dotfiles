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

" [NeoVim] Show the replacemnt result interactively
set inccommand=split
" ----------------------------------------

" Buffer swithing ------------------------
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
" ----------------------------------------
