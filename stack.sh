#!/usr/bin/env bash
# ################################################################################################ #
# Copyright (c) 2019 MetaStack Solutions Ltd. See distribution terms at the end of this file.      #
# David Allsopp. 16-Jun-2019                                                                       #
# ################################################################################################ #

# Patch stacking script

set -e

declare -A BRANCHES
BRANCHES=(
  ['windows-testsuite']='(
    ["BRANCHES"]="(windows-filenames crlf-hashing patch-rewrite-tests)"
    ["NAMES"]="('"'PR#3350' 'PR#3407' 'PR#3456'"')"
    ["COMMITS"]="windows-testing")'
  ['windows-stack']='(
    ["BRANCHES"]="(windows-filenames patch-rewrite-tests windows-testing fix-licence)"
    ["NAMES"]="('"'PR#3350' 'PR#3456' 'PR#3260' 'PR#3863'"')")'
)

# Conflict resolution settings
setting=$(git config rerere.enabled || true)
if [[ $setting != 'true' ]] ; then
  echo 'Setting rerere.enabled to true'
  git config rerere.enabled true
fi
setting=$(git config rerere.autoUpdate || true)
if [[ $setting != 'true' ]] ; then
  echo 'Setting rerere.autoUpdate to true'
  git config rerere.autoUpdate true
fi
setting=$(git config gc.rerereResolved || true)
if [[ $setting = '60' ]] ; then
  echo 'Setting gc.rerereResolved to 16400'
  git config gc.rerereResolved 16400
fi

if [[ ! -d .git ]] ; then
  echo 'In a worktree or not at root directory' >&2
  exit 1
fi

prepared=0

if [[ -e .git/opamstack ]] ; then
  . .git/opamstack
else
  phase=1
fi

declare -a branches
declare -A CURRENT
branches=("${!BRANCHES[@]}")

while [[ $phase -ne 0 ]] ; do
  if [[ $phase -ne 1 ]] ; then
    echo "phase=$phase" >> .git/opamstack
  fi
  case $phase in
    1)
      # Begin the process

      if ! git diff-index --quiet HEAD ; then
        echo 'Cannot proceed with uncommitted changes' >&2
        exit 1
      fi

      # Must be on a branch
      branch=$(git rev-parse --abbrev-ref HEAD)
      if [[ $branch = 'HEAD' ]] ; then
        echo 'Cannot determine branch; or in detached HEAD state' >&2
        exit 1
      fi

      # Must not be on the working branch
      if [[ $branch = 'opamstack-working' ]] ; then
        echo 'Cannot be on opamstack-working (it will be deleted)' >&2
        echo 'Switch to another branch first' >&2
        exit 1
      fi

      # Cannot be on a branch we're updating, so detach
      if [[ -n ${BRANCHES[$branch]} ]] ; then
        git checkout $(git rev-parse HEAD)
      fi

      echo 'Syncing with upstream'
      git fetch upstream

      echo "Will return to $branch on completion"
      echo "branch='$branch'" > .git/opamstack

      git branch -D opamstack-working &> /dev/null || true

      phase=2
      ;;
    2)
      target="${branches[$prepared]}"
      if [[ -z $target ]] ; then
        phase=999
      else
        git branch -D "$target" &> /dev/null || true

        git branch "$target" upstream/master
        merged=0
        echo "target='$target'" >> .git/opamstack
        echo "merged=0" >> .git/opamstack

        phase=3
      fi
      ;;
    3)
      # Begin stacking a branch
      eval CURRENT=${BRANCHES[${branches[$prepared]}]}
      eval merge="${CURRENT['BRANCHES']}"
      eval merge_name="${CURRENT['NAMES']}"
      merge="${merge[$merged]}"
      merge_name="${merge_name[$merged]}"
      if [[ -z $merge ]] ; then
        commits=${CURRENT['COMMITS']}
        if [[ -z $commits ]] ; then
          phase=9
        else
          rebase_return=8
          echo "rebase_return=8" >> .git/opamstack
          phase=7
        fi
      else
        echo "merge='$merge'" >> .git/opamstack
        echo "merge_name='$merge_name'" >> .git/opamstack
        echo "rebase_return=6" >> .git/opamstack
        rebase_return=6
        git checkout -b opamstack-working "$merge"
        phase=4
      fi
      ;;
    4)
      if git rebase --rerere-autoupdate "$target" ; then
        phase=6
      else
        phase=5
      fi
      ;;
    5)
      # It doesn't seem to be possible to persuade git rebase to continue
      # if rerere was able to stage a completely resolved patch, so attempt
      # one --continue knowing that this will fail if there were definitely
      # conflicts still to resolve.
      if [[ -z $(git ls-files --unmerged) ]] ; then
        if git rebase --continue ; then
          phase=$rebase_return
        fi
      else
        exit 2
      fi
      ;;
    6)
      git reset --soft "$target"
      git commit -m "$merge_name"
      git checkout "$target"
      git merge --ff-only opamstack-working
      git branch -D opamstack-working
      ((merged+=1))
      echo "merged=$merged" >> .git/opamstack
      phase=3
      ;;
    7)
      git checkout -b opamstack-working "$commits"
      if git rebase --rerere-autoupdate --committer-date-is-author-date "$target" ; then
        phase=8
      else
        phase=5
      fi
      ;;
    8)
      git checkout "$target"
      git merge --ff-only opamstack-working
      git branch -D opamstack-working
      phase=9
      ;;
    9)
      ((prepared+=1))
      echo "prepared=$prepared" >> .git/opamstack
      phase=2
      ;;
    999)
      # Success - restore previous branch
      echo "Process complete - returning to $branch"
      rm -f .git/opamstack
      git checkout "$branch"
      phase=0
      ;;
    *)
      echo "Unknown phase: $phase"
      exit 1
      ;;
  esac
done

# ################################################################################################ #
# Redistribution and use in source and binary forms, with or without modification, are permitted   #
# provided that the following conditions are met:                                                  #
#     1. Redistributions of source code must retain the above copyright notice, this list of       #
#        conditions and the following disclaimer.                                                  #
#     2. Redistributions in binary form must reproduce the above copyright notice, this list of    #
#        conditions and the following disclaimer in the documentation and/or other materials       #
#        provided with the distribution.                                                           #
#     3. Neither the name of MetaStack Solutions Ltd. nor the names of its contributors may be     #
#        used to endorse or promote products derived from this software without specific prior     #
#        written permission.                                                                       #
#                                                                                                  #
# This software is provided by the Copyright Holder 'as is' and any express or implied warranties, #
# including, but not limited to, the implied warranties of merchantability and fitness for a       #
# particular purpose are disclaimed. In no event shall the Copyright Holder be liable for any      #
# direct, indirect, incidental, special, exemplary, or consequential damages (including, but not   #
# limited to, procurement of substitute goods or services; loss of use, data, or profits; or       #
# business interruption) however caused and on any theory of liability, whether in contract,       #
# strict liability, or tort (including negligence or otherwise) arising in any way out of the use  #
# of this software, even if advised of the possibility of such damage.                             #
# ################################################################################################ #
