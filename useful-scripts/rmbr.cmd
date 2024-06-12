@ECHO OFF

if "%2"=="" (
goto :choice
) else (
echo Going to remove local AND REMOTE branch "%1"
git branch -D %1
git push origin :%1
exit
)

:choice
echo Going to remove local AND REMOTE branch "%1"
set /P c=Continue[Y/N]?
if /I "%c%" EQU "Y" goto :rm_branch
if /I "%c%" EQU "N" goto :skip_exit
goto :choice

:rm_branch
echo "Removing branch"

git branch -D %1
git push origin :%1
pause

git st
git lg

exit

:skip_exit
echo exiting
exit

