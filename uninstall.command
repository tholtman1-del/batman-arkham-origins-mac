#!/bin/zsh
# Batman: Arkham Origins on macOS (CrossOver) - uninstaller.
# Restores the game DLLs, removes the drive mapping, the runtime copy and (if it was created by the
# installer and you agree) the bottle. The game itself and your saves stay untouched.
HERE=${0:A:h}
if [[ -f $HERE/lib/common.sh ]]; then source "$HERE/lib/common.sh"
else source "$HOME/Library/Application Support/BatmanAO-Mac/lib/common.sh" || exit 1; fi
[[ -f $BMAO_CONFIG ]] || die "nothing to uninstall ($BMAO_CONFIG missing)"
source "$BMAO_CONFIG"

ask "Uninstall the Batman: Arkham Origins Mac fix?" n || exit 0

MANIFEST="$BMAO_HOME/backups/game-dlls/manifest.txt"
if [[ -f $MANIFEST ]]; then
  while IFS= read -r dll; do
    backup="$BMAO_HOME/backups/game-dlls/${dll:t}"
    if [[ -f $backup && -d ${dll:h} ]]; then cp -p "$backup" "$dll" && info "restored ${dll:t}"
    else warn "could not restore $dll (game folder missing?)"; fi
  done < "$MANIFEST"
fi

BIN_DIR="$GAME_DIR/SinglePlayer/Binaries/Win32"
(( STEAM_APPID_CREATED )) && rm -f "$BIN_DIR/steam_appid.txt"

BOTTLE_DIR="$(bottles_dir)/$BOTTLE"
[[ -n $DRIVE && -L $BOTTLE_DIR/dosdevices/$DRIVE: ]] && rm -f "$BOTTLE_DIR/dosdevices/$DRIVE:"
if (( BOTTLE_CREATED )) && [[ -d $BOTTLE_DIR ]]; then
  if ask "Delete the bottle \"$BOTTLE\" (game settings/saves stored in it are lost)?" n; then
    "$CX_APP/Contents/SharedSupport/CrossOver/bin/cxbottle" --bottle "$BOTTLE" --delete --force >/dev/null 2>&1 \
      || rm -rf "$BOTTLE_DIR"
    info "bottle deleted"
  fi
fi

rm -f "$HOME/Desktop/Batman Arkham Origins (DX11).command" "$HOME/Desktop/Batman Arkham Origins (DX9 backup).command"
rm -rf "$BMAO_HOME"
info "Uninstalled."
