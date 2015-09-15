#!/bin/bash

# convert-symlinks.sh root looks for symbolic links in root and converts them to Windows native symlinks
# if they are in either of Cygwin's internal formats. Links to executables are guaranteed to have the required
# .exe ending for both the symlink and the target (meaning that a symlink'd executable is callable from CMD)

function relink {
  # Don't do anything with native symlinks if the target doesn't exist
  if [ -e "$(readlink -f $2)" ] ; then
    pushd `dirname "$2"` > /dev/null

    # Check to see if cmd thinks the file exists - if it doesn't, means it's a .exe
    TEST=$(cygpath -w "$1")
    if [ "$(cmd /c "if exist "$TEST" printf Y")Y" = "YY" ] ; then
      # Symlink contents should be fine for native too
      TARGET=$1
    else
      # Append .exe so that the command will work from cmd
      TARGET=$1.exe
    fi
    SOURCE=$2
    # If the target is a .exe, ensure that the source link has .exe
    if [ "${TARGET%.exe}" != "$TARGET" ] ; then
      if [ "${SOURCE%.exe}" = "$SOURCE" ] ; then
        SOURCE=$2.exe
      fi
    fi
    echo "Re-link $SOURCE -> $TARGET"

    popd > /dev/null

    # Always remove the original source!
    rm "$2"
    # Ensure that no mistakes have been made by creating the symlink using nativestrict
    CYGWIN="$CYGWIN winsymlinks:nativestrict" ln -s "$TARGET" "$SOURCE"
  fi
}

while IFS= read i ; do
  if [ ! "$i" = "$1" ] ; then
    COUNT=0
    TARGET=$(readlink "$i")

    # Ensure that the symlink type is correct
    pushd $(dirname "$i") > /dev/null
    while IFS= read j ; do
      if [ $COUNT -eq 0 ] ; then
        COUNT=1
        TYPE=$(echo $j| sed -e "s/.*<\([^>]*\)>.*/\1/")
        case $TYPE in
          "JUNCTION" | "SYMLINKD")
            if [ -f "$TARGET" ] ; then
              relink "$TARGET" "$i"
            fi
          ;;
          "SYMLINK")
            if [ -d "$TARGET" ] ; then
              relink "$TARGET" "$i"
            fi
          ;;
        esac
      else
        if [ $COUNT -eq 1 ] ; then
          echo Unexpected duplicate results for "$i">&2
        else
          COUNT=2
        fi
      fi
    done < <(cmd /c dir /a | fgrep " `basename "$i"` [")
    popd > /dev/null

    # The symbolic link is not a native one
    if [ $COUNT -eq 0 ] ; then
      relink "$TARGET" "$i"
    fi
  fi
done < <(find $1 \( -path "/cygdrive" -o -path "/proc" -o -path "/dev" \) -prune -o \( -type l -print \) )
