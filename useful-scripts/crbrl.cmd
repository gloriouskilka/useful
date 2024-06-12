echo Creating local branch %1

git checkout -b %1
git br --set-upstream-to origin/%1

git status