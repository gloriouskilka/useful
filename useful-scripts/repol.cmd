REM SET LOCAL_GIT_REPOS=F:\Projects\Mine\_LocalGitRepos

set LocalRepoFolderName=%1.git

pushd "%LOCAL_GIT_REPOS%"
mkdir "%LocalRepoFolderName%"
cd "%LocalRepoFolderName%"
git init --bare
popd

git init .
git ci -m "Initial commit" --allow-empty

git remote add origin "%LOCAL_GIT_REPOS%\%LocalRepoFolderName%"
git push --set-upstream origin master
