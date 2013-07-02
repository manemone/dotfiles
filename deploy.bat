rem @echo off

rem
rem Vim 設定ファイルを適切な位置に配置する。
rem Windows Vista 以降用。XP では動作しない。
rem 配置にはシンボリックリンクを用いる。
rem 必要な環境変数の設定等も行うため、管理者権限で実行すること。
rem

rem HOME 環境変数の設定
setx HOME %USERPROFILE%

rem このバッチが存在するフォルダをカレントに
pushd %0\..

rem 設定ファイルを配置
if exist %USERPROFILE%\.vimrc del %USERPROFILE%\.vimrc
mklink %USERPROFILE%\.vimrc .\.vimrc

if exist %USERPROFILE%\.vimrc.plugin del %USERPROFILE%\.vimrc.plugin
mklink %USERPROFILE%\.vimrc.plugin .\.vimrc.plugin

if exist %USERPROFILE%\.vim rmdir /s /q %USERPROFILE%\.vim
mklink /d %USERPROFILE%\.vim .\.vim
cls

pause
exit
