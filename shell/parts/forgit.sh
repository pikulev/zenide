export FORGIT_CHECKOUT_BRANCH_BRANCH_GIT_OPTS='--sort=-committerdate'

# forgit aliases:
# 
# ga – git add selector
# glo – git log viewer
# gi – .gitignore generator
# gd – git diff viewer
# grh – git reset HEAD <file> selector
# gcf – git checkout <file> selector
# gcb – git checkout <branch> selector
# gbd – git branch -D <branch> selector
# gct – git checkout <tag> selector
# gco – git checkout <commit> selector
# grc – git revert <commit> selector
# gss – git stash viewer
# gsp – git stash push selector
# gclean – git clean selector
# gcp – git cherry-pick selector
# grb – git rebase -i selector
# grl – git reflog viewer
# gbl – git blame selector
# gfu – git commit --fixup && git rebase -i --autosquash selector

# custom aliases:
# 
alias gs='git status -sb'
alias gl='git log --color --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
alias glb='git log --color --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit --branches'
alias gc='git commit'
alias gcm='git commit -m'
alias gus='git restore --staged'
alias guw='git restore --worktree'
alias gds='gd --staged'
alias glp='gl --follow -p --'
alias gda='files=($(git ls-files . --exclude-standard --others -m)); git add "${files[@]}" && gd --staged && git restore --staged "${files[@]}"'
alias gdah='files=($(git ls-files . --exclude-standard --others -m)); git add "${files[@]}" && diffh --staged && git restore --staged "${files[@]}"'
alias gfa='git fetch --all'