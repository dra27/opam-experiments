#!/bin/bash

# wrap-scripts.sh root looks for shell scripts (including symbolic links to shell scripts) and creates
# wrapper .cmd files for them

while IFS= read i ; do
  if head -1 "$i" | grep -q "^#!" ; then
    if [ ! -e $i.cmd ] ; then
      echo "Creating command script $i.cmd"
      cat > $i.cmd <<EOF
@bash -c '$i %*'
EOF
    fi
  fi
done < <(find $1 -type l -o -type f)
