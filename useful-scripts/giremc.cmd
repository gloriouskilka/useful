setlocal EnableDelayedExpansion

set ORIGIN=origin
if not "%1"=="" (
	set ORIGIN=%1
)


SET fname=repo_path.tmp
rm -f %fname%
REM git remote -v show -n origin > %fname%
git remote get-url %ORIGIN%>%fname%

set /p RemotePath=<%fname%

powershell Set-Clipboard "%RemotePath%"
del /F %fname%
