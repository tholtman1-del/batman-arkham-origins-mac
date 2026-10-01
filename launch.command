#!/bin/zsh
# Batman: Arkham Origins on macOS (CrossOver) - launcher. Installed by install.command.
#
# Usage: launch.command [--dx9] [--fps]
#   (default) DX11 renderer on DXMT v0.80 + patched d3d11.dll (main version).
#   --dx9     DX9 renderer on patched DXVK 1.10.3 (backup; some floors can vanish for a few seconds and
#             the dripping-water effect is missing).
#   --fps     FPS overlay (Metal HUD in DX11, DXVK HUD in DX9).
# Environment: BMAO_ALLOW_PHYSX=1 keeps the game's PhysX setting (otherwise forced off: CPU PhysX under
# Rosetta drops the game to ~30 FPS). DXVK_D3D9_OCCLUSION_VISIBLE=1 fixes vanishing floors in DX9 (-30 FPS).
HERE=${0:A:h}
source "$HERE/lib/common.sh"
[[ -f $BMAO_CONFIG ]] || die "not installed - run install.command first"
source "$BMAO_CONFIG"

MODE=dx11 FPS=
for arg in "$@"; do
  case $arg in
    --dx9)  MODE=dx9 ;;
    --dx11) MODE=dx11 ;;
    --fps)  FPS=1 ;;
    *) die "unknown option: $arg" ;;
  esac
done

RUNTIME="$BMAO_HOME/runtime/CrossOver"
WINE="$RUNTIME/bin/wine"
[[ -x $WINE ]] || die "runtime missing - run install.command again"
CONF="$(bottles_dir)/$BOTTLE/cxbottle.conf"
[[ -f $CONF ]] || die "bottle not found: $BOTTLE - run install.command again"
[[ -d $GAME_DIR/SinglePlayer ]] || die "game folder not found: $GAME_DIR (external disk not connected?)"
if [[ -n $CX_APP && -d $CX_APP ]] && [[ $(crossover_version "$CX_APP") != $CX_VER ]]; then
  warn "CrossOver was updated ($CX_VER -> $(crossover_version "$CX_APP")). Run install.command again to refresh the runtime."
fi

# Game config (UTF-16 ini in the game folder; exists after the first start)
ENGINE_INI="$GAME_DIR/SinglePlayer/BMGame/Config/BmEngine.ini"
if [[ -f $ENGINE_INI ]]; then
  ini_set "$ENGINE_INI" SystemSettings AllowD3D11 $([[ $MODE == dx11 ]] && print True || print False)
  if [[ $BMAO_ALLOW_PHYSX != 1 ]]; then
    ini_set "$ENGINE_INI" SystemSettings PhysXLevel 0
    ini_set "$ENGINE_INI" SystemSettings PhysXLevelToSetOnRestart 0
  fi
fi

# Bottle settings for this mode. The previous values are restored on exit, so a shared bottle
# (e.g. a Steam bottle) keeps working for other programs.
typeset -A SAVED
for key in CX_GRAPHICS_BACKEND WINE_D3D_CONFIG WINEMSYNC; do SAVED[$key]=$(conf_get_env "$CONF" $key); done
restore_conf() {
  (( BOTTLE_CREATED )) && return
  for key in ${(k)SAVED}; do conf_set_env "$CONF" $key "${SAVED[$key]}"; done
}
trap restore_conf EXIT INT TERM
conf_set_env "$CONF" CX_GRAPHICS_BACKEND $([[ $MODE == dx11 ]] && print dxmt || print dxvk)
conf_set_env "$CONF" WINE_D3D_CONFIG "renderer=gl"   # renderer=no3d breaks character lighting in DX9
conf_set_env "$CONF" WINEMSYNC 1

export DXVK_ASYNC=${DXVK_ASYNC:-1}           # background pipeline compiles (DX9)
export DXMT_ASYNC_PSO=${DXMT_ASYNC_PSO:-1}   # background pipeline compiles (DX11)
export DXVK_LOG_LEVEL=${DXVK_LOG_LEVEL:-none}
if [[ -n $FPS ]]; then
  [[ $MODE == dx11 ]] && export MTL_HUD_ENABLED=1 || export DXVK_HUD=fps,frametimes
fi

print "Starting Batman: Arkham Origins ($([[ $MODE == dx11 ]] && print 'DX11 / DXMT' || print 'DX9 / DXVK'))..."
CX_DEBUGMSG=${CX_DEBUGMSG:--all} "$WINE" --bottle "$BOTTLE" \
  "${(U)DRIVE}:\\SinglePlayer\\Binaries\\Win32\\BatmanOrigins.exe" -nostartupmovies ${=BMAO_ARGS}
