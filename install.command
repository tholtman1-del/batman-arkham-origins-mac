#!/bin/zsh
# Batman: Arkham Origins on macOS (CrossOver) - installer.
#
# Usage: ./install.command [--game "/path/to/Batman Arkham Origins"] [--bottle "Existing Bottle Name"]
#
# Without options it asks for the game folder (GOG or Steam copy, any disk) and creates a dedicated
# CrossOver bottle. Use --bottle to run the game in an existing bottle instead (for example the bottle
# where Steam is installed, if the Steam version refuses to start without the Steam client).
#
# What it does (nothing inside CrossOver.app is modified):
#   1. Clones CrossOver's Wine runtime into ~/Library/Application Support/BatmanAO-Mac/runtime
#      (APFS clone: instant and takes no extra space on the same disk).
#   2. Puts the patched DXVK d3d9.dll (DX9 mode) and DXMT v0.80 + patched d3d11.dll (DX11 mode) into it.
#   3. Sets the NX_COMPAT flag on game DLLs that lack it (originals backed up), which fixes extremely
#      slow loading screens.
#   4. Creates the bottle (or uses yours), maps the game folder to a drive letter, writes launchers.
set -e
PKG=${0:A:h}
source "$PKG/lib/common.sh"

GAME_ARG= BOTTLE_ARG=
while (( $# )); do
  case $1 in
    --game)   GAME_ARG=$2; shift ;;
    --bottle) BOTTLE_ARG=$2; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

print -P "%BBatman: Arkham Origins for macOS - installer%b\n"

# --- checks -----------------------------------------------------------------------------------------
[[ $(uname -m) == arm64 ]] || warn "Only tested on Apple Silicon Macs."
CX_APP=$(find_crossover) || die "CrossOver.app not found. Install CrossOver, or set CROSSOVER_APP=/path/to/CrossOver.app"
CX_VER=$(crossover_version "$CX_APP")
info "CrossOver $CX_VER at $CX_APP"
if [[ ${CX_VER%%.*} != 26 ]]; then
  warn "This package was built and tested with CrossOver 26.3. Other versions may not work."
  ask "Continue anyway?" n || exit 1
fi

# --- game folder ------------------------------------------------------------------------------------
find_game_root() {   # accepts the game folder or any folder inside it
  local d=${1:A}
  while [[ $d != / ]]; do
    [[ -f $d/SinglePlayer/Binaries/Win32/BatmanOrigins.exe ]] && { print -r -- "$d"; return 0; }
    d=${d:h}
  done
  local hit=$(find "${1:A}" -maxdepth 5 -path "*SinglePlayer/Binaries/Win32/BatmanOrigins.exe" 2>/dev/null | head -1)
  [[ -n $hit ]] && { print -r -- "${hit:h:h:h:h}"; return 0; }
  return 1
}

GAME_DIR=
if [[ -n $GAME_ARG ]]; then
  GAME_DIR=$(find_game_root "$GAME_ARG") || die "BatmanOrigins.exe not found under: $GAME_ARG"
