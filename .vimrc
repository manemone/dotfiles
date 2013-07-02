"------ pathogen -------
"call pathogen#runtime_append_all_bundles()

set t_Co=256
syntax on
"set background=dark
"let g:solarized_termcolors=256
"colorscheme solarized
"colorscheme molokai

"------ indent --------
set autoindent
set smartindent
set cindent

"------ tab --------
set shiftwidth=4
set smarttab
set tabstop=4
set softtabstop=4
set expandtab

"------ cursor --------
"dont stop cursor at the end of line or first of line
set whichwrap=b,s,h,l,<,>,[,]
"for split mode
nmap <C-k> <ESC><C-w>k
imap <C-k> <ESC><C-w>k
nmap <C-j> <ESC><C-w>j
imap <C-j> <ESC><C-w>j
nmap <C-l> <ESC><C-w>l
imap <C-l> <ESC><C-w>l
nmap <C-g> <ESC><C-w>h
imap <C-g> <ESC><C-w>h
"for square choose mode
set virtualedit+=block
"for japanese

"------ key --------
set backspace=indent,eol,start

"------ search --------
set incsearch
set nowrapscan

"------ display --------
set number
set title
set ruler
set list
set listchars=tab:>\ ,extends:<
"correspond to ()
set showmatch
set showcmd
set laststatus=2

"------ extra --------
set clipboard=unnamed
nmap <F7> :!gcc %<CR>; ./a.out
nmap <F6> :!ruby %<CR>

"------ others --------
"vi compatible
set nocompatible
set history=1000

"--twitvim ---------
let twitvim_count = 40
nnoremap tp :<C-u>PosttoTwitter<CR>
nnoremap tf :<C-u>FriendsTwitter<CR><C-w>
nnoremap tu :<C-u>UserTwitter<CR><C-w>
nnoremap tr :<C-u>RepliesTwitter<CR><C-w>
nnoremap tn :<C-u>NextTwitter<CR>

"--- for latex -----
filetype plugin on
set shellslash
set grepprg=grep\ -nH\ $*
let g:tex_flavor='latex'
let g:Tex_DefaultTargetFormat = 'pdf'
let g:Tex_FormatDependency_ps = 'dvi,ps'
let g:Tex_FormatDependency_pdf = 'dvi,pdf'
let g:Tex_CompileRule_dvi = 'eplatex -synctex=-1 -src-specials -interaction=nonstopmode $*'
let g:Tex_CompileRule_ps = 'dvips -Ppdf -o $*.ps $*.dvi'
let g:Tex_CompileRule_pdf = 'dvipdfmx $*.dvi'
let g:Tex_BibtexFlavor = 'pbibtex'
let g:Tex_MakeIndexFlavor = 'mendex $*.idx'
"let g:Tex_ViewRule_dvi = 'C:\w32tex\dviout\dviout.exe -1'
"let g:Tex_ViewRule_ps = 'C:\Program Files\Ghostgum\gsview\gsview32.exe -e'
"let g:Tex_ViewRule_pdf = 'C:\Program Files\SumatraPDF\SumatraPDF.exe -reuse-instance'


"-- japanese enc judge ---

if &encoding !=# 'utf-8'
  set encoding=japan
  set fileencoding=japan
endif
if has('iconv')
  let s:enc_euc = 'euc-jp'
  let s:enc_jis = 'iso-2022-jp'
  " iconvがeucJP-msに対応しているかをチェック
  if iconv("\x87\x64\x87\x6a", 'cp932', 'eucjp-ms') ==# "\xad\xc5\xad\xcb"
    let s:enc_euc = 'eucjp-ms'
    let s:enc_jis = 'iso-2022-jp-3'
  " iconvがJISX0213に対応しているかをチェック
  elseif iconv("\x87\x64\x87\x6a", 'cp932', 'euc-jisx0213') ==# "\xad\xc5\xad\xcb"
    let s:enc_euc = 'euc-jisx0213'
    let s:enc_jis = 'iso-2022-jp-3'
  endif
  " fileencodingsを構築
  if &encoding ==# 'utf-8'
    let s:fileencodings_default = &fileencodings
    let &fileencodings = s:enc_jis .','. s:enc_euc .',cp932'
    let &fileencodings = &fileencodings .','. s:fileencodings_default
    unlet s:fileencodings_default
  else
    let &fileencodings = &fileencodings .','. s:enc_jis
    set fileencodings+=utf-8,ucs-2le,ucs-2
    if &encoding =~# '^\(euc-jp\|euc-jisx0213\|eucjp-ms\)$'
      set fileencodings+=cp932
      set fileencodings-=euc-jp
      set fileencodings-=euc-jisx0213
      set fileencodings-=eucjp-ms
      let &encoding = s:enc_euc
      let &fileencoding = s:enc_euc
    else
      let &fileencodings = &fileencodings .','. s:enc_euc
    endif
  endif
  " 定数を処分
  unlet s:enc_euc
  unlet s:enc_jis
endif
" 日本語を含まない場合は fileencoding に encoding を使うようにする
if has('autocmd')
  function! AU_ReCheck_FENC()
    if &fileencoding =~# 'iso-2022-jp' && search("[^\x01-\x7e]", 'n') == 0
      let &fileencoding=&encoding
    endif
  endfunction
  autocmd BufReadPost * call AU_ReCheck_FENC()
endif
" 改行コードの自動認識
set fileformats=unix,dos,mac
" □とか○の文字があってもカーソル位置がずれないようにする
if exists('&ambiwidth')
  set ambiwidth=double
endif
