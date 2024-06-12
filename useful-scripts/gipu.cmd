@echo off

SET fname=gibr_branch.tmp
git br --show-current>%fname%

set /p CurrentBranch=<%fname%

powershell Set-Clipboard "%CurrentBranch%"
del /F %fname%

echo %CurrentBranch%

git push -u origin %CurrentBranch%