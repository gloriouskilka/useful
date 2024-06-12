echo Creating branch %1

git checkout -b %1
git push --set-upstream origin %1

git status