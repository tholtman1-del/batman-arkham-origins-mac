# Shared helpers for install.command, launch.command and uninstall.command (zsh).
# Only tools that ship with macOS are used (zsh, perl, cp, codesign, curl, shasum).

BMAO_HOME="$HOME/Library/Application Support/BatmanAO-Mac"
BMAO_CONFIG="$BMAO_HOME/config.sh"
BMAO_DEFAULT_BOTTLE="Batman Arkham Origins (Mac)"
DXMT_VERSION="v0.80"
DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
DXMT_SHA256="8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"

info() { print -P "%F{cyan}==>%f $*"; }
warn() { print -P "%F{yellow}warning:%f $*" >&2; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

# Ask a yes/no question; $2 is the default (y or n).
ask() {
  local answer prompt="[y/N]"
  [[ $2 == y ]] && prompt="[Y/n]"
  read "answer?$1 $prompt "
  [[ -z $answer ]] && answer=$2
  [[ $answer == [yY]* ]]
}

# Locate CrossOver.app: $CROSSOVER_APP, the usual folders, then Spotlight.
find_crossover() {
  local app
  for app in "$CROSSOVER_APP" /Applications/CrossOver.app "$HOME/Applications/CrossOver.app"; do
    [[ -n $app && -x $app/Contents/SharedSupport/CrossOver/bin/wine ]] && { print -r -- "$app"; return 0; }
  done
  app=$(mdfind "kMDItemCFBundleIdentifier == 'com.codeweavers.CrossOver'" 2>/dev/null | head -1)
  [[ -n $app && -x $app/Contents/SharedSupport/CrossOver/bin/wine ]] && { print -r -- "$app"; return 0; }
  return 1
}

crossover_version() {
  /usr/bin/defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

bottles_dir() {
  print -r -- "$HOME/Library/Application Support/CrossOver/Bottles"
}

# PE DllCharacteristics helpers. NX_COMPAT (0x100) matters: if any loaded DLL lacks it, Wine maps
# all process memory read-write-execute, and under Rosetta writes to such memory trap constantly
# (loading screens crawl at 1-3 FPS).
# pe_nx_status FILE -> prints "nx", "no-nx" or "not-pe"
pe_nx_status() {
  /usr/bin/perl -e '
    open(my $f, "<", $ARGV[0]) or do { print "not-pe"; exit };
    binmode $f; local $/; my $d = <$f>;
    if (length($d) < 0x40 || substr($d, 0, 2) ne "MZ") { print "not-pe"; exit }
    my $pe = unpack("V", substr($d, 0x3c, 4));
    if ($pe + 24 + 72 > length($d) || substr($d, $pe, 4) ne "PE\0\0") { print "not-pe"; exit }
    my $flags = unpack("v", substr($d, $pe + 24 + 70, 2));
    print(($flags & 0x100) ? "nx" : "no-nx");
  ' "$1"
}

# pe_set_nx FILE : sets NX_COMPAT in place
pe_set_nx() {
  /usr/bin/perl -e '
    open(my $f, "+<", $ARGV[0]) or die "cannot open $ARGV[0]: $!\n";
    binmode $f; local $/; my $d = <$f>;
    my $pe = unpack("V", substr($d, 0x3c, 4));
    my $off = $pe + 24 + 70;
    my $flags = unpack("v", substr($d, $off, 2)) | 0x100;
    seek($f, $off, 0); print $f pack("v", $flags); close $f;
  ' "$1"
}

# ini_set FILE SECTION KEY VALUE : set KEY=VALUE inside [SECTION] of a UE3 ini.
# Handles UTF-16LE (with BOM, as the game writes it) and plain ASCII files. No-op if the key is absent.
ini_set() {
  /usr/bin/perl -e '
    use Encode;
    my ($path, $section, $key, $value) = @ARGV;
    open(my $f, "<", $path) or exit 0; binmode $f; local $/; my $raw = <$f>; close $f;
    my $utf16 = substr($raw, 0, 2) eq "\xFF\xFE";
    my $text = $utf16 ? decode("UTF-16LE", substr($raw, 2)) : $raw;
    my @lines = split(/\r\n/, $text, -1);
    my $cur = "";
    for (@lines) {
      $cur = $1 if /^\[(.*)\]$/;
      $_ = "$key=$value" if $cur eq $section && /^\Q$key\E=/;
    }
    $text = join("\r\n", @lines);
    open($f, ">", $path) or die "cannot write $path: $!\n"; binmode $f;
    print $f ($utf16 ? "\xFF\xFE" . encode("UTF-16LE", $text) : $text); close $f;
  ' "$1" "$2" "$3" "$4"
}

# conf_get_env CONF KEY : prints the value of KEY in [EnvironmentVariables] of a cxbottle.conf (empty if unset)
conf_get_env() {
  /usr/bin/perl -ne '
    BEGIN { ($key) = splice(@ARGV, 1, 1) }
    $in = ($1 eq "EnvironmentVariables") if /^\[(.*)\]\s*$/;
    if ($in && /^"\Q$key\E"\s*=\s*"(.*)"\s*$/) { print $1; exit }
  ' "$1" "$2"
}

# conf_set_env CONF KEY VALUE : sets (or adds) KEY in [EnvironmentVariables]; empty VALUE removes it.
conf_set_env() {
  /usr/bin/perl -e '
    my ($path, $key, $value) = @ARGV;
    open(my $f, "<", $path) or die "cannot read $path: $!\n"; my @l = <$f>; close $f;
    my ($start, $end) = (-1, scalar @l);
    for my $i (0 .. $#l) {
      if ($l[$i] =~ /^\[(.*)\]\s*$/) {
        if ($1 eq "EnvironmentVariables") { $start = $i } elsif ($start >= 0 && $end == @l) { $end = $i }
      }
    }
    if ($start < 0) { push @l, "\n[EnvironmentVariables]\n"; $start = $#l; $end = @l }
    my $line = qq("$key" = "$value"\n);
    my $done = 0;
    for my $i ($start + 1 .. $end - 1) {
      if ($l[$i] =~ /^"\Q$key\E"\s*=/) { $l[$i] = $value eq "" ? "" : $line; $done = 1 }
    }
    splice(@l, $end, 0, $line) if !$done && $value ne "";
    open($f, ">", $path) or die "cannot write $path: $!\n"; print $f @l; close $f;
  ' "$1" "$2" "$3"
}
