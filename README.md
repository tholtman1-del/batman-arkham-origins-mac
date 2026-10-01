# Batman: Arkham Origins on Apple Silicon Macs (CrossOver)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/F2J527ZLUN)

This package makes Batman: Arkham Origins (GOG or Steam, the 32-bit Windows game) run well in
[CrossOver](https://www.codeweavers.com/crossover) on Apple Silicon Macs. It includes a DirectX 11
version and a DirectX 9 backup.

Test result: M1 Pro, CrossOver 26.3, macOS 27, 1920×1200, high settings, in-game benchmark:

| Mode | Min FPS | Avg FPS | Notes |
|---|---|---|---|
| **DX11 (main)** | 52–56 | 110 | DX11 effects, no known glitches |
| DX9 (backup) | ~74 | ~125 | some floors vanish briefly, dripping-water effect missing |

Without this package the game takes about 5 minutes to reach the menu, and every loading screen runs
at 1–3 FPS.

## What was wrong and how it is fixed

Each problem below is listed with what you see, the cause, and the fix in this package.

### 1. Gray screen crash at startup

**What you see:** the game window stays gray, and then the Wine debugger appears. The game never
reaches the menu.

**Cause:** Arkham Origins is a **32-bit** game. CrossOver's best DirectX 11 layer, Apple's D3DMetal,
only supports 64-bit programs, so for this game CrossOver falls back to Wine's own DirectX 11 layer
(running on Vulkan). That layer cannot create one texture format the game needs at startup
(`R32G32B32_FLOAT`), so texture creation fails. The game keeps going with an empty texture, crashes,
and then its own crash reporter crashes as well, which leaves the gray window and the debugger.

**Fix:** the game runs on a translation layer that does support 32-bit games:

- **DX11 mode:** [DXMT](https://github.com/3Shain/dxmt), which translates DirectX 11 directly to Metal.
- **DX9 mode:** DXVK, which translates DirectX 9 to Vulkan, and then MoltenVK to Metal.

### 2. Very slow loading (5 minutes to the menu)

**What you see:** every loading screen crawls at 1–3 FPS. The menu takes about 5 minutes, and some
loading screens only continue after you switch to another window and back.

**Cause:** six of the game's DLLs (libcurl, libeay32/ssleay32 (OpenSSL), PhysXExtensions, the CUDA
runtime and libresample) are old enough to lack the `NX_COMPAT` flag. When a program loads such a DLL,
Wine plays it safe and makes **all** of the program's memory read-write-execute. Under Rosetta (the
game is x86 code on an ARM Mac), writing to memory that is also executable is very expensive, because
Rosetta must check whether code was modified. The graphics layer writes to memory constantly while
loading, so loading slows to a crawl.

**Fix:** the installer sets the `NX_COMPAT` flag in those DLLs, which changes one bit in each file
header. Nothing else in the files changes, and the originals are backed up and restored by the
uninstaller. Loading screens now take seconds.

### 3. DX11 was a slideshow, and stutter on camera turns

**What you see:** with CrossOver's own DXMT, version 0.72, the DX11 version runs at a few FPS. After
updating DXMT it runs well, but drops to 30–40 FPS when you turn the camera quickly.

**Fix:**

- DXMT is updated to **v0.80**, the official release, downloaded at install time and verified by
  checksum.
- Its `d3d11.dll` is patched. When the game shows something new, DXMT has to compile a Metal
  "pipeline" for it, and DXMT normally freezes the frame until that compile is done. With the patch,
  those draws are skipped for a moment while the pipeline compiles in the background, so the camera
  stays smooth.
- The patch also fixes a crash in that code path.

### 4. DX9: broken shadows and lighting, stutter

**What you see:** with CrossOver's DXVK, characters and scenes have broken lighting, and the game
stutters for 150–190 ms whenever a new effect appears.

**Cause:** for shadows, the game samples the same depth texture in two ways (as a normal texture and
as a "shadow" texture). DXVK binds both views to one slot, which Vulkan allows but Metal (through
MoltenVK) does not, so those shaders fail. The stutter comes from shader pipelines compiling while
the game waits.

**Fix:** DXVK's `d3d9.dll` is patched:

- The shadow comparison is computed inside the shader, so only one texture binding is needed.
- Pipelines compile in the background instead of blocking the game.
- It keeps more upload memory cached.

### 5. PhysX