else
  print "Where is the game installed? Drag the game folder (the one containing \"SinglePlayer\") into"
  print "this window and press Return. Examples:"
  print "  GOG in CrossOver:   ~/Library/Application Support/CrossOver/Bottles/<bottle>/drive_c/Program Files (x86)/GOG Galaxy/Games/Batman Arkham Origins"
  print "  Steam in CrossOver: ~/Library/Application Support/CrossOver/Bottles/<bottle>/drive_c/Program Files (x86)/Steam/steamapps/common/Batman Arkham Origins"
  print "  External disk:      /Volumes/<disk>/Games/Batman Arkham Origins"
  while [[ -z $GAME_DIR ]]; do
    read -r "input?Game folder: "
    input=${input%%[[:space:]]}; input=${input//\\ / }; input=${input#\'}; input=${input%\'}
    input=${input/#\~/$HOME}
    GAME_DIR=$(find_game_root "$input") || { warn "BatmanOrigins.exe not found there, try again."; GAME_DIR=; }
  done
fi
BIN_DIR="$GAME_DIR/SinglePlayer/Binaries/Win32"
STORE=GOG
[[ -f $BIN_DIR/steam_api.dll ]] && STORE=Steam
info "Game ($STORE version): $GAME_DIR"
[[ -w $BIN_DIR ]] || die "No write access to $BIN_DIR"

# --- runtime clone ------------------------------------------------------------------------------------
mkdir -p "$BMAO_HOME/backups/game-dlls"
RUNTIME="$BMAO_HOME/runtime/CrossOver"
if [[ -d $RUNTIME ]]; then
  info "Removing previous runtime copy"
  rm -rf "$BMAO_HOME/runtime"
fi
mkdir -p "$BMAO_HOME/runtime"
info "Copying CrossOver's Wine runtime (APFS clone if possible)"
cp -cR "$CX_APP/Contents/SharedSupport/CrossOver" "$BMAO_HOME/runtime/" 2>/dev/null \
  || { warn "APFS clone not possible (different disk), doing a full copy (~1 GB)"; rm -rf "$BMAO_HOME/runtime/CrossOver"; cp -R "$CX_APP/Contents/SharedSupport/CrossOver" "$BMAO_HOME/runtime/"; }
print -r -- "$CX_VER" > "$BMAO_HOME/runtime/crossover-version"

# --- payload: DXVK d3d9 (DX9 mode) ------------------------------------------------------------------
(cd "$PKG/payload" && shasum -a 256 -c SHA256SUMS >/dev/null) || die "payload checksum mismatch - download the package again"
DXVK_DIR="$RUNTIME/lib/dxvk/i386-windows"
[[ -d $DXVK_DIR ]] || die "unexpected CrossOver layout: $DXVK_DIR missing"
cp "$PKG/payload/d3d9.dll" "$DXVK_DIR/d3d9.dll"

# --- payload: DXMT v0.80 + patched d3d11.dll (DX11 mode) ------------------------------------------------
DXMT_TGZ="$BMAO_HOME/dxmt-$DXMT_VERSION-builtin.tar.gz"
if [[ ! -f $DXMT_TGZ ]] || [[ $(shasum -a 256 "$DXMT_TGZ" | cut -d' ' -f1) != $DXMT_SHA256 ]]; then
  info "Downloading DXMT $DXMT_VERSION from GitHub"
  curl -fL --progress-bar -o "$DXMT_TGZ" "$DXMT_URL" || die "download failed: $DXMT_URL"
fi
[[ $(shasum -a 256 "$DXMT_TGZ" | cut -d' ' -f1) == $DXMT_SHA256 ]] || die "DXMT archive checksum mismatch"
rm -rf "$RUNTIME/lib/dxmt.crossover"
mv "$RUNTIME/lib/dxmt" "$RUNTIME/lib/dxmt.crossover"
mkdir -p "$RUNTIME/lib/dxmt"
tar xzf "$DXMT_TGZ" -C "$RUNTIME/lib/dxmt" --strip-components 1
cp "$PKG/payload/d3d11.dll" "$RUNTIME/lib/dxmt/i386-windows/d3d11.dll"

xattr -dr com.apple.quarantine "$BMAO_HOME/runtime" 2>/dev/null || true
codesign -s - -f "$RUNTIME/lib/dxmt/x86_64-unix/winemetal.so" >/dev/null 2>&1 || warn "could not sign winemetal.so"

# NX flag on the runtime's own Direct3D DLLs that lack it
for dll in "$DXVK_DIR"/*.dll "$RUNTIME"/lib/dxmt/i386-windows/*.dll; do
  [[ $(pe_nx_status "$dll") == no-nx ]] && pe_set_nx "$dll"
done

# --- game DLLs: NX flag (with backups) -------------------------------------------------------------------
MANIFEST="$BMAO_HOME/backups/game-dlls/manifest.txt"
touch "$MANIFEST"
patched=0
for dll in "$BIN_DIR"/*.dll(N); do
  if [[ $(pe_nx_status "$dll") == no-nx ]]; then
    backup="$BMAO_HOME/backups/game-dlls/${dll:t}"
    [[ -f $backup ]] || cp -p "$dll" "$backup"
    grep -qxF -- "$dll" "$MANIFEST" || print -r -- "$dll" >> "$MANIFEST"
    pe_set_nx "$dll"
    (( ++patched ))
  fi
done
info "NX_COMPAT set on $patched game DLL(s) (originals in $BMAO_HOME/backups/game-dlls)"

STEAM_APPID_CREATED=0
if [[ $STORE == Steam && ! -f $BIN_DIR/steam_appid.txt ]]; then
  print 209000 > "$BIN_DIR/steam_appid.txt"
  STEAM_APPID_CREATED=1
  info "Steam version: created steam_appid.txt (lets the exe start outside the Steam client)"
fi

# --- bottle -------------------------------------------------------------------------------------------
CXBOTTLE="$CX_APP/Contents/SharedSupport/CrossOver/bin/cxbottle"
BOTTLE=${BOTTLE_ARG:-$BMAO_DEFAULT_BOTTLE}
BOTTLE_DIR="$(bottles_dir)/$BOTTLE"
BOTTLE_CREATED=0
if [[ -d $BOTTLE_DIR ]]; then
  info "Using existing bottle: $BOTTLE"
else
  [[ -n $BOTTLE_ARG ]] && die "bottle not found: $BOTTLE"
  info "Creating bottle: $BOTTLE (takes a minute)"
  "$CXBOTTLE" --bottle "$BOTTLE" --create --template win10_64 --description "Batman: Arkham Origins (BatmanAO-Mac)" >/dev/null \
    || die "bottle creation failed"
  BOTTLE_CREATED=1
fi
CONF="$BOTTLE_DIR/cxbottle.conf"
[[ -f $CONF ]] || die "missing $CONF"
cp -p "$CONF" "$BMAO_HOME/backups/cxbottle.conf.before-install" 2>/dev/null || true
# Settings only for a dedicated bottle; a shared bottle gets them per launch and restored afterwards.
if (( BOTTLE_CREATED )); then
  conf_set_env "$CONF" WINEMSYNC 1
  conf_set_env "$CONF" WINE_D3D_CONFIG "renderer=gl"
  conf_set_env "$CONF" CX_GRAPHICS_BACKEND dxmt
fi

# Drive letter for the game folder (works for any path, including external disks)
DOSDEV="$BOTTLE_DIR/dosdevices"
DRIVE=
for l in g h i j k l m n o p q r s t u v w x; do
  [[ -L $DOSDEV/$l: && ${$(readlink "$DOSDEV/$l:"):A} == ${GAME_DIR:A} ]] && { DRIVE=$l; break; }
done
if [[ -z $DRIVE ]]; then
  for l in g h i j k l m n o p q r s t u v w x; do
    [[ -e $DOSDEV/$l: || -L $DOSDEV/$l: ]] || { DRIVE=$l; break; }
  done
  [[ -n $DRIVE ]] || die "no free drive letter in $DOSDEV"
  ln -s "$GAME_DIR" "$DOSDEV/$DRIVE:"
fi
info "Game folder mapped to ${(U)DRIVE}: in the bottle"

# --- config + launchers ----------------------------------------------------------------------------------
{
  print -r -- "# Written by install.command - $(date)"
  print -r -- "CX_APP=${(q)CX_APP}"
  print -r -- "CX_VER=${(q)CX_VER}"
  print -r -- "GAME_DIR=${(q)GAME_DIR}"
  print -r -- "STORE=$STORE"
  print -r -- "BOTTLE=${(q)BOTTLE}"
  print -r -- "BOTTLE_CREATED=$BOTTLE_CREATED"
  print -r -- "DRIVE=$DRIVE"
  print -r -- "STEAM_APPID_CREATED=$STEAM_APPID_CREATED"
} > "$BMAO_CONFIG"

cp "$PKG/launch.command" "$BMAO_HOME/launch.command"
cp "$PKG/uninstall.command" "$BMAO_HOME/uninstall.command"
mkdir -p "$BMAO_HOME/lib"; cp "$PKG/lib/common.sh" "$BMAO_HOME/lib/common.sh"
chmod +x "$BMAO_HOME/launch.command" "$BMAO_HOME/uninstall.command"

make_shortcut() {   # make_shortcut FILE ARGS...
  local file=$1; shift
  print -r -- "#!/bin/zsh" > "$file"
  print -r -- "exec ${(q)BMAO_HOME}/launch.command $*" >> "$file"
  chmod +x "$file"
}
make_shortcut "$BMAO_HOME/Batman Arkham Origins (DX11).command"
make_shortcut "$BMAO_HOME/Batman Arkham Origins (DX9 backup).command" --dx9
if ask "Put the two launchers on your Desktop?" y; then
  cp "$BMAO_HOME/Batman Arkham Origins (DX11).command" "$BMAO_HOME/Batman Arkham Origins (DX9 backup).command" "$HOME/Desktop/"
fi

print
info "Done. Start the game with \"Batman Arkham Origins (DX11).command\" (main) or the DX9 backup."
print "  Launchers and uninstaller: $BMAO_HOME"
print "  In the game's graphics options keep Hardware Accelerated PhysX OFF and Geometry Detail on Normal."
[[ $STORE == Steam ]] && print "  Steam version: if the game asks for Steam, re-run with --bottle \"<bottle with Steam>\" and start Steam there first."
