# .zshrc

export LOCAL_GIT_REPOS="$HOME/.localGitRepos"

if [[ ! -d "$LOCAL_GIT_REPOS" ]]; then
  mkdir -p "$LOCAL_GIT_REPOS"
fi

# Creating branch
alias crbr='f() { echo "Creating branch $1"; git checkout -b $1; git push --set-upstream origin $1; git status; };f'

# Creating local branch
alias crbrl='f() { echo "Creating local branch $1"; git checkout -b $1; git branch --set-upstream-to origin/$1; git status; };f'

# Git add all
alias gia='git add .'

# Git add patch
alias giap='git add . -p'

# Show current branch
alias gibr='git rev-parse --abbrev-ref HEAD'

# Copy current branch to clipboard
alias gibrc='git rev-parse --abbrev-ref HEAD | pbcopy'

# Git clean
alias gic='git clean -df'

# Git commit --amend
alias gica='git commit --amend'

# Git commit
alias gici='f() { git commit -m "$*"; };f'

# Git commit --amend with message
alias gicia='f() { git commit --amend -m "$*"; };f'

# Git commit --amend with message and push
alias giciap='f() { git commit --amend -m "$*"; git push; };f'

# Git clone with submodules
alias gicl='f() { git clone --recurse-submodules "$1" "$2"; };f'

# Git cherry-pick
alias gicp='f() { git cherry-pick $1; };f'

# Git diff
alias gid='git diff .'

# Git diff HEAD^^
alias gidh='git diff HEAD^^ .'

# Git diff --staged
alias gids='git diff --staged .'

# Git fetch
alias gif='git fetch --all --prune'

# Git log
alias gils='f() { git log --stat $1; };f'

# Git push
alias gip='git push'

# Git force push
alias gipf='git push -f'

# Git push with upstream
alias gipu='cbranch=$(git rev-parse --abbrev-ref HEAD) && git push -u origin $cbranch'

# Git reset
alias gir='f() { git reset $*; };f'

# Git rebase continue
alias girec='git rebase --continue'

# Git remote -v
alias girem='git remote -v'

# Git remote -v to clipboard
function giremc() {
  local ORIGIN="origin"
  if [[ ! -z "$1" ]]; then
    ORIGIN="$1"
  fi
  git remote get-url $ORIGIN | pbcopy
}

# Git reset --hard
alias girh='git reset --hard HEAD^^'

# Git reset --hard, clean
alias girl='f() { git reset --hard $1 --; git clean -df };f'

# Git reset --hard clean with -x
alias girls='f() { git reset --hard $1 --; git clean -dfx };f'

# Git status
alias gis='git status '

# Git stash
alias giss='f() { git stash save $*; };f'

# Git pull and sync submodules
alias pull_with_submodules='git pull; git submodule sync --recursive; git submodule update --init --recursive'

# Git sync submodules
alias sync_submodules='git submodule sync --recursive; git submodule update --init --recursive'

# Git initialize repo
alias repo='git init .; git commit -m "Initial commit" --allow-empty'

# Git remove both local and remote branch
alias rmbr='f() { while true; do read "REPLY?Going to remove local AND REMOTE branch $1. Continue[Y/N]? "; case $REPLY in y*|Y*) git branch -D $1; git push origin :$1; break;; n*|N*) echo "exiting"; exit;; esac; done; };f'

alias repol='noglob _repol'
_repol() {
  local LocalRepoFolderName="$1.git"
  pushd "$LOCAL_GIT_REPOS"
  mkdir "$LocalRepoFolderName"
  cd "$LocalRepoFolderName"
  git init --bare
  popd
  git init .
  git commit --allow-empty -m "Initial commit"
  git remote add origin "$LOCAL_GIT_REPOS/$LocalRepoFolderName"
  git push --set-upstream origin master
}