"Hardware Accelerated PhysX" needs an NVIDIA GPU. On a Mac it runs on the CPU, under Rosetta, and the
game drops to about 30 FPS with 4 FPS minimums. The launcher turns it off on every start (see
[Recommended in-game settings](#recommended-in-game-settings)).

## Requirements

- Apple Silicon Mac (tested on M1 Pro)
- CrossOver 26.x (tested on 26.3), installed and licensed. It is not included here.
- Your own copy of Batman: Arkham Origins from GOG or Steam. The game can be installed anywhere,
  including in a CrossOver bottle, any folder, or an external disk.
- An internet connection during installation (DXMT is downloaded from GitHub).

## Install

1. Install the game. For example, install GOG Galaxy or Steam in a CrossOver bottle and download the
   game there, or copy an existing installation to any folder.
2. Download this repository and open Terminal in its folder.
3. Run:
   ```
   ./install.command
   ```
   When it asks for the game folder, drag the folder that contains `SinglePlayer` into the Terminal
   window and press Return. You can also pass the path directly:
   `./install.command --game "/Volumes/Games/Batman Arkham Origins"`.
4. Start the game with the **"Batman Arkham Origins (DX11)"** launcher on your Desktop. Both launchers
   are also in `~/Library/Application Support/BatmanAO-Mac`.

You can also run the launcher from Terminal:
```
~/Library/Application\ Support/BatmanAO-Mac/launch.command          # DX11 (main)
~/Library/Application\ Support/BatmanAO-Mac/launch.command --dx9    # DX9 backup
~/Library/Application\ Support/BatmanAO-Mac/launch.command --fps    # with FPS overlay
```

### Recommended in-game settings

- **Hardware Accelerated PhysX: OFF.** There is no NVIDIA GPU, so PhysX would run on the CPU under
  Rosetta and drop the game to about 30 FPS. The launcher turns it off on every start; set
  `BMAO_ALLOW_PHYSX=1` to keep your own choice.
- **Geometry Detail: Normal.** "DX11 Enhanced" uses tessellated snow, which renders as stray
  triangles on Apple GPUs.
- Everything else, including the DX11 Enhanced shadows, depth of field and ambient occlusion, works.
  FXAA High costs almost nothing.

### Steam version

The installer adds `steam_appid.txt` (app id 209000) so the game can start outside the Steam client.
If the game still asks for Steam, run the installer again and point it at the bottle where Steam is
installed:
```
./install.command --bottle "Steam"
```
Then start Steam in that bottle before using the launcher. The launcher changes that bottle's graphics
settings only while the game runs and restores them afterwards.

The Steam version has not been tested. Please report your results.

## What it changes

Nothing inside `CrossOver.app` is modified, and your other bottles are left alone.

1. **Private runtime.** CrossOver's Wine runtime is cloned to
   `~/Library/Application Support/BatmanAO-Mac/runtime`. On the same disk this is an instant APFS clone
   and uses no extra space. The clone gets:
   - `lib/dxvk/i386-windows/d3d9.dll`: DXVK 1.10.3 (CrossOver's version), patched. Depth-compare
     samplers are emulated in the shader, because Metal can't bind two textures to one slot, so the
     original shows broken shadows and lighting. Shader pipelines compile in the background, so there
     are no camera hitches. Memory handling is improved.
   - `lib/dxmt`: [DXMT](https://github.com/3Shain/dxmt) v0.80, the official release downloaded at
     install time and verified by checksum. Its `d3d11.dll` is patched so encoding doesn't wait for
     pipelines that are still compiling. CrossOver 26.3 ships DXMT 0.72, which is unplayably slow with
     this game.
2. **NX_COMPAT flag on game DLLs.** Some of the game's DLLs (libcurl, OpenSSL, PhysX, CUDA runtime,
   ...) lack this flag. When one of them loads, Wine makes all of the game's memory
   read-write-execute. Under Rosetta, every write to such memory then traps, which is the cause of the
   extremely slow loading. The installer sets the flag and backs up the originals in
   `~/Library/Application Support/BatmanAO-Mac/backups`.
3. **Bottle.** The installer creates a bottle "Batman Arkham Origins (Mac)" (Windows 10, msync on) and
   maps the game folder to a drive letter in it. This is how any path or external disk works.
4. **Game config.** The launcher sets `AllowD3D11` in `BMGame/Config/BmEngine.ini` to match the chosen
   mode, and forces PhysX off.

## Uninstall

```
~/Library/Application\ Support/BatmanAO-Mac/uninstall.command
```
This restores the original game DLLs and removes the drive mapping, the runtime copy and the launchers.
It also offers to delete the bottle. The game itself is not touched.

## Known issues

- **DX11:** occasional short stutter on very fast camera turns. These are CPU-bound frames, because the
  32-bit game runs under Rosetta.
- **DX11:** Geometry Detail "DX11 Enhanced" (snow tessellation) renders the snow wrong. Use Normal.
- **DX9:** some floors or objects disappear for a few seconds. Occlusion queries return 0 on
  CrossOver's MoltenVK. `DXVK_D3D9_OCCLUSION_VISIBLE=1` works around it at about −30 FPS.
- **DX9:** the dripping-water particle effect is missing.
- Do not use the `-NoTextureStreaming` game option: all textures turn black (a game bug in every
  renderer).
- **After a CrossOver update,** run `install.command` again so the runtime copy matches. The launcher
  warns you.

## Building the patched DLLs yourself

`patches/` contains the source changes:

- `dxvk-1.10.3-crossover-26.3.patch`: against the `dxvk` folder of the CrossOver 26.3.0 source
  package (`crossover-sources-26.3.0.tar.gz` from codeweavers.com). Build it 32-bit with
  meson/mingw (`build-win32.txt`, `-Denable_dxgi=false -Denable_d3d10=false -Denable_d3d11=false`,
  `-Dcpp_args="-include cstdint"`).
- `dxmt-v0.80-async-pso.patch`: against DXMT tag `v0.80` (commit 589adb7). Build it 32-bit with
  `meson --cross-file build-win32.txt`, `-Dcpp_args="-include iomanip -include cstdint"`.

Both DLLs carry Wine's "builtin" marker ("Wine builtin DLL" at file offset 0x40). `payload/SHA256SUMS`
lists the checksums of the shipped binaries. The patches also contain diagnostic switches, which are all
off by default.

## Licenses

- DXVK: zlib/libpng license, see `licenses/DXVK-LICENSE`.
- DXMT: MIT license, see `licenses/DXMT-LICENSE`.
- The scripts in this repository: MIT.

## Credits

Made by Tibor Holtman together with Claude Code (an AI coding assistant): Claude traced the problems,
wrote the patches and the installer, and every build was tested in the game on a real Mac. Thanks to
the DXVK and DXMT developers, whose work this builds on.

This project is not affiliated with CodeWeavers, Warner Bros. Games, GOG or Valve. You need your own
CrossOver license and your own copy of the game.

## Support

If this helped you play the game on your Mac, you can buy me a coffee:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/F2J527ZLUN)
