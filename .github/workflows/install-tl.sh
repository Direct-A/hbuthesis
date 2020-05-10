#!/usr/bin/env perl
# $Id: install-tl 54993 2020-05-03 21:57:54Z karl $
# Copyright 2007-2020
# Reinhard Kotucha, Norbert Preining, Karl Berry, Siep Kroonenberg.
# This file is licensed under the GNU General Public License version 2
# or any later version.
#
# Be careful when changing wording: *every* normal informational message
# output here must be recognized by the long grep in tl-update-tlnet.

my $svnrev = '$Revision: 54993 $';
$svnrev =~ m/: ([0-9]+) /;
$::installerrevision = ($1 ? $1 : 'unknown');

# taken from 00texlive.config: release, $tlpdb->config_release;
our $texlive_release;

BEGIN {
  $^W = 1;
  my $Master;
  my $me = $0;
  $me =~ s!\\!/!g if $^O =~ /^MSWin/i;
  if ($me =~ m!/!) {
    ($Master = $me) =~ s!(.*)/[^/]*$!$1!;
  } else {
    $Master = ".";
  }
  $::installerdir = $Master;

  # All platforms: add the installer modules
  unshift (@INC, "$::installerdir/tlpkg");
}

# debugging communication with external gui: use shared logfile

our $dblfile = "/tmp/dblog";
$dblfile = $ENV{'TEMP'} . "\\dblog.txt" if ($^O =~ /^MSWin/i);
$dblfile = $ENV{'TMPDIR'} . "/dblog" if ($^O eq 'darwin'
                                         && exists $ENV{'TMPDIR'});
sub dblog {
  my $s = shift;
  open(my $dbf, ">>", $dblfile);
  print $dbf "PERL: $s\n";
  close $dbf;
}


# On unix, this run of install-tl may do duty as a wrapper for
# install-tl-gui.tcl, which in its turn will start an actual run of install-tl.
# Skip this wrapper block if we can easily rule out a tcl gui:

if (($^O !~ /^MSWin/i) &&
      # this wrapper is only for unix, since windows has its own wrapper
      ($#ARGV >= 0 || ($^O eq 'darwin')) &&
        # tcl parameter may still come, or tcl is default
      ($#ARGV < 0 || $ARGV[0] ne '-from_ext_gui')
        # this run is not invoked by tcl
    ) {

  # make syntax uniform: --a => -a, a=b => 'a b'
  my @tmp_args = ();
  my $p;
  my $i=-1;
  while ($i<$#ARGV) {
    $p = $ARGV[++$i];
    $p =~ s/^--/-/;
    if ($p =~ /^(.*)=(.*)$/) {
      push (@tmp_args, $1, $2);
    } else {
      push (@tmp_args, $p);
    }
  }

  # build argument array @new_args for install-tl-gui.tcl.
  # '-gui' or '-gui tcl' will not be copied to @new_args.
  # quit scanning and building @new_args once tcl is ruled out.
  my $want_tcl = ($^O eq 'darwin');
  my $asked4tcl = 0;
  my @new_args = ();
  $i = -1;
  while ($i < $#tmp_args) {
    $p = $tmp_args[++$i];
    if ($p eq '-gui') {
      # look ahead at next parameter
      if ($i == $#tmp_args || $tmp_args[$i+1] =~ /^-/) {
        $want_tcl = 1; # default value for -gui
        $asked4tcl = 1;
      } elsif ($tmp_args[$i+1] eq 'tcl') {
        $want_tcl = 1;
        $asked4tcl = 1;
        $i++;
      } else { # other value for -gui
        $want_tcl = 0;
        last;
      }
    } else {
      my $forbid = 0;
      for my $q (qw/in-place profile help/) {
        if ($p eq "-$q") {
          # default text mode
          $want_tcl = 0 unless $asked4tcl;
          last;
        }
      }
      for my $q (qw/print-platform version no-gui/) {
        if ($p eq "-$q") {
          # enforce text mode
          $want_tcl = 0;
          $forbid = 1;
          last;
        }
      }
      last if $forbid;
      # not gui-related, continue collecting @new_args
      push (@new_args, $p);
    }
  }
  # done scanning arguments
  if ($want_tcl) {
    unshift (@new_args, "--");
    unshift (@new_args, "$::installerdir/tlpkg/installer/install-tl-gui.tcl");
    my @wishes = qw /wish wish8.6 wish8.5 tclkit/;
    unshift @wishes, $ENV{'WISH'} if (defined $ENV{'WISH'});
    foreach my $w (@wishes) {
      if (!exec($w, @new_args)) {
        next; # no return on successful exec
      }
    }
    # no succesful exec of wish
  } # else continue with main installer below
}
# end of wrapper block, start of the real installer

use Cwd 'abs_path';
use Getopt::Long qw(:config no_autoabbrev);
use Pod::Usage;
use POSIX ();

use TeXLive::TLUtils qw(platform platform_desc sort_archs
   which getenv win32 unix info log debug tlwarn ddebug tldie
   member process_logging_options rmtree wsystem
   mkdirhier make_var_skeleton make_local_skeleton install_package copy
   install_packages dirname setup_programs native_slashify forward_slashify);
use TeXLive::TLPOBJ;
use TeXLive::TLPDB;
use TeXLive::TLConfig;
use TeXLive::TLCrypto;
use TeXLive::TLDownload;
use TeXLive::TLPaper;

if (win32) {
  require TeXLive::TLWinGoo;
  TeXLive::TLWinGoo->import( qw(
    &is_vista
    &is_seven
    &admin
    &non_admin
    &reg_country
    &expand_string
    &get_system_path
    &get_user_path
    &setenv_reg
    &unsetenv_reg
    &adjust_reg_path_for_texlive
    &register_extension
    &unregister_extension
    &register_file_type
    &unregister_file_type
    &broadcast_env
    &update_assocs
    &add_menu_shortcut
    &remove_desktop_shortcut
    &remove_menu_shortcut
    &create_uninstaller
    &maybe_make_ro
  ));
}

use strict;

# global list of lines that get logged (see TLUtils.pm::_logit).
@::LOGLINES = ();
# if --version, --help, etc., this just gets thrown away, which is ok.
&log ("TeX Live installer invocation: $0", map { " $_" } @ARGV, "\n");

# global list of warnings
@::WARNLINES = ();

# we play around with the environment, place to keep original
my %origenv = ();

# $install{$packagename} == 1 if it should be installed
my %install;

# the different modules have to assign a code blob to this global variable
# which starts the installation.
# Example: In install-menu-text.pl there is
#   $::run_menu = \&run_menu_text;
#
$::run_menu = sub { die "no UI defined." ; };

# the default scheme to be installed
my $default_scheme='scheme-full';

# common fmtutil args, keep in sync with tlmgr.pl.
our $common_fmtutil_args =
  "--no-error-if-no-engine=$TeXLive::TLConfig::PartialEngineSupport";

# some arrays where the lists of collections to be installed are saved
# our for menus
our @collections_std;

# The global variable %vars is an associative list which contains all
# variables and their values which can be changed by the user.
# needs to be our since TeXLive::TLUtils uses it
#
# The following values are taken from the remote tlpdb using the
#   $tlpdb->tlpdbopt_XXXXX
# settings (i.e., taken from tlpkg/tlpsrc/00texlive.installation.tlpsrc
#
#        'tlpdbopt_sys_bin' => '/usr/local/bin',
#        'tlpdbopt_sys_man' => '/usr/local/man',
#        'tlpdbopt_sys_info' => '/usr/local/info',
#        'tlpdbopt_install_docfiles' => 1,
#        'tlpdbopt_install_srcfiles' => 1,
#        'tlpdbopt_create_formats' => 0,
our %vars=( # 'n_' means 'number of'.
        'this_platform' => '',
        'n_systems_available' => 0,
        'n_systems_selected' => 0,
        'n_collections_selected' => 0,
        'n_collections_available' => 0,
        'total_size' => 0,
        'src_splitting_supported' => 1,
        'doc_splitting_supported' => 1,
        'selected_scheme' => $default_scheme,
        'instopt_portable' => 0,
        'instopt_letter' => 0,
        'instopt_adjustrepo' => 1,
        'instopt_write18_restricted' => 1,
        'instopt_adjustpath' => 0,
    );

my %path_keys = (
  'TEXMFLOCAL' => 1,
  'TEXMFCONFIG' => 1,
  'TEXMFSYSCONFIG' => 1,
  'TEXMFVAR' => 1,
  'TEXMFSYSVAR' => 1,
  'TEXDIR' => 1,
  'TEXMFHOME' => 1,
);

# option handling
my $opt_allow_ftp = 0;
my $opt_custom_bin;
my $opt_force_arch;
# tcl gui weeded out at start
my $opt_gui = "text";
my $opt_help = 0;
my $opt_init_from_profile = "";
my $opt_location = "";
my $opt_no_gui = 0;
my $opt_nonadmin = 0;
my $opt_persistent_downloads = 1;
my $opt_portable = 0;
my $opt_print_arch = 0;
my $opt_profile = "";
my $opt_scheme = "";
my $opt_version = 0;
my $opt_warn_checksums = 1;
my $opt_font;
# unusual cases:
$::opt_select_repository = 0;
our $opt_in_place = 0;
# don't set this to a value, see below
my $opt_verify_downloads;

# show all options even those not relevant for that arch
$::opt_all_options = 0;

# default language for GUI installer
$::lang = "en";

# use the fancy directory selector for TEXDIR
# no longer used, although we still accept the parameter
$::alternative_selector = 0;

# do not debug translations by default
$::debug_translation = 0;

# some strings to describe the different meanings of tlpdbopt_file_assoc
$::fileassocdesc[0] = "None";
$::fileassocdesc[1] = "Only new";
$::fileassocdesc[2] = "All";

# before we try to interact with the user, we need to know whether or not
# install-tl was called from an external gui. This gui will start install-tl
# with "-from_ext_gui" as its first command-line option.

my $from_ext_gui = 0;
if ((defined $ARGV[0]) && $ARGV[0] eq "-from_ext_gui") {
  shift @ARGV;
  $from_ext_gui = 1;

  # do not buffer output to the frontend
  select(STDERR);
  $| = 1;
  select(STDOUT);
  $| = 1;

  # windows: suppress console windows when invoking other programs
  Win32::SetChildShowWindow(0) if win32();
  # ___, defined in this file, replaces the GUI translating function
  *__ = \&::___;
}

# if we find a file installation.profile we ask the user whether we should
# continue with the installation
# note, we are in the directory from which the aborted installation was run.
my %profiledata;
if (-r "installation.profile") {
  if ($from_ext_gui) { # prepare for dialog interaction
    print "mess_yesno\n";
  }
  my $pwd = Cwd::getcwd();
  print "ABORTED TL INSTALLATION FOUND: installation.profile (in $pwd)\n";
  print
    "Do you want to continue with the exact same settings as before (y/N): ";
  print "\nendmess\n" if $from_ext_gui;
  my $answer = <STDIN>;
  if ($answer =~ m/^y(es)?$/i) {
    $opt_profile = "installation.profile";
  }
}


# first process verbosity/quiet options
process_logging_options();
# now the others
GetOptions(
           "all-options"                 => \$::opt_all_options,
           "custom-bin=s"                => \$opt_custom_bin,
           "debug-translation"           => \$::debug_translation,
           "fancyselector"               => \$::alternative_selector,
           "force-platform|force-arch=s" => \$opt_force_arch,
           "gui:s"                       => \$opt_gui,
           "in-place"                    => \$opt_in_place,
           "init-from-profile=s"         => \$opt_init_from_profile,
           "lang=s"                      => \$::opt_lang,
           "gui-lang=s"                  => \$::opt_lang,
           "location|url|repository|repos|repo=s" => \$opt_location,
           "no-cls",                    # $::opt_no_cls in install-menu-text-pl
           "no-gui"                      => \$opt_no_gui,
           "non-admin"                   => \$opt_nonadmin,
           "persistent-downloads!"       => \$opt_persistent_downloads,
           "portable"                    => \$opt_portable,
           "print-platform|print-arch"   => \$opt_print_arch,
           "profile=s"                   => \$opt_profile,
           "scheme=s"                    => \$opt_scheme,
           "select-repository"           => \$::opt_select_repository,
           "font=s"                      => \$opt_font,
           "tcl",                       # handled by wrapper
           "verify-downloads!"           => \$opt_verify_downloads,
           "version"                     => \$opt_version,
           "warn-checksums!"             => \$opt_warn_checksums,
           "help|?"                      => \$opt_help) or pod2usage(2);

if ($opt_gui eq "expert") {
  $opt_gui = "perltk";
}
if ($opt_gui eq "" || $opt_gui eq "tcl") {
  # tried and failed tcl, try perltk instead
  $opt_gui = "perltk";
  warn "Setting opt_gui to perltk instead";
}
if ($from_ext_gui) {
  $opt_gui = "extl";
}

if ($opt_help) {
  # theoretically we could make a subroutine with all the same
  # painful checks as we do in tlmgr, but let's not bother until people ask.
  my @noperldoc = ();
  if (win32() || $ENV{"NOPERLDOC"}) {
    @noperldoc = ("-noperldoc", "1");
  }

  # Tweak less stuff same as tlmgr, though.
  # less can break control characters and thus the output of pod2usage
  # is broken.  We add/set LESS=-R in the environment and unset
  # LESSPIPE and LESSOPEN to try to help.
  # 
  if (defined($ENV{'LESS'})) {
    $ENV{'LESS'} .= " -R";
  } else {
    $ENV{'LESS'} = "-R";
  }
  delete $ENV{'LESSPIPE'};
  delete $ENV{'LESSOPEN'};

  pod2usage(-exitstatus => 0, -verbose => 2, @noperldoc);
  die "sorry, pod2usage did not work; maybe a download failure?";
}

if ($opt_version) {
  print "install-tl (TeX Live Cross Platform Installer)",
        " revision $::installerrevision\n";
  if (open (REL_TL, "$::installerdir/release-texlive.txt")) {
    # print first and last lines, which have the TL version info.
    my @rel_tl = <REL_TL>;
    print $rel_tl[0];
    print $rel_tl[$#rel_tl];
    close (REL_TL);
  }
  if ($::opt_verbosity > 0) {
    print "Module revisions:";
    print "\nTLConfig: " . TeXLive::TLConfig->module_revision();
    print "\nTLCrypto: " . TeXLive::TLCrypto->module_revision();
    print "\nTLDownload: ".TeXLive::TLDownload->module_revision();
    print "\nTLPDB:    " . TeXLive::TLPDB->module_revision();
    print "\nTLPOBJ:   " . TeXLive::TLPOBJ->module_revision();
    print "\nTLTREE:   " . TeXLive::TLTREE->module_revision();
    print "\nTLUtils:  " . TeXLive::TLUtils->module_revision();
    print "\nTLWinGoo: " . TeXLive::TLWinGoo->module_revision() if win32();
    print "\n";
  }
  exit 0;
}

die "$0: Options custom-bin and in-place are incompatible.\n"
  if ($opt_in_place && $opt_custom_bin);

die "$0: Options profile and in-place are incompatible.\n"
  if ($opt_in_place && $opt_profile);

die "$0: Options init-from-profile and in-place are incompatible.\n"
  if ($opt_in_place && $opt_init_from_profile);

if ($#ARGV >= 0) {
  # we still have arguments left, should only be gui, otherwise die
  if ($ARGV[0] =~ m/^gui$/i) {
    $opt_gui = "perltk";
  } else {
    die "$0: Extra arguments `@ARGV'; try --help if you need it.\n";
  }
}


if (defined($::opt_lang)) {
  $::lang = $::opt_lang;
}

if ($opt_profile) { # for now, not allowed if in_place
  if (-r $opt_profile && -f $opt_profile) {
    info("Automated TeX Live installation using profile: $opt_profile\n");
  } else {
    $opt_profile = "";
    info(
"Profile $opt_profile not readable or not a file, continuing in interactive mode.\n");
  }
}

if ($opt_nonadmin and win32()) {
  non_admin();
}


# the TLPDB instances we will use. $tlpdb is for the one from the installation
# media, while $localtlpdb is for the new installation
# $tlpdb must be our because it is used in install-menu-text.pl
our $tlpdb;
my $localtlpdb;
my $location;

@::info_hook = ();

our $media;
our @media_available;

TeXLive::TLUtils::initialize_global_tmpdir();

# special uses of install-tl:
if ($opt_print_arch) {
  print platform()."\n";
  exit 0;
}

if (TeXLive::TLCrypto::setup_checksum_method()) {
  # try to setup gpg:
  # either explicitly requested or nothing requested
  if ((defined($opt_verify_downloads) && $opt_verify_downloads)
      ||
      (!defined($opt_verify_downloads))) {
    if (TeXLive::TLCrypto::setup_gpg($::installerdir)) {
      # make sure we actually do verify ...
      $opt_verify_downloads = 1;
      log("Trying to verify cryptographic signatures!\n")
    } else {
      if ($opt_verify_downloads) {
        tldie("$0: No gpg found, but verification explicitly requested "
              . "on command line, so quitting.\n");
      } else {
        # implicitly requested, just 
        debug("Couldn't detect gpg so will proceed without verification!\n");
      }
    }
  }
} else {
  if ($opt_warn_checksums) {
      tldie(<<END_NO_CHECKSUMS);
Warning: Cannot find a checksum implementation.
Please install Digest::SHA (from CPAN), openssl, or sha512sum,
or use --no-warn-checksums command line!
END_NO_CHECKSUMS
  }
}


# continuing with normal install

# check as soon as possible for GUI functionality to give people a chance
# to interrupt.
# not needed for extl, because in this case install-tl is invoked by external gui
if (($opt_gui ne "extl") && ($opt_gui ne "text") && !$opt_no_gui && ($opt_profile eq "")) {
  # try to load Tk.pm, but don't die if it doesn't work
  eval { require Tk; };
  if ($@) {
    # that didn't work out, so warn the user and continue with text mode
    tlwarn("Cannot load Tk, maybe something is missing and\n");
    tlwarn("maybe https://tug.org/texlive/distro.html#perltk can help.\n");
    tlwarn("Error message from loading Tk:\n");
    tlwarn("  $@\n");
    tlwarn("Continuing in text mode...\n");
    $opt_gui = "text";
  }
  eval { my $foo = Tk::MainWindow->new; $foo->destroy; };
  if ($@) {
    tlwarn("perl/Tk unusable, cannot create main window.\n");
    if (platform() eq "universal-darwin") {
      tlwarn("That could be because X11 is not installed or started.\n");
    }
    tlwarn("Error message from creating MainWindow:\n");
    tlwarn("  $@\n");
    tlwarn("Continuing in text mode...\n");
    $opt_gui = "text";
  } else {
    # try to set up fonts if $opt_gui is given
    if ($opt_font) {
      my @a;
      push @a, "--font", $opt_font;
      Tk::CmdLine::SetArguments(@a);
    }
  }
  if ($opt_gui eq "text") {
    # we switched from GUI to non-GUI mode, tell the user and wait a bit
    tlwarn("\nSwitching to text mode installer, if you want to cancel, do it now.\n");
    tlwarn("Waiting for 3 seconds\n");
    sleep(3);
  }
}

if (defined($opt_force_arch)) {
  tlwarn("Overriding platform to $opt_force_arch\n");
  $::_platform_ = $opt_force_arch;
}

# initialize the correct platform
platform();
$vars{'this_platform'} = $::_platform_;

# we do not support cygwin < 1.7, so check for that
if (!$opt_custom_bin && (platform() eq "i386-cygwin")) {
  chomp( my $un = `uname -r`);
  if ($un =~ m/^(\d+)\.(\d+)\./) {
    if ($1 < 2 && $2 < 7) {
      tldie("$0: Sorry, the TL binaries require at least cygwin 1.7, "
            . "not $1.$2\n");
    }
  }
}

# determine which media are available, don't put NET here, it is
# assumed to be available at any time
{
  # check the installer dir for what is present
  my $tmp = $::installerdir;
  $tmp = abs_path($tmp);
  # remove trailing \ or / (e.g. root of dvd drive on w32)
  $tmp =~ s,[\\\/]$,,;
  if (-d "$tmp/$Archive") {
    push @media_available, "local_compressed#$tmp";
  }
  if (-r "$tmp/texmf-dist/web2c/texmf.cnf") {
    push @media_available, "local_uncompressed#$tmp";
  }
}

# check command line arguments if given
if ($opt_location) {
  my $tmp = $opt_location;
  if ($tmp =~ m!^(https?|ftp)://!i) {
    push @media_available, "NET#$tmp";

  } elsif ($tmp =~ m!^(rsync|)://!i) {
    tldie ("$0: sorry, rsync unsupported; use an http or ftp url here.\n"); 

  } else {
    # remove leading file:/+ part
    $tmp =~ s!^file://*!/!i;
    $tmp = abs_path($tmp);
    # remove trailing \ or / (e.g. root of dvd drive on w32)
    $tmp =~ s,[\\\/]$,,;
    if (-d "$tmp/$Archive") {
      push @media_available, "local_compressed#$tmp";
    }
    if (-d "$tmp/texmf-dist/web2c") {
      push @media_available, "local_uncompressed#$tmp";
    }
  }
}

# find wget, tar, xz
if (!setup_programs ("$::installerdir/tlpkg/installer", "$::_platform_")) {
  tldie("$0: Goodbye.\n");
}


if ($opt_profile eq "") {
  if ($opt_init_from_profile) {
    read_profile("$opt_init_from_profile", seed => 1);
  }
  # do the normal interactive installation.
  #
  # here we could load different menu systems. Currently several things
  # are "our" so that the menu implementation can use it. The $tlpdb, the
  # %var, and all the @collection*
  # install-menu-*.pl have to assign a code ref to $::run_menu which is
  # run, and should change ONLY stuff in %vars
  # The allowed keys in %vars should be specified somewhere ...
  # the menu implementation should return
  #    MENU_INSTALL  do the installation
  #    MENU_ABORT    abort every action immediately, no cleanup
  #    MENU_QUIT     try to quit and clean up mess
  our $MENU_INSTALL = 0;
  our $MENU_ABORT   = 1;
  our $MENU_QUIT    = 2;
  $opt_gui = "text" if ($opt_no_gui);
  # finally do check for additional screens in the $opt_gui setting:
  # format:
  #   --gui <plugin>:<a1>,<a2>,...
  # which will passed to run_menu (<a1>, <a2>, ...)
  #
  my @runargs;
  if ($opt_gui =~ m/^([^:]*):(.*)$/) {
    $opt_gui = $1;
    @runargs = split ",", $2;
  }
  if (-r "$::installerdir/tlpkg/installer/install-menu-${opt_gui}.pl") {
    require("installer/install-menu-${opt_gui}.pl");
  } else {
    tlwarn("UI plugin $opt_gui not found,\n");
    tlwarn("Using text mode installer.\n");
    require("installer/install-menu-text.pl");
  }

  # before we start the installation we check for the existence of
  # a previous installation, and in case we ship inform the UI
  if (!exists $ENV{"TEXLIVE_INSTALL_NO_WELCOME"}) {
    my $tlmgrwhich = which("tlmgr");
    if ($tlmgrwhich) {
      my $dn = dirname($tlmgrwhich);
      $dn = abs_path("$dn/../..");
      # The "make Karl happy" case, check that we are not running install-tl
      # from the same tree where tlmgr is hanging around
      my $install_tl_root = abs_path($::installerdir);
      my $tlpdboldpath
       = $dn .
         "/$TeXLive::TLConfig::InfraLocation/$TeXLive::TLConfig::DatabaseName";
      if (-r $tlpdboldpath && $dn ne $install_tl_root) {
        debug ("found old installation in $dn\n");
        push @runargs, "-old-installation-found=$dn";
        # only the text-mode menu will pay attention!
      }
    }
  }

  my $ret = &{$::run_menu}(@runargs);
  if ($ret == $MENU_QUIT) {
    do_cleanup(); # log, profile, temp files
    flushlog();
    exit(1);
  } elsif ($ret == $MENU_ABORT) {
    # here, omit do_cleanup()
    flushlog();
    exit(2);
  }
  if ($ret != $MENU_INSTALL) {
    tlwarn("Unknown return value of run_menu: $ret\n");
    exit(3);
  }
} else { # no interactive setting of options
  *__ = \&::___;
  if (!do_remote_init()) {
    die ("Exiting installation.\n");
  }
  read_profile($opt_profile);
  if ($from_ext_gui) {
    print STDOUT "startinst\n";
  }
}

my $varsdump = "";
foreach my $key (sort keys %vars) {
  my $val = $vars{$key} || "";
  $varsdump .= "  $key: \"$val\"\n";
}
log("Settings:\n" . $varsdump);

# portable option overrides any system integration options
$vars{'instopt_adjustpath'} = 0 if $vars{'instopt_portable'};
$vars{'tlpdbopt_file_assocs'} = 0 if $vars{'instopt_portable'};
$vars{'tlpdbopt_desktop_integration'} = 0 if $vars{'instopt_portable'};
install_warnlines_hook(); # collect warnings in @::WARNLINES
info("Installing to: $vars{TEXDIR}\n");

$::env_warns = "";
create_welcome();
my $status = 1;
if ($opt_gui eq 'text' or $opt_gui eq 'extl' or $opt_profile ne "" or
      !(-r "$::installerdir/tlpkg/installer/tracked-install.pl")) {
  $status = do_installation();
  if (@::WARNLINES) {
    foreach my $t (@::WARNLINES) { print STDERR $t; }
  }
  if ($::env_warns) { tlwarn($::env_warns); }
  unless ($ENV{"TEXLIVE_INSTALL_NO_WELCOME"} or $opt_gui eq 'extl') {
    info(join("\n", @::welcome_arr));
  }
  do_cleanup(); # sets $::LOGFILENAME if not already defined
  if ($LOGFILENAME) {
    print STDOUT "\nLogfile: $::LOGFILENAME\n";
  } else {
    # do_cleanup sets $::LOGFILENAME to ""
    #if no logfile could be written
    print STDERR
      "Cannot create logfile $vars{'TEXDIR'}/install-tl.log: $!\n";
  }
  printf STDOUT "Installed on platform %s at %s\n",
      $vars{'this_platform'}, $vars{'TEXDIR'} if ($opt_gui eq 'extl');
} else {
  require("installer/tracked-install.pl");
  $status = installer_tracker();
}
exit $status;


###################################################################
#
# FROM HERE ON ONLY SUBROUTINES
# NO VARIABLE DECLARATIONS OR CODE
#
###################################################################

#
# SETUP OF REMOTE STUFF
#
# this is now a sub since it is called from the ui plugins on demand
# this allows selecting a mirror first and then continuing

sub only_load_remote {
  my $selected_location = shift;

  # determine where we will find the distribution to install from.
  #
  $location = $opt_location;
  $location = $selected_location if defined($selected_location);
  $location || ($location = "$::installerdir");
  if ($location =~ m!^(ctan$|(https?|ftp)://)!i) {
    # remove any trailing tlpkg[/texlive.tlpdb] or /
    $location =~ s,/(tlpkg(/texlive\.tlpdb)?|archive)?/*$,,;
    if ($location =~ m/^ctan$/i) {
      $location = TeXLive::TLUtils::give_ctan_mirror();
    } elsif ($location =~ m/^$TeXLiveServerURL/) {
      my $mirrorbase = TeXLive::TLUtils::give_ctan_mirror_base();
      $location =~ s,^($TeXLiveServerURL|ctan$),$mirrorbase,;
    }
    $TeXLiveURL = $location;
    $media = 'NET';
  } else {
    if (scalar grep($_ =~ m/^local_compressed/, @media_available)) {
      $media = 'local_compressed';
      # for in_place option we want local_uncompressed media
      $media = 'local_uncompressed' if $opt_in_place &&
        member('local_uncompressed', @media_available);
    } elsif (scalar grep($_ =~ m/^local_uncompressed/, @media_available)) {
      $media = 'local_uncompressed';
    } else {
      if ($opt_location) {
        # user gave a --location but nothing can be found there, so die
        die "$0: cannot find installation source at $opt_location.\n";
      }
      # no --location given, but NET installation
      $TeXLiveURL = $location = TeXLive::TLUtils::give_ctan_mirror();
      $media = 'NET';
    }
  }
  if ($from_ext_gui) {print "location: $location\n";}
  return load_tlpdb();
} # only_load_remote


sub do_remote_init {
  if (!only_load_remote(@_)) {
    tlwarn("$0: Could not load TeX Live Database from $location, goodbye.\n");
    return 0;
  }
  if (!do_version_agree()) {
    TeXLive::TLUtils::tldie <<END_MISMATCH;
=============================================================================
$0: The TeX Live versions of the local installation
and the repository being accessed are not compatible:
      local: $TeXLive::TLConfig::ReleaseYear
 repository: $texlive_release
Perhaps you need to use a different CTAN mirror?
(For more, see the output of install-tl --help, especially the
 -repository option.  Online via https://tug.org/texlive/doc.)
=============================================================================
END_MISMATCH
  }
  final_remote_init();
  return 1;
} # do_remote_init

sub do_version_agree {
  $texlive_release = $tlpdb->config_release;
  if ($media eq "local_uncompressed") {
    # existing installation may not have 00texlive.config metapackage
    # so use TLConfig to establish what release we have
    $texlive_release ||= $TeXLive::TLConfig::ReleaseYear;
  }

  # if the release from the remote TLPDB does not agree with the
  # TLConfig::ReleaseYear in the first 4 places break out here.
  # Why only the first four places: some optional network distributions
  # might use
  #   release/2009-foobar
  if ($media eq "NET"
      && $texlive_release !~ m/^$TeXLive::TLConfig::ReleaseYear/) {
    return 0;
  } else {
    return 1;
  }
} # do_version_agree

sub final_remote_init {
  info("Installing TeX Live $TeXLive::TLConfig::ReleaseYear from: $location" .
    ($tlpdb->is_verified ? " (verified)" : " (not verified)") . "\n");

  info("Platform: ", platform(), " => \'", platform_desc(platform), "\'\n");
  if ($opt_custom_bin) {
    if (-d $opt_custom_bin && (-r "$opt_custom_bin/kpsewhich"
                               || -r "$opt_custom_bin/kpsewhich.exe")) {
      info("Platform overridden, binaries taken from $opt_custom_bin\n"
           . "and will be installed into .../bin/custom.\n");
    } else {
      tldie("$0: -custom-bin argument must be a directory "
            . "with TeX Live binaries, not like: $opt_custom_bin\n");
    }
  }
  if ($media eq "local_uncompressed") {
    info("Distribution: live (uncompressed)\n");
  } elsif ($media eq "local_compressed") {
    info("Distribution: inst (compressed)\n");
  } elsif ($media eq "NET") {
    info("Distribution: net  (downloading)\n");
    info("Using URL: $TeXLiveURL\n");
    TeXLive::TLUtils::setup_persistent_downloads() if $opt_persistent_downloads;
  } else {
    info("Distribution: $media\n");
  }
  info("Directory for temporary files: $::tl_tmpdir\n");

  if ($opt_in_place and ($media ne "local_uncompressed")) {
    print "TeX Live not local or not decompressed; 'in_place' option not applicable\n";
    $opt_in_place = 0;
  } elsif (
      $opt_in_place and (!TeXLive::TLUtils::texdir_check($::installerdir))) {
    print "Installer dir not writable; 'in_place' option not applicable\n";
    $opt_in_place = 0;
  }
  $opt_scheme = "" if $opt_in_place;
  $vars{'instopt_portable'} = $opt_portable;
  $vars{'instopt_adjustpath'} = 1 if win32();

  log("Installer revision: $::installerrevision\n");
  log("Database revision: " . $tlpdb->config_revision . "\n");

  # correctly set the splitting support
  # for local_uncompressed we always support splitting
  if (($media eq "NET") || ($media eq "local_compressed")) {
    $vars{'src_splitting_supported'} = $tlpdb->config_src_container;
    $vars{'doc_splitting_supported'} = $tlpdb->config_doc_container;
  }
  set_platforms_supported();
  set_texlive_default_dirs();
  set_install_platform();
  initialize_collections();

  # initialize the scheme from the command line value, if given.
  if ($opt_scheme) {
    # add the scheme- prefix if they didn't give it.
    $opt_scheme = "scheme-$opt_scheme" if $opt_scheme !~ /^scheme-/;
    my $scheme = $tlpdb->get_package($opt_scheme);
    if (defined($scheme)) {
      select_scheme($opt_scheme);  # select it
    } else {
      tlwarn("Scheme $opt_scheme not defined, ignoring it.\n");
    }
  }
} # final_remote_init


sub do_installation {
  if (win32()) {
    non_admin() if !$vars{'tlpdbopt_w32_multi_user'};
  }
  if ($vars{'instopt_portable'}) {
    $vars{'tlpdbopt_desktop_integration'} = 0;
    $vars{'tlpdbopt_file_assocs'} = 0;
    $vars{'instopt_adjustpath'} = 0;
    $vars{'tlpdbopt_w32_multi_user'} = 0;
  }
  if ($vars{'selected_scheme'} ne "scheme-infraonly"
      && $vars{'n_collections_selected'} <= 0) {
    tldie("$0: Nothing selected, nothing to install, exiting!\n");
  }
  # maybe_make_ro tests for admin, local drive and NTFS before proceeding.
  # making the root read-only automatically locks everything below it.
  # do TEXDIR now, before it loses its final slash
  mkdirhier "$vars{'TEXDIR'}";
  if (win32()) {
    TeXLive::TLWinGoo::maybe_make_ro ($vars{'TEXDIR'});
  }
  # now remove final slash from TEXDIR even if it is the root of a drive
  $vars{'TEXDIR'} =~ s!/$!!;
  # do the actual installation
  make_var_skeleton "$vars{'TEXMFSYSVAR'}";
  make_local_skeleton "$vars{'TEXMFLOCAL'}";
  mkdirhier "$vars{'TEXMFSYSCONFIG'}";
  if (win32()) {
    TeXLive::TLWinGoo::maybe_make_ro ($vars{'TEXMFSYSVAR'});
    TeXLive::TLWinGoo::maybe_make_ro ($vars{'TEXMFLOCAL'});
    TeXLive::TLWinGoo::maybe_make_ro ($vars{'TEXMFSYSCONFIG'});
  }

  if ($opt_in_place) {
    $localtlpdb = $tlpdb;
  } else {
    $localtlpdb=new TeXLive::TLPDB;
    $localtlpdb->root("$vars{'TEXDIR'}");
  }
  if (!$opt_in_place) {
    # have to do top-level release-texlive.txt as a special file, so
    # tl-update-images can insert the final version number without
    # having to remake any packages.  But if the source does not exist,
    # or the destination already exists, don't worry about it (even
    # though these cases should never arise); it's not that important.
    #
    if (-e "$::installerdir/release-texlive.txt"
        && ! -e "$vars{TEXDIR}/release-texlive.txt") {
      copy("$::installerdir/release-texlive.txt", "$vars{TEXDIR}/");
    }
    #
    calc_depends();
    save_options_into_tlpdb();
    # we need to do that dir, since we use the TLPDB->install_package which
    # might change into texmf-dist for relocated packages
    mkdirhier "$vars{'TEXDIR'}/texmf-dist";
    do_install_packages();
    if ($opt_custom_bin) {
      $vars{'this_platform'} = "custom";
      my $TEXDIR="$vars{'TEXDIR'}";
      mkdirhier("$TEXDIR/bin/custom");
      for my $f (<$opt_custom_bin/*>) {
        copy($f, "$TEXDIR/bin/custom");
      }
    }
  }
  # now we save every scheme that is fully covered by the stuff we have
  # installed to the $localtlpdb
  foreach my $s ($tlpdb->schemes) {
    my $stlp = $tlpdb->get_package($s);
    die ("This cannot happen, $s not defined in tlpdb") if ! defined($stlp);
    my $incit = 1;
    foreach my $d ($stlp->depends) {
      if (!defined($localtlpdb->get_package($d))) {
        $incit = 0;
        last;
      }
    }
    if ($incit) {
      $localtlpdb->add_tlpobj($stlp);
    }
  }
  
  # include a 00texlive.config package in the new tlpdb,
  # so that further installations and updates using the new installation
  # as the source can work.  Only include the release info, the other
  # 00texlive.config entries are not relevant for this case.
  my $tlpobj = new TeXLive::TLPOBJ;
  $tlpobj->name("00texlive.config");
  my $t = $tlpdb->get_package("00texlive.config");
  $tlpobj->depends("minrelease/" . $tlpdb->config_minrelease,
                   "release/"    . $tlpdb->config_release);
  $localtlpdb->add_tlpobj($tlpobj);  
  
  $localtlpdb->save unless $opt_in_place;

  my $errcount = do_postinst_stuff();

  #tlwarn("!!! Dummy test warning\n");
  #tlwarn("!!! Another test warning\n");
  #$errcount += 2;

  # check environment for possibly tex-related strings:
  check_env() unless $ENV{"TEXLIVE_INSTALL_ENV_NOCHECK"};

  # We do clean up in the main installation part
  # don't do this here because it closes the log file and
  # further messages (warnings, welcome) are not logged.
  # log, profile, temp files:
  # do_cleanup();

  # create_welcome(); already invoked in main program
  if (@::WARNLINES) {
    unshift @::WARNLINES, ("\nSummary of warnings:\n");
  }
  my $status = 0;
  if ($errcount > 0) {
    $status = 1;
    warn "\n$0: errors in installation reported above\n";
  }

  return $status;
} # do_installation

sub run_postinst_cmd {
  my ($cmd) = @_;
  
  info ("running $cmd ...");
  my ($out,$ret) = TeXLive::TLUtils::run_cmd ("$cmd 2>&1");
  if ($ret == 0) {
    info ("done\n");
  } else {
    info ("failed\n");
    tlwarn ("$0: $cmd failed (status $ret): $!\n");
    $ret = 1; # be sure we don't overflow the sum on anything crazy
  }
  log ($out);
  
  return $ret;
} # run_postinst_cmd


# 
# Make texmf.cnf, backup directory, cleanups, path setting, and
# (most importantly) post-install subprograms: mktexlsr, fmtutil,
# and more.  Return count of errors detected, hopefully zero.
#
sub do_postinst_stuff {
  my $TEXDIR = "$vars{'TEXDIR'}";
  my $TEXMFSYSVAR = "$vars{'TEXMFSYSVAR'}";
  my $TEXMFSYSCONFIG = "$vars{'TEXMFSYSCONFIG'}";
  my $TEXMFVAR = "$vars{'TEXMFVAR'}";
  my $TEXMFCONFIG = "$vars{'TEXMFCONFIG'}";
  my $TEXMFLOCAL = "$vars{'TEXMFLOCAL'}";
  my $tmv;

  do_texmf_cnf();

  # clean up useless files in texmf-dist/tlpkg as this is only
  # created by the relocatable packages
  if (-d "$TEXDIR/$TeXLive::TLConfig::RelocTree/tlpkg") {
    rmtree("$TEXDIR/TeXLive::TLConfig::RelocTree/tlpkg");
  }

  # create package backup directory for tlmgr autobackup to work
  mkdirhier("$TEXDIR/$TeXLive::TLConfig::PackageBackupDir");

  # final program execution
  # we have to do several things:
  # - clean the environment from spurious TEXMF related variables
  # - add the bin dir to the PATH
  # - select perl interpreter and set the correct perllib
  # - run the programs

  # Step 1: Clean the environment.
  %origenv = %ENV;
  my @TMFVARS=qw(VARTEXFONTS
    TEXMF SYSTEXMF VARTEXFONTS
    TEXMFDBS WEB2C TEXINPUTS TEXFORMATS MFBASES MPMEMS TEXPOOL MFPOOL MPPOOL
    PSHEADERS TEXFONTMAPS TEXPSHEADERS TEXCONFIG TEXMFCNF
    TEXMFMAIN TEXMFDIST TEXMFLOCAL TEXMFSYSVAR TEXMFSYSCONFIG
    TEXMFVAR TEXMFCONFIG TEXMFHOME TEXMFCACHE);

  if (defined($ENV{'TEXMFCNF'})) {
    tlwarn "WARNING: environment variable TEXMFCNF is set.
You should know what you are doing.
We will unset it for the post-install actions, but all further
operations might be disturbed.\n\n";
  }
  foreach $tmv (@TMFVARS) {
    delete $ENV{$tmv} if (defined($ENV{$tmv}));
  }

  # Step 2: Setup the PATH, switch to the new Perl

  my $pathsep = (win32)? ';' : ':';
  my $plat_bindir = "$TEXDIR/bin/$vars{'this_platform'}";
  my $perl_bindir = "$TEXDIR/tlpkg/tlperl/bin";
  my $perl_libdir = "$TEXDIR/tlpkg/tlperl/lib";
  my $progext = (win32)? '.exe' : '';

  debug("Prepending $plat_bindir to PATH\n");
  $ENV{'PATH'} = $plat_bindir . $pathsep . $ENV{'PATH'};

  if (win32) {
    debug("Prepending $perl_bindir to PATH\n");
    $ENV{'PATH'} = "$perl_bindir" . "$pathsep" . "$ENV{'PATH'}";
    $ENV{'PATH'} =~ s!/!\\!g;
  }

  debug("\nNew PATH is:\n");
  foreach my $dir (split $pathsep, $ENV{'PATH'}) {
    debug("  $dir\n");
  }
  debug("\n");
  if (win32) {
    $ENV{'PERL5LIB'} = $perl_libdir;
  }

  #
  # post install actions
  #

  my $usedtlpdb = $opt_in_place ? $tlpdb : $localtlpdb;

  if (win32()) {
    debug("Actual environment:\n" . `set` ."\n\n");
    debug("Effective TEXMFCNF: " . `kpsewhich -expand-path=\$TEXMFCNF` ."\n");
  }

  # Step 4: run the programs
  my $errcount = 0;

  if (!$opt_in_place) {
    wsystem("running", 'mktexlsr', "$TEXDIR/texmf-dist") && exit(1);
  }

  # we have to generate the various config file. That could be done with
  # texconfig generate * but Win32 does not have texconfig. But we have
  # $localtlpdb and this is simple code, so do it directly, i.e., duplicate
  # the code from the various generate-*.pl scripts

  mkdirhier "$TEXDIR/texmf-dist/web2c";
  info("writing fmtutil.cnf to $TEXDIR/texmf-dist/web2c/fmtutil.cnf\n");
  TeXLive::TLUtils::create_fmtutil($usedtlpdb,
    "$TEXDIR/texmf-dist/web2c/fmtutil.cnf");

  # warn if fmtutil-local.cnf is present
  if (-r "$TEXMFLOCAL/web2c/fmtutil-local.cnf") {
    tlwarn("Old configuration file $TEXMFLOCAL/web2c/fmtutil-local.cnf found.\n");
    tlwarn("fmtutil now reads *all* fmtutil.cnf files, so probably the easiest way\nis to rename the above file to $TEXMFLOCAL/web2c/fmtutil.cnf\n");
  }
    

  info("writing updmap.cfg to $TEXDIR/texmf-dist/web2c/updmap.cfg\n");
  TeXLive::TLUtils::create_updmap ($usedtlpdb,
    "$TEXDIR/texmf-dist/web2c/updmap.cfg");

  info("writing language.dat to $TEXMFSYSVAR/tex/generic/config/language.dat\n");
  TeXLive::TLUtils::create_language_dat($usedtlpdb,
    "$TEXMFSYSVAR/tex/generic/config/language.dat",
    "$TEXMFLOCAL/tex/generic/config/language-local.dat");

  info("writing language.def to $TEXMFSYSVAR/tex/generic/config/language.def\n");
  TeXLive::TLUtils::create_language_def($usedtlpdb,
    "$TEXMFSYSVAR/tex/generic/config/language.def",
    "$TEXMFLOCAL/tex/generic/config/language-local.def");

  info("writing language.dat.lua to $TEXMFSYSVAR/tex/generic/config/language.dat.lua\n");
  TeXLive::TLUtils::create_language_lua($usedtlpdb,
    "$TEXMFSYSVAR/tex/generic/config/language.dat.lua",
    "$TEXMFLOCAL/tex/generic/config/language-local.dat.lua");

  wsystem("running", "mktexlsr",
                     $TEXMFSYSVAR, $TEXMFSYSCONFIG, "$TEXDIR/texmf-dist")
  && exit(1);

  if (-x "$plat_bindir/updmap-sys$progext") {
    $errcount += run_postinst_cmd("updmap-sys --nohash");
  } else {
    info("not running updmap-sys (not installed)\n");
  }

  # now work through the options if specified at all
  my $env_paper = $ENV{"TEXLIVE_INSTALL_PAPER"};
  if (defined $env_paper && $env_paper eq "letter") {
    $vars{'instopt_letter'} = 1;
  } elsif (defined $env_paper && $env_paper eq "a4") {
    ; # do nothing
  } elsif ($env_paper) {
    tlwarn("$0: TEXLIVE_INSTALL_PAPER value must be letter or a4, not: "
           . "$env_paper (ignoring)\n");
  }
  # letter instead of a4
  if ($vars{'instopt_letter'}) {
    # set paper size, but do not execute any post actions, which in this
    # case would be mktexlsr and fmtutil-sys -all; clearly premature
    # here in the installer.
    info("setting default paper size to letter:\n");
    $errcount += run_postinst_cmd("tlmgr --no-execute-actions paper letter");
  }

  # option settings in launcher.ini
  if (win32() && !$vars{'instopt_portable'}) {
    if ($vars{'tlpdbopt_file_assocs'} != 1 || !$vars{'instopt_adjustpath'}) {
      # create higher priority tlaunch.ini with adjusted settings
      # whether or not launcher mode (desktop integration 2)
      # was selected
      rewrite_tlaunch_ini();
    }
  }

  # now rerun mktexlsr for updmap-sys and tlmgr paper letter updates.
  wsystem("re-running", "mktexlsr", $TEXMFSYSVAR, $TEXMFSYSCONFIG) && exit(1);

  if (win32() and !$vars{'instopt_portable'} and !$opt_in_place) {
    if ($vars{'tlpdbopt_desktop_integration'} != 2) {
      create_uninstaller($vars{'TEXDIR'});
    } else {
      $errcount += wsystem (
        'Running','tlaunch.exe',
        admin() ? 'admin_inst_silent' : 'user_inst_silent');
    }
  }

  # luatex/context setup.
  if (exists($install{"context"}) && $install{"context"} == 1
      && -x "$plat_bindir/texlua$progext"
      && !exists $ENV{"TEXLIVE_INSTALL_NO_CONTEXT_CACHE"}) {
    info("setting up ConTeXt cache: ");
    $errcount += run_postinst_cmd("mtxrun --generate");
  }

  # all formats option
  if ($vars{'tlpdbopt_create_formats'}) {
    if (-x "$plat_bindir/fmtutil-sys$progext") {
      info("pre-generating all format files, be patient...\n");
      $errcount += run_postinst_cmd(
                     "fmtutil-sys $common_fmtutil_args --no-strict --all");
    } else {
      info("not running fmtutil-sys (not installed)\n");
    }
  }

  # do path adjustments: On Windows add/remove to PATH etc,
  # on Unix set symlinks
  # for portable, this option should be unset
  # it should not be necessary to test separately for portable
  $errcount += do_path_adjustments() if
    $vars{'instopt_adjustpath'} and $vars{'tlpdbopt_desktop_integration'} != 2;

  # now do the system integration:
  # on unix this means setting up symlinks
  # on w32 this means settting registry values
  # on both, we run the postaction directives of the tlpdb
  # no need to test for portable or in_place:
  # the menus (or profile?) should have set the required options
  $errcount += do_tlpdb_postactions();
  
  return $errcount;
} # do_postinst_stuff


# Run the post installation code in the postaction tlpsrc entries.
# Return number of errors found, or zero.

sub do_tlpdb_postactions {
  info ("running package-specific postactions\n");

  # option settings already reflect portable- and in_place options.
  my $usedtlpdb = $opt_in_place ? $tlpdb : $localtlpdb;
  my $ret = 0; # n. of errors

  foreach my $package ($usedtlpdb->list_packages) {
    # !!! alert: parameter 4 is menu shortcuts, parameter 5 does nothing !!!
    if ($vars{'tlpdbopt_desktop_integration'}==2) {
      # skip creation of shortcuts and file associations
      if (!TeXLive::TLUtils::do_postaction(
        "install", $usedtlpdb->get_package($package),
        0, 0, 0, $vars{'tlpdbopt_post_code'})) { $ret += 1; }
    } else {
      # create shortcuts and file associations
      # according to corresponding options
      if (!TeXLive::TLUtils::do_postaction(
        "install", $usedtlpdb->get_package($package),
        $vars{'tlpdbopt_file_assocs'},
        $vars{'tlpdbopt_desktop_integration'}, 0,
        $vars{'tlpdbopt_post_code'})) { $ret += 1; }
    }
  }
  # windows: alert the system about changed file associations
  if (win32) { TeXLive::TLWinGoo::update_assocs(); }
  info ("finished with package-specific postactions\n");
  return $ret;
} # do_tlpdb_postactions

sub rewrite_tlaunch_ini {
  # create a higher-priority copy of tlaunch.ini in TEXMFSYSVAR
  # with appropriate settings in the General section
  my $ret = 0; # n. of errors

  chomp( my $tmfmain = `kpsewhich -var-value=TEXMFMAIN` ) ;
  chomp( my $tmfsysvar = `kpsewhich -var-value=TEXMFSYSVAR` ) ;
  if (open IN, "$tmfmain/web2c/tlaunch.ini") {
    my $eolsave = $/;
    undef $/;
    my $ini = <IN>;
    close IN;
    # remove general section, if any
    $ini =~ s/\r\n/\n/g;
    $ini =~ s/\[general[^\[]*//si;
    mkdirhier("$tmfsysvar/web2c");
    if (open OUT, ">", "$tmfsysvar/web2c/tlaunch.ini") {
      my @fts = ('none', 'new', 'overwrite');
      $\ = "\n";
      print OUT $ini;
      print OUT "[General]";
      print OUT "FILETYPES=$fts[$vars{'tlpdbopt_file_assocs'}]";
      print OUT "SEARCHPATH=$vars{'instopt_adjustpath'}\n";
      close OUT;
      `mktexlsr $tmfsysvar`;
    } else {
      $ret += 1;
      tlwarn("Cannot write modified tlaunch.ini\n");
    }
    $/ = $eolsave;
  } else {
    $ret += 1;
    tlwarn("Cannot open tlaunch.ini for reading\n");
  }
  return $ret;
} # rewrite_tlaunch_ini

sub do_path_adjustments {
  my $ret = 0;
  info ("running path adjustment actions\n");
  if (win32()) {
    TeXLive::TLUtils::w32_add_to_path($vars{'TEXDIR'}.'/bin/win32',
      $vars{'tlpdbopt_w32_multi_user'});
    broadcast_env();
  } else {
    if ($F_OK != TeXLive::TLUtils::add_symlinks($vars{'TEXDIR'}, 
         $vars{'this_platform'},
         $vars{'tlpdbopt_sys_bin'}, $vars{'tlpdbopt_sys_man'},
         $vars{'tlpdbopt_sys_info'})) {
      $ret = 1;
    }
  }
  info ("finished with path adjustment actions\n");
  return $ret;
} # do_path_adjustments


# we have to adjust the texmf.cnf file to the paths set in the configuration!
sub do_texmf_cnf {
  open(TMF,"<$vars{'TEXDIR'}/texmf-dist/web2c/texmf.cnf")
      or die "$vars{'TEXDIR'}/texmf-dist/web2c/texmf.cnf not found: $!";
  my @texmfcnflines = <TMF>;
  close(TMF);

  my @changedtmf = ();  # install to disk: write only changed items

  my $yyyy = $TeXLive::TLConfig::ReleaseYear;

  # we have to find TEXMFLOCAL TEXMFSYSVAR and TEXMFHOME
  foreach my $line (@texmfcnflines) {
    if ($line =~ m/^TEXMFLOCAL\b/) { # don't find TEXMFLOCALEDIR
      # by default TEXMFLOCAL = TEXDIR/../texmf-local, if this is the case
      # we don't have to write a new setting.
      my $deftmlocal = dirname($vars{'TEXDIR'});
      $deftmlocal .= "/texmf-local";
      if ("$vars{'TEXMFLOCAL'}" ne "$deftmlocal") {
        push @changedtmf, "TEXMFLOCAL = $vars{'TEXMFLOCAL'}\n";
      }
    } elsif ($line =~ m/^TEXMFSYSVAR/) {
      if ("$vars{'TEXMFSYSVAR'}" ne "$vars{'TEXDIR'}/texmf-var") {
        push @changedtmf, "TEXMFSYSVAR = $vars{'TEXMFSYSVAR'}\n";
      }
    } elsif ($line =~ m/^TEXMFSYSCONFIG/) {
      if ("$vars{'TEXMFSYSCONFIG'}" ne "$vars{'TEXDIR'}/texmf-config") {
        push @changedtmf, "TEXMFSYSCONFIG = $vars{'TEXMFSYSCONFIG'}\n";
      }
    } elsif ($line =~ m/^TEXMFVAR/) {
      if ($vars{"TEXMFVAR"} ne "~/.texlive$yyyy/texmf-var") {
        push @changedtmf, "TEXMFVAR = $vars{'TEXMFVAR'}\n";
      }
    } elsif ($line =~ m/^TEXMFCONFIG/) {
      if ("$vars{'TEXMFCONFIG'}" ne "~/.texlive$yyyy/texmf-config") {
        push @changedtmf, "TEXMFCONFIG = $vars{'TEXMFCONFIG'}\n";
      }
    } elsif ($line =~ m/^TEXMFHOME/) {
      if ("$vars{'TEXMFHOME'}" ne "~/texmf") {
        push @changedtmf, "TEXMFHOME = $vars{'TEXMFHOME'}\n";
      }
    } elsif ($line =~ m/^OSFONTDIR/) {
      if (win32()) {
        push @changedtmf, "OSFONTDIR = \$SystemRoot/fonts//\n";
      }
    }
  }

  if ($vars{'instopt_portable'}) {
    push @changedtmf, "ASYMPTOTE_HOME = \$TEXMFCONFIG/asymptote\n";
  }

  my ($TMF, $TMFLUA);
  # we want to write only changes to texmf.cnf
  # even for in_place installation
  $TMF = ">$vars{'TEXDIR'}/texmf.cnf";
  open(TMF, $TMF) || die "open($TMF) failed: $!";
  print TMF <<EOF;
% (Public domain.)
% This texmf.cnf file should contain only your personal changes from the
% original texmf.cnf (for example, as chosen in the installer).
%
% That is, if you need to make changes to texmf.cnf, put your custom
% settings in this file, which is .../texlive/YYYY/texmf.cnf, rather than
% the distributed file (which is .../texlive/YYYY/texmf-dist/web2c/texmf.cnf).
% And include *only* your changed values, not a copy of the whole thing!
%
EOF
  foreach (@changedtmf) {
    # avoid absolute paths for TEXDIR, use $SELFAUTOPARENT instead
    s/^(TEXMF\w+\s*=\s*)\Q$vars{'TEXDIR'}\E/$1\$SELFAUTOPARENT/;
    print TMF;
  }
  #
  # save the setting of shell_escape to the generated system texmf.cnf
  # default in texmf-dist/web2c/texmf.cnf is
  #   shell_escape = p
  # so we write that only if the user *deselected* this option
  if (!$vars{"instopt_write18_restricted"}) {
    print TMF <<EOF;

% Disable system commands via \\write18{...}.  See texmf-dist/web2c/texmf.cnf.
shell_escape = 0
EOF
;
  }

  # external perl for third-party scripts?
  # the wrapper batchfile has set the environment variable extperl
  # to its version if available and 0 otherwise.
  if (win32) {
    my $use_ext = 0;
    if (!$vars{'instopt_portable'} &&
          defined $ENV{'extperl'} &&  $ENV{'extperl'} =~ /^(\d+\.\d+)/) {
      $use_ext = 1 if $1 >= 5.14;
    }
    print TMF <<EOF;

% Prefer external Perl for third-party TeXLive Perl scripts
% Was set to 1 if at install time a sufficiently recent Perl was detected.
EOF
;
    print TMF "TEXLIVE_WINDOWS_TRY_EXTERNAL_PERL = " . $use_ext;
    log("Configuring for using external perl for third-party scripts\n")
  }

  close(TMF) || warn "close($TMF) failed: $!";

  $TMFLUA = ">$vars{'TEXDIR'}/texmfcnf.lua";
  open(TMFLUA, $TMFLUA) || die "open($TMFLUA) failed: $!";
    print TMFLUA <<EOF;
-- (Public domain.)
-- This texmfcnf.lua file should contain only your personal changes from the
-- original texmfcnf.lua (for example, as chosen in the installer).
--
-- That is, if you need to make changes to texmfcnf.lua, put your custom
-- settings in this file, which is .../texlive/YYYY/texmfcnf.lua, rather than
-- the distributed file (.../texlive/YYYY/texmf-dist/web2c/texmfcnf.lua).
-- And include *only* your changed values, not a copy of the whole thing!

return { 
  content = {
    variables = {
EOF
;
  foreach (@changedtmf) {
    my $luavalue = $_;
    $luavalue =~ s/^(\w+\s*=\s*)(.*)\s*$/$1\"$2\",/;
    $luavalue =~ s/\$SELFAUTOPARENT/selfautoparent:/g;
    print TMFLUA "      $luavalue\n";
  }
  print TMFLUA "    },\n";
  print TMFLUA "  },\n";
  if (!$vars{"instopt_write18_restricted"}) {
    print TMFLUA <<EOF;
  directives = {
       -- Disable system commands.  See texmf-dist/web2c/texmfcnf.lua
    ["system.commandmode"]       = "none",
  },
EOF
;
  }
  print TMFLUA "}\n";
  close(TMFLUA) || warn "close($TMFLUA) failed: $!";
} # do_texmf_cnf


sub dump_vars {
  my $filename=shift;
  my $fh;
  if (ref($filename)) {
    $fh = $filename;
  } else {
    open VARS, ">$filename";
    $fh = \*VARS;
  }
  foreach my $key (keys %vars) {
    print $fh "$key $vars{$key}\n";
  }
  close VARS if (!ref($filename));
  debug("\n%vars dumped to '$filename'.\n");
} # dump_vars


# Determine which platforms are supported.
sub set_platforms_supported {
  my @binaries = $tlpdb->available_architectures;
  for my $binary (@binaries) {
    unless (defined $vars{"binary_$binary"}) {
      $vars{"binary_$binary"}=0;
    }
  }
  for my $key (keys %vars) {
    ++$vars{'n_systems_available'} if ($key=~/^binary/);
  }
} # set_platforms_supported

# Environment variables and default values on UNIX:
#   TEXLIVE_INSTALL_PREFIX         /usr/local/texlive   => $tex_prefix
#   TEXLIVE_INSTALL_TEXDIR         $tex_prefix/2010     => $TEXDIR
#   TEXLIVE_INSTALL_TEXMFSYSVAR    $TEXDIR/texmf-var
#   TEXLIVE_INSTALL_TEXMFSYSCONFIG $TEXDIR/texmf-config
#   TEXLIVE_INSTALL_TEXMFLOCAL     $tex_prefix/texmf-local
#   TEXLIVE_INSTALL_TEXMFHOME      '$HOME/texmf'
#   TEXLIVE_INSTALL_TEXMFVAR       ~/.texlive2010/texmf-var
#   TEXLIVE_INSTALL_TEXMFCONFIG    ~/.texlive2010/texmf-config

sub set_var_from_alternatives {
  my ($whatref, @alternatives) = @_;
  my $final;
  while (@alternatives) {
    my $el = pop @alternatives;
    $final = $el if ($el);
  }
  $$whatref = $final;
}

sub set_standard_var {
  my ($what, $envstr, $default) = @_;
  # warn if a value was set from both the profile and
  # via env var
  my $envvar = getenv($envstr);
  if ($vars{$what} && $envvar && $vars{$what} ne $envvar) {
    tlwarn("Trying to define $what via conflicting settings:\n");
    tlwarn("  from envvar $envvar = $envvar($envstr)\n");
    tlwarn("  from profile = $vars{$what}\n");
    tlwarn("  Preferring the profile value!\n");
    $envvar = undef;
  }
  # default for most variables is in increasing priority
  # - some default
  # - setting from profile saved already in $vars{$what}
  # - environment variable
  set_var_from_alternatives( \$vars{$what},
    $envvar,
    $vars{$what},
    $default);
}

sub set_texlive_default_dirs {
  my $homedir = (platform() =~ m/darwin/) ? "~/Library" : "~";
  my $yyyy = $TeXLive::TLConfig::ReleaseYear;
  #
  my $tlprefixenv = getenv('TEXLIVE_INSTALL_PREFIX');
  if ($tlprefixenv && $vars{'TEXDIR'}) {
    # NOTE we cannot compare these two values because the one might
    # contain the YYYY part (TEXDIR) while the other is the one without.
    tlwarn("Trying to set up basic path using two incompatible methods:\n");
    tlwarn("  from envvar TEXLIVE_INSTALL_PREFIX = $tlprefixenv\n");
    tlwarn("  from profile TEXDIR = $vars{'TEXDIR'}\n");
    tlwarn("  Preferring the profile value!\n");
    $tlprefixenv = undef;
  }
  # first set $tex_prefix
  my $tex_prefix;
  set_var_from_alternatives( \$tex_prefix,
    ($opt_in_place ? abs_path($::installerdir) : undef),
    $tlprefixenv,
    (win32() ? getenv('SystemDrive') . '/texlive' : '/usr/local/texlive'));
  set_var_from_alternatives( \$vars{'TEXDIR'},
    $vars{'TEXDIR'},
    ($vars{'instopt_portable'} || $opt_in_place)
      ? $tex_prefix : "$tex_prefix/$texlive_release");
  set_standard_var('TEXMFSYSVAR', 'TEXLIVE_INSTALL_TEXMFSYSVAR',
    $vars{'TEXDIR'} . '/texmf-var');
  set_standard_var('TEXMFSYSCONFIG', 'TEXLIVE_INSTALL_TEXMFSYSCONFIG',
    $vars{'TEXDIR'} . '/texmf-config');
  set_standard_var('TEXMFLOCAL', 'TEXLIVE_INSTALL_TEXMFLOCAL',
    "$tex_prefix/texmf-local");
  set_standard_var('TEXMFHOME', 'TEXLIVE_INSTALL_TEXMFHOME',
    "$homedir/texmf");
  set_standard_var('TEXMFVAR', 'TEXLIVE_INSTALL_TEXMFVAR',
    (platform() =~ m/darwin/)
      ? "$homedir/texlive/$yyyy/texmf-var"
      : "$homedir/.texlive$yyyy/texmf-var");
  set_standard_var('TEXMFCONFIG', 'TEXLIVE_INSTALL_TEXMFCONFIG',
    (platform() =~ m/darwin/)
      ? "$homedir/texlive/$yyyy/texmf-config"
      : "$homedir/.texlive$yyyy/texmf-config");

  # for portable installation we want everything in one directory
  if ($vars{'instopt_portable'}) {
    $vars{'TEXMFHOME'}   = "\$TEXMFLOCAL";
    $vars{'TEXMFVAR'}    = "\$TEXMFSYSVAR";
    $vars{'TEXMFCONFIG'} = "\$TEXMFSYSCONFIG";
  }
} # set_texlive_default_dirs

sub calc_depends {
  # we have to reset the install hash EVERY TIME otherwise everything will
  # always be installed since the default is scheme-full which selects
  # all packages and never deselects it
  %install=();
  my $p;
  my $a;

  # initialize the %install hash with what should be installed

  if ($vars{'selected_scheme'} ne "scheme-custom") {
    # First look for packages in the selected scheme.
    my $scheme=$tlpdb->get_package($vars{'selected_scheme'});
    if (!defined($scheme)) {
      if ($vars{'selected_scheme'}) {
        # something is written in the selected scheme but not defined, that
        # is strange, so warn and die
        die ("Scheme $vars{'selected_scheme'} not defined, vars:\n");
        dump_vars(\*STDOUT);
      }
    } else {
      for my $scheme_content ($scheme->depends) {
        $install{"$scheme_content"}=1 unless ($scheme_content=~/^collection-/);
      }
    }
  }

  # Now look for collections in the %vars hash.  These are not
  # necessarily the collections required by a scheme.  The final
  # decision is made in the collections/languages menu.
  foreach my $key (keys %vars) {
    if ($key=~/^collection-/) {
      $install{$key} = 1 if $vars{$key};
    }
  }

  # compute the list of archs to be installed
  my @archs;
  foreach (keys %vars) {
    if (m/^binary_(.*)$/ ) {
      if ($vars{$_}) { push @archs, $1; }
    }
  }

  #
  # work through the addon settings in the %vars hash
  #if ($vars{'addon_editor'}) {
  #  $install{"texworks"} = 1;
  #}

  # if programs for arch=win32 are installed we also have to install
  # tlperl.win32 which provides the "hidden" perl that will be used
  # to run all the perl scripts.
  # Furthermore we install tlgs.win32 and tlpsv.win32, too
  if (grep(/^win32$/,@archs)) {
    $install{"tlperl.win32"} = 1;
    $install{"tlgs.win32"} = 1;
    $install{"tlpsv.win32"} = 1;
  }

  # loop over all the packages until it is getting stable
  my $changed = 1;
  while ($changed) {
    # set $changed to 0
    $changed = 0;

    # collect the already selected packages
    my @pre_selected = keys %install;
    debug("initial number of installations: $#pre_selected\n");

    # loop over all the pre_selected and add them
    foreach $p (@pre_selected) {
      ddebug("pre_selected $p\n");
      my $pkg = $tlpdb->get_package($p);
      if (!defined($pkg)) {
        tlwarn("$p is mentioned somewhere but not available, disabling it.\n");
        $install{$p} = 0;
        next;
      }
      foreach my $p_dep ($tlpdb->get_package($p)->depends) {
        if ($p_dep =~ m/^(.*)\.ARCH$/) {
          my $foo = "$1";
          foreach $a (@archs) {
            $install{"$foo.$a"} = 1 if defined($tlpdb->get_package("$foo.$a"));
          }
        } elsif ($p_dep =~ m/^(.*)\.win32$/) {
          # a win32 package should *only* be installed if we are installing
          # the win32 arch
          if (grep(/^win32$/,@archs)) {
            $install{$p_dep} = 1;
          }
        } else {
          $install{$p_dep} = 1;
        }
      }
    }

    # check for newly selected packages
    my @post_selected = keys %install;
    debug("number of post installations: $#post_selected\n");

    # set repeat condition
    if ($#pre_selected != $#post_selected) {
      $changed = 1;
    }
  }

  # now do the size computation
  my $size = 0;
  foreach $p (keys %install) {
    my $tlpobj = $tlpdb->get_package($p);
    if (not(defined($tlpobj))) {
      tlwarn("$p should be installed but "
             . "is not in texlive.tlpdb; disabling.\n");
      $install{$p} = 0;
      next;
    }
    $size+=$tlpobj->docsize if $vars{'tlpdbopt_install_docfiles'};
    $size+=$tlpobj->srcsize if $vars{'tlpdbopt_install_srcfiles'};
    $size+=$tlpobj->runsize;
    foreach $a (@archs) {
      $size += $tlpobj->binsize->{$a} if defined($tlpobj->binsize->{$a});
    }
  }
  $vars{'total_size'} =
    sprintf "%d", ($size * $TeXLive::TLConfig::BlockSize)/1024**2;
} # calc_depends

sub load_tlpdb {
  my $master = $location;
  info("Loading $master/$TeXLive::TLConfig::InfraLocation/$TeXLive::TLConfig::DatabaseName\n");
  $tlpdb = TeXLive::TLPDB->new(
    root => $master, 'verify' => $opt_verify_downloads);
  if (!defined($tlpdb)) {
    my $do_die = 1;
    # if that failed, and:
    # - we are installing from the network
    # - the location string does not contain "tlnet"
    # then we simply add "/systems/texlive/tlnet" in case someone just
    # gave an arbitrary CTAN mirror address without the full path
    if ($media eq "NET" && $location !~ m/tlnet/) {
      tlwarn("First attempt for net installation failed;\n");
      tlwarn("  repository url does not contain \"tlnet\",\n");
      tlwarn("  retrying with \"/systems/texlive/tlnet\" appended.\n");
      $location .= "/systems/texlive/tlnet";
      $master = $location;
      #
      # since we change location, we reset the error count of the
      # download object
      $::tldownload_server->enable if defined($::tldownload_server);
      #
      $tlpdb = TeXLive::TLPDB->new(
        root => $master, 'verify' => $opt_verify_downloads);
      if (!defined($tlpdb)) {
        tlwarn("Oh well, adding tlnet did not help.\n");
        tlwarn(<<END_EXPLICIT_MIRROR);

You may want to try specifying an explicit or different CTAN mirror;
see the information and examples for the -repository option at
https://tug.org/texlive/doc/install-tl.html
(or in the output of install-tl --help).

You can also rerun the installer with -select-repository
to choose a mirror from a menu.

END_EXPLICIT_MIRROR
      } else {
        # hurray, that worked out
        info("Loading $master/$TeXLive::TLConfig::InfraLocation/$TeXLive::TLConfig::DatabaseName\n");
        $do_die = 0;
      }
    }
    #die "$0: Could not load TeX Live Database from $master, goodbye.\n"
    return 0
      if $do_die;
  }
  # set the defaults to what is specified in the tlpdb
  # since we might have loaded values via -init-from-profile,
  # make sure that we don't overwrite default values
  for my $o (keys %TeXLive::TLConfig::TLPDBOptions) {
    $vars{"tlpdbopt_$o"} = $tlpdb->option($o)
      if (!defined($profiledata{"tlpdbopt_$o"}));
  }
  if (win32()) {
    # below, we really mean (start) menu integration.
    # 2016: always menu shortcuts, never desktop shortcuts, whatever the setting
    # 2017: new option value 2: launcher instead of menu.
    # in portable case, shortcuts sanitized away elsewhere
    $vars{'tlpdbopt_desktop_integration'} = 1;
    # we have to make sure that this option is set to 0 in case
    # that a non-admin is running the installations program
    $vars{'tlpdbopt_w32_multi_user'} = 0 if (!admin());
  }

  # select scheme: either $vars{'selected_scheme'} or $default_scheme
  # check that the default scheme is actually present, otherwise switch to
  # scheme-minimal
  my $selscheme = defined($vars{'selected_scheme'}) ? $vars{'selected_scheme'}
                                                    : $default_scheme;
  if (!defined($tlpdb->get_package($selscheme))) {
    if (!defined($tlpdb->get_package("scheme-minimal"))) {
      die("Aborting, cannot find either $selscheme or scheme-minimal");
    }
    $default_scheme = "scheme-minimal";
    $vars{'selected_scheme'} = $default_scheme;
  }
  # make sure that we update %vars for collection_* if only selected_scheme
  # is there, but no collection information
  my $found_collection = 0;
  for my $k (keys(%vars)) {
    if ($k =~ m/^collection-/) {
      $found_collection = 1;
      last;
    }
  }
  if (!$found_collection) {
    for my $p ($tlpdb->get_package($vars{'selected_scheme'})->depends) {
      $vars{$p} = 1 if ($p =~ m/^collection-/);
    }
  }
  return 1;
} # load_tlpdb

sub initialize_collections {
  foreach my $pkg ($tlpdb->list_packages) {
    my $tlpobj = $tlpdb->{'tlps'}{$pkg};
    if ($tlpobj->category eq "Collection") {
      $vars{"$pkg"} = 0 if (!defined($vars{$pkg}));
      ++$vars{'n_collections_available'};
      push (@collections_std, $pkg);
    }
  }
  my $selscheme = ($vars{'selected_scheme'} || $default_scheme);
  my $scheme_tlpobj = $tlpdb->get_package($selscheme);
  if (defined ($scheme_tlpobj)) {
    $vars{'n_collections_selected'}=0;
    foreach my $dependent ($scheme_tlpobj->depends) {
      if ($dependent=~/^(collection-.*)/) {
        $vars{"$1"}=1;
      }
    }
  }
  for my $c (keys(%vars)) {
    if ($c =~ m/^collection-/ && $vars{$c}) {
      ++$vars{'n_collections_selected'};
    }
  }
  if ($vars{"binary_win32"}) {
    $vars{"collection-wintools"} = 1;
    ++$vars{'n_collections_selected'};
  }
} # initialize_collections

sub set_install_platform {
  my $detected_platform=platform;
  if ($opt_custom_bin) {
    $detected_platform = "custom";
  }
  my $warn_nobin;
  my $warn_nobin_x86_64_linux;
  my $nowarn="";
  my $wp='***'; # warning prefix

  $warn_nobin="\n$wp WARNING: No binaries for your platform found.  ";
  $warn_nobin_x86_64_linux="$warn_nobin" .
      "$wp No binaries for x86_64-linux found, using i386-linux instead.\n";

  my $ret = $warn_nobin;
  if (defined $vars{"binary_$detected_platform"}) {
    $vars{"binary_$detected_platform"}=1;
    $vars{'inst_platform'}=$detected_platform;
    $ret = $nowarn;
  } elsif ($detected_platform eq 'x86_64-linux') {
    $vars{'binary_i386-linux'}=1;
    $vars{'inst_platform'}='i386-linux';
    $ret = $warn_nobin_x86_64_linux;
  } else {
    if ($opt_custom_bin) {
      $ret = "$wp Using custom binaries from $opt_custom_bin.\n";
    } else {
      $ret = $warn_nobin;
    }
  }
  foreach my $key (keys %vars) {
    if ($key=~/^binary.*/) {
       ++$vars{'n_systems_selected'} if $vars{$key}==1;
    }
  }
  return($ret);
} # set_install_platform

sub create_profile {
  my $profilepath = shift;
  # The file "TLprofile" is created at the beginning of the
  # installation process and contains information about the current
  # setup.  The purpose is to allow non-interactive installations.
  my $fh;
  if (ref($profilepath)) {
    $fh = $profilepath;
  } else {
    open PROFILE, ">$profilepath";
    $fh = \*PROFILE;
  }
  #
  # determine whether the set of selected collections exactly 
  # agrees with the selected scheme. In this case we do *not*
  # save the actual collection setting but only the selected
  # scheme, as reading the profile will load all collections
  # if only the scheme is given.
  my %instcols;
  foreach my $key (sort keys %vars) {
    $instcols{$key} = 1 if $key=~/^collection/ and $vars{$key}==1;
  }
  # for anything but "scheme-custom" we delete the contained
  # collections from the list
  if ($vars{'selected_scheme'} ne "scheme-custom") {
    my $scheme=$tlpdb->get_package($vars{'selected_scheme'});
    if (!defined($scheme)) {
      die ("Scheme $vars{selected_scheme} not defined.\n");
    }
    for my $scheme_content ($scheme->depends) {
      delete($instcols{"$scheme_content"}) if ($scheme_content=~/^collection-/);
    }
  }
  # if there are still collection left, we keep all of them
  my $save_cols = (keys(%instcols) ? 1 : 0);

  # start
  my $tim = gmtime(time);
  print $fh "# texlive.profile written on $tim UTC\n";
  print $fh "# It will NOT be updated and reflects only the\n";
  print $fh "# installation profile at installation time.\n";
  print $fh "selected_scheme $vars{selected_scheme}\n";
  foreach my $key (sort keys %vars) {
    print $fh "$key $vars{$key}\n"
        if $save_cols and $key=~/^collection/ and $vars{$key}==1;
    # we don't save tlpdbopt_location
    next if ($key eq "tlpdbopt_location");
    print $fh "$key $vars{$key}\n" if $key =~ /^tlpdbopt_/;
    print $fh "$key $vars{$key}\n" if $key =~ /^instopt_/;
    print $fh "$key $vars{$key}\n" if defined($path_keys{$key});
    print $fh "$key $vars{$key}\n" if (($key =~ /^binary_/) && $vars{$key});
  }
  if (!ref($profilepath)) {
    close PROFILE;
  }
} # create_profile

sub read_profile {
  my $profilepath = shift;
  my %opts = @_;
  my %keyrename = (
    'option_doc'        => 'tlpdbopt_install_docfiles',
    'option_fmt'        => 'tlpdbopt_create_formats',
    'option_src'        => 'tlpdbopt_install_srcfiles',
    'option_sys_bin'    => 'tlpdbopt_sys_bin',
    'option_sys_info'   => 'tlpdbopt_sys_info',
    'option_sys_man'    => 'tlpdbopt_sys_man',
    'option_file_assocs' => 'tlpdbopt_file_assocs',
    'option_backupdir'  => 'tlpdbopt_backupdir',
    'option_w32_multi_user' => 'tlpdbopt_w32_multi_user',
    'option_post_code'  => 'tlpdbopt_post_code',
    'option_autobackup' => 'tlpdbopt_autobackup',
    'option_desktop_integration' => 'tlpdbopt_desktop_integration',
    'option_adjustrepo' => 'instopt_adjustrepo',
    'option_letter'     => 'instopt_letter',
    'option_path'       => 'instopt_adjustpath',
    'option_symlinks'   => 'instopt_adjustpath',
    'portable'          => 'instopt_portable',
    'option_write18_restricted' => 'instopt_write18_restricted',
  );
  my %keylost = (
    'option_menu_integration' => 1,
    'in_place' => 1,
  );

  open PROFILE, "<$profilepath"
    or die "$0: Cannot open profile $profilepath for reading.\n";
  # %pro is used to see whether there are non-recognized keys,
  # while %profiledata is used to make sure that the values
  # from the tlpdb do not overwrite -seed-profile values.
  my %pro;
  while (<PROFILE>) {
    chomp;
    next if m/^[[:space:]]*$/; # skip empty lines
    next if m/^[[:space:]]*#/; # skip comment lines
    s/^[[:space:]]+//;         # ignore leading (but not trailing) whitespace
    my ($k,$v) = split (" ", $_, 2); # value might have spaces
    # skip TEXDIRW, seems not used anymore, but might be around
    # in some profiles
    next if ($k eq "TEXDIRW");
    # convert old keys to new keys
    $k = $keyrename{$k} if ($keyrename{$k});
    if ($keylost{$k}) {
      tlwarn("Profile key `$k' is now ignored, please remove it.\n");
      next;
    }
    $pro{$k} = $v;
    $profiledata{$k} = $v;
  }
  foreach (keys %vars) {
    # clear out collections from var, just to be sure
    if (m/^collection-/) { $vars{$_} = 0; }
  }
  # initialize installer and tlpdb options
  foreach (keys %pro) {
    if (m/^instopt_/) {
      if (defined($vars{$_})) {
        $vars{$_} = $pro{$_};
        delete($pro{$_});
      }
    } elsif (m/^tlpdbopt_/) {
      my $o = $_;
      $o =~ s/^tlpdbopt_//;
      # we do not support setting the location in the profile
      # could be done, but might be tricky ..
      next if ($o eq 'location');
      if (defined($TeXLive::TLConfig::TLPDBOptions{$o})) {
        $vars{$_} = $pro{$_};
        delete($pro{$_});
      }

    } elsif (defined($path_keys{$_}) || m/^selected_scheme$/) {
      if ($pro{$_}) {
        $vars{$_} = $pro{$_};
        delete($pro{$_});
      } else {
        tldie("$0: Quitting, profile key for path $_ must not be empty.\n");
      }
    
    } elsif (m/^(binary|collection-)/) {
      if ($pro{$_} =~ /^[01]$/) {
        $vars{$_} = $pro{$_};
        delete($pro{$_});
      } else {
        tldie("$0: Quitting, profile key for $_ must be 0 or 1, not: $pro{$_}\n");
      }
    }
  }
  #require Data::Dumper;
  #$Data::Dumper::Indent = 1;
  #print Data::Dumper->Dump([\%vars], [qw(vars)]);
  #
  # if there are still keys in the %pro array, some unknown keys have
  # been written in the profile, bail out
  if (my @foo = keys(%pro)) {
    tlwarn("Unknown key(s) in profile $profilepath: @foo\n");
    tlwarn("Stopping here.\n");
    exit 1;
  }

  # if a profile contains *only* the selected_scheme setting without
  # any collection, we assume that exactely that scheme should be installed
  my $coldefined = 0;
  foreach my $k (keys %profiledata) {
    if ($k =~ m/^collection-/) {
      $coldefined = 1;
      last;
    }
  }
  # if we are in seed mode, do not try to load remote db as it is 
  # not initialized by now
  return if $opts{'seed'};
  #
  # check whether the collections are actually present in case of
  # changes on the server
  foreach my $k (keys %profiledata) {
    if ($k =~ m/^collection-/) {
      if (!defined($tlpdb->get_package($k))) {
        tlwarn("The profile references a non-existing collection: $k\n");
        tlwarn("Exiting.\n");
        exit(1);
      }
    }
  }
  # if at least one collection has been defined return here
  return if $coldefined;
  # since no collections have been defined in the profile, we
  # set those to be installed on which the scheme depends
  my $scheme=$tlpdb->get_package($vars{'selected_scheme'});
  if (!defined($scheme)) {
    dump_vars(\*STDOUT);
    die ("Scheme $vars{selected_scheme} not defined.\n");
  }
  for my $scheme_content ($scheme->depends) {
    $vars{"$scheme_content"}=1 if ($scheme_content=~/^collection-/);
  }
} # read_profile

sub do_install_packages {
  # let's install the critical packages first, since they are the most
  # likely to fail (so let's fail early), and nothing is usable without them.
  my @what = ();
  foreach my $package (sort {
      if ($a =~ /$CriticalPackagesRegexp/) {
        if ($b =~ /$CriticalPackagesRegexp/) {
          return $a cmp $b; # both critical
        } else {
          return -1; # critical before non-critical
        }
      } elsif ($b =~ /$CriticalPackagesRegexp/) {
        return 1; # critical before non-critical 
      } else {
        return $a cmp $b;
      }
    } keys %install) {
    push (@what, $package) if ($install{$package} == 1);
  }
  # temporary unset the localtlpdb options responsible for
  # running all kind of postactions, since install_packages
  # would call them without the PATH already set up
  # we are doing this anyway in do_postinstall_actions
  $localtlpdb->option ("desktop_integration", "0");
  $localtlpdb->option ("file_assocs", "0");
  $localtlpdb->option ("post_code", "0");
  if (!install_packages($tlpdb,$media,$localtlpdb,\@what,
                        $vars{'tlpdbopt_install_srcfiles'},
                        $vars{'tlpdbopt_install_docfiles'})) {
    my $profile_name = "installation.profile";
    create_profile($profile_name);
    tlwarn("Installation failed.\n");
    tlwarn("Rerunning the installer will try to restart the installation.\n");
    if (-r $profile_name) {
      # only suggest rerunning with the profile if it exists.
      tlwarn("Or you can restart by running the installer with:\n");
      my $repostr = ($opt_location ? " --repository $location" : "");
      my $args = "--profile $profile_name [YOUR-EXTRA-ARGS]";
      if (win32()) {
        tlwarn("  install-tl-windows.bat$repostr $args\n"
              ."or\n"
              ."  install-tl-advanced.bat$repostr $args\n");
      } else {
        tlwarn("  install-tl$repostr $args\n");
      }
    }
    flushlog();
    exit(1);
  }
  # restore options in tlpdb
  $localtlpdb->option (
    "desktop_integration", $vars{'tlpdbopt_desktop_integration'});
  $localtlpdb->option ("file_assocs", $vars{'tlpdbopt_file_assocs'});
  $localtlpdb->option ("post_code", $vars{'tlpdbopt_post_code'} ? "1" : "0");
  $localtlpdb->save;
} # do_install_packages

# for later complete removal we want to save some options and values
# into the local tlpdb:
# - should links be set, and if yes, the destination (bin,man,info)
#
sub save_options_into_tlpdb {
  # if we are told to adjust the repository *and* we are *not*
  # installing from the network already, we adjust the repository
  # to the default mirror.ctan.org
  if ($vars{'instopt_adjustrepo'} && ($media ne 'NET')) {
    $localtlpdb->option ("location", $TeXLiveURL); 
  } else {
    my $final_loc = ($media eq 'NET' ? $location : abs_path($location));
    $localtlpdb->option ("location", $final_loc);
  }
  for my $o (keys %TeXLive::TLConfig::TLPDBOptions) {
    next if ($o eq "location"); # done above already
    $localtlpdb->option ($o, $vars{"tlpdbopt_$o"});
  }
  my @archs;
  foreach (keys %vars) {
    if (m/^binary_(.*)$/ ) {
      if ($vars{$_}) { push @archs, $1; }
    }
  }
  if ($opt_custom_bin) {
    push @archs, "custom";
  }
  if (! @archs) {
    tldie("$0: Quitting, no binary platform specified/available.\n"
         ."$0: See https://tug.org/texlive/custom-bin.html for\n"
         ."$0: information on other precompiled binary sets.\n");
  }
  # only if we forced the platform we do save this option into the tlpdb
  if (defined($opt_force_arch)) {
    $localtlpdb->setting ("platform", $::_platform_);
  }
  $localtlpdb->setting("available_architectures", @archs);
  $localtlpdb->save() unless $opt_in_place;
} # save_options_into_tlpdb

sub import_settings_from_old_tlpdb {
  my $dn = shift;
  my $tlpdboldpath =
    "$dn/$TeXLive::TLConfig::InfraLocation/$TeXLive::TLConfig::DatabaseName";
  my $previoustlpdb;
  if (-r $tlpdboldpath) {
    # we found an old installation, so read that one in and save
    # the list installed collections into an array.
    info ("Trying to load old TeX Live Database,\n");
    $previoustlpdb = TeXLive::TLPDB->new(root => $dn);
    if ($previoustlpdb) {
      info ("Importing settings from old installation in $dn\n");
    } else {
      tlwarn ("Cannot load old TLPDB, continuing with normal installation.\n");
      return;
    }
  } else {
    return;
  }
  ############# OLD CODE ###################
  # in former times we sometimes didn't change from scheme-full
  # to scheme-custom when deselecting some collections
  # this is fixed now.
  #
  # # first import the collections
  # # since the scheme is not the final word we select scheme-custom here
  # # and then set the single collections by hand
  # $vars{'selected_scheme'} = "scheme-custom";
  # $vars{'n_collections_selected'} = 0;
  # # remove the selection of all collections
  # foreach my $entry (keys %vars) {
  #   if ($entry=~/^(collection-.*)/) {
  #     $vars{"$1"}=0;
  #   }
  # }
  # for my $c ($previoustlpdb->collections) {
  #   my $tlpobj = $tlpdb->get_package($c);
  #   if ($tlpobj) {
  #     $vars{$c} = 1;
  #     ++$vars{'n_collections_selected'};
  #   }
  # }
  ############ END OF OLD CODE ############

  ############ NEW CODE ###################
  # we simply go through all installed schemes, install
  # all depending collections
  # if we find scheme-full we use this as 'selected_scheme'
  # otherwise we use 'scheme_custom' as we don't know
  # and there is no total order on the schemes.
  #
  # we cannot use select_scheme from tlmgr.pl, as this one clears
  # previous selctions (hmm :-(
  $vars{'selected_scheme'} = "scheme-custom";
  $vars{'n_collections_selected'} = 0;
  # remove the selection of all collections
  foreach my $entry (keys %vars) {
    if ($entry=~/^(collection-.*)/) {
      $vars{"$1"}=0;
    }
  }
  # now go over all the schemes *AND* collections and select them
  foreach my $s ($previoustlpdb->schemes) {
    my $tlpobj = $tlpdb->get_package($s);
    if ($tlpobj) {
      foreach my $e ($tlpobj->depends) {
        if ($e =~ /^(collection-.*)/) {
          # do not add collections multiple times
          if (!$vars{$e}) {
            $vars{$e} = 1;
            ++$vars{'n_collections_selected'};
          }
        }
      }
    }
  }
  # Now do the same for collections:
  for my $c ($previoustlpdb->collections) {
    my $tlpobj = $tlpdb->get_package($c);
    if ($tlpobj) {
      if (!$vars{$c}) {
        $vars{$c} = 1;
        ++$vars{'n_collections_selected'};
      }
    }
  }
  ########### END NEW CODE #############


  # now take over the path
  my $oldroot = $previoustlpdb->root;
  my $newroot = abs_path("$oldroot/..") . "/$texlive_release";
  $vars{'TEXDIR'} = $newroot;
  $vars{'TEXMFSYSVAR'} = "$newroot/texmf-var";
  $vars{'TEXMFSYSCONFIG'} = "$newroot/texmf-config";
  # only TEXMFLOCAL is treated differently, we use what is found by kpsewhich
  # in 2008 and onward this is defined as
  # TEXMFLOCAL = $SELFAUTOPARENT/../texmf-local
  # so kpsewhich -var-value=TEXMFLOCAL returns
  # ..../2008/../texmf-local
  # TODO TODO TODO
  chomp (my $tml = `kpsewhich -var-value=TEXMFLOCAL`);
  $tml = abs_path($tml);
  $vars{'TEXMFLOCAL'} = $tml;
  #
  # now for the settings
  # set the defaults to what is specified in the tlpdb
  $vars{'tlpdbopt_install_docfiles'} =
    $previoustlpdb->option_pkg("00texlive.installation",
                               "install_docfiles");
  $vars{'tlpdbopt_install_srcfiles'} =
    $previoustlpdb->option_pkg("00texlive.installation",
                               "install_srcfiles");
  $vars{'tlpdbopt_create_formats'} =
    $previoustlpdb->option_pkg("00texlive.installation",
                               "create_formats");
  $vars{'tlpdbopt_desktop_integration'} = 1 if win32();
  $vars{'instopt_adjustpath'} =
    $previoustlpdb->option_pkg("00texlive.installation",
                               "path");
  $vars{'instopt_adjustpath'} = 0 if !defined($vars{'instopt_adjustpath'});
  $vars{'instopt_adjustpath'} = 1 if win32();
  $vars{'tlpdbopt_sys_bin'} =
    $previoustlpdb->option_pkg("00texlive.installation",
                               "sys_bin");
  $vars{'tlpdbopt_sys_man'} =
    $previoustlpdb->option_pkg("00texlive.installation",
                               "sys_man");
  $vars{'sys_info'} =
    $previoustlpdb->option_pkg("00texlive.installation",
                               "sys_info");
  #
  # import the set of selected architectures
  my @aar = $previoustlpdb->setting_pkg("00texlive.installation",
                                        "available_architectures");
  if (@aar) {
    for my $b ($tlpdb->available_architectures) {
      $vars{"binary_$b"} = member( $b, @aar );
    }
    $vars{'n_systems_available'} = 0;
    for my $key (keys %vars) {
      ++$vars{'n_systems_available'} if ($key=~/^binary/);
    }
  }
  #
  # try to import paper settings
  my $xdvi_paper;
  if (!win32()) {
    $xdvi_paper = TeXLive::TLPaper::get_paper("xdvi");
  }
  my $pdftex_paper = TeXLive::TLPaper::get_paper("pdftex");
  my $dvips_paper = TeXLive::TLPaper::get_paper("dvips");
  my $dvipdfmx_paper = TeXLive::TLPaper::get_paper("dvipdfmx");
  my $context_paper;
  if (defined($previoustlpdb->get_package("context"))) {
    $context_paper = TeXLive::TLPaper::get_paper("context");
  }
  my $common_paper = "";
  if (defined($xdvi_paper)) {
    $common_paper = $xdvi_paper;
  }
  $common_paper = 
    ($common_paper ne $context_paper ? "no-agree-on-paper" : $common_paper)
      if (defined($context_paper));
  $common_paper = 
    ($common_paper ne $pdftex_paper ? "no-agree-on-paper" : $common_paper)
      if (defined($pdftex_paper));
  $common_paper = 
    ($common_paper ne $dvips_paper ? "no-agree-on-paper" : $common_paper)
      if (defined($dvips_paper));
  $common_paper = 
    ($common_paper ne $dvipdfmx_paper ? "no-agree-on-paper" : $common_paper)
      if (defined($dvipdfmx_paper));
  if ($common_paper eq "no-agree-on-paper") {
    tlwarn("Previous installation uses different paper settings.\n");
    tlwarn("You will need to select your preferred paper sizes manually.\n\n");
  } else {
    if ($common_paper eq "letter") {
      $vars{'instopt_letter'} = 1;
    } elsif ($common_paper eq "a4") {
      # do nothing
    } else {
      tlwarn(
        "Previous installation has common paper setting of: $common_paper\n");
      tlwarn("After installation has finished, you will need\n");
      tlwarn("  to redo this setting by running:\n");
    }
  }
} # import_settings_from_old_tlpdb

# do everything to select a scheme
#
sub select_scheme {
  my $s = shift;
  # set the selected scheme to $s
  $vars{'selected_scheme'} = $s;
  # if we are working on scheme-custom simply return
  return if ($s eq "scheme-custom");
  # remove the selection of all collections
  foreach my $entry (keys %vars) {
    if ($entry=~/^(collection-.*)/) {
      $vars{"$1"}=0;
    }
  }
  # select the collections belonging to the scheme
  my $scheme_tlpobj = $tlpdb->get_package($s);
  if (defined ($scheme_tlpobj)) {
    $vars{'n_collections_selected'}=0;
    foreach my $dependent ($scheme_tlpobj->depends) {
      if ($dependent=~/^(collection-.*)/) {
        $vars{"$1"}=1;
        ++$vars{'n_collections_selected'};
      }
    }
  }
  # we have first set all collection-* keys to zero and than
  # set to 1 only those which are required by the scheme
  # since now scheme asks for collection-wintools we set its vars value
  # to 1 in case we are installing win32 binaries
  if ($vars{"binary_win32"}) {
    $vars{"collection-wintools"} = 1;
    ++$vars{'n_collections_selected'};
  }
  # for good measure, update the deps
  calc_depends();
} # select_scheme

# try to give a decent order of schemes, but be so general that
# if we change names of schemes nothing bad happnes (like forgetting one)
sub schemes_ordered_for_presentation {
  my @scheme_order;
  my %schemes_shown;
  for my $s ($tlpdb->schemes) { $schemes_shown{$s} = 0 ; }
  # first try the size-name-schemes in decreasing order
  for my $sn (qw/full medium small basic minimal/) {
    if (defined($schemes_shown{"scheme-$sn"})) {
      push @scheme_order, "scheme-$sn";
      $schemes_shown{"scheme-$sn"} = 1;
    }
  }
  # now push all the other schemes if they are there and not already shown
  for my $s (sort keys %schemes_shown) {
    push @scheme_order, $s if !$schemes_shown{$s};
  }
  return @scheme_order;
} # schemes_ordered_for_presentation

sub update_numbers {
  $vars{'n_collections_available'}=0;
  $vars{'n_collections_selected'} = 0;
  $vars{'n_systems_available'} = 0;
  $vars{'n_systems_selected'} = 0;
  foreach my $key (keys %vars) {
    if ($key =~ /^binary/) {
      ++$vars{'n_systems_available'};
      ++$vars{'n_systems_selected'} if $vars{$key} == 1;
    }
    if ($key =~ /^collection-/) {
      ++$vars{'n_collections_available'};
      ++$vars{'n_collections_selected'} if $vars{$key} == 1;
    }
  }
} # update_numbers

# to be called at exit when the installation did not complete
sub flushlog {
  if (!defined($::LOGFILENAME)) {
    my $fh;
    my $logfile = "install-tl.log";
    if (open (LOG, ">$logfile")) {
      my $pwd = Cwd::getcwd();
      $logfile = "$pwd/$logfile";
      print "$0: Writing log in current directory: $logfile\n";
      $fh = \*LOG;
    } else {
      $fh = \*STDERR;
      print
        "$0: Could not write to $logfile, so flushing messages to stderr.\n";
    }
    foreach my $l (@::LOGLINES) {
      print $fh $l;
    }
  }
} # flushlog

sub do_cleanup {
  # remove temporary files from TEXDIR/temp
  if (($media eq "local_compressed") or ($media eq "NET")) {
    debug("Remove temporary downloaded containers...\n");
    rmtree("$vars{'TEXDIR'}/temp") if (-d "$vars{'TEXDIR'}/temp");
  }

  # write the profile out
  if ($opt_in_place) {
    create_profile("$vars{'TEXDIR'}/texlive.profile");
    debug("Profile written to $vars{'TEXDIR'}/texlive.profile\n");
  } else {
    create_profile("$vars{'TEXDIR'}/$InfraLocation/texlive.profile");
    debug("Profile written to $vars{'TEXDIR'}/$InfraLocation/texlive.profile\n");
  }

  # now open the log file and write out the log lines if needed.
  # the user could have given the -logfile option in which case all the
  # stuff is already dumped to it and $::LOGFILE defined. So do not
  # redefine it.
  if (!defined($::LOGFILE)) {
    # no -logfile option; nothing written yet
    $::LOGFILENAME = "$vars{'TEXDIR'}/install-tl.log";
    if (open(LOGF,">$::LOGFILENAME")) {
      $::LOGFILE = \*LOGF;
      foreach my $line(@::LOGLINES) {
        print $::LOGFILE "$line";
      }
    } else {
      tlwarn("$0: Cannot create log file $::LOGFILENAME: $!\n"
             . "Not writing out log lines.\n");
    }
  }

  # Close log file if present
  close($::LOGFILE) if (defined($::LOGFILE));
  if (!defined($::LOGFILENAME) and (-e "$vars{'TEXDIR'}/install-tl.log")) {
    $::LOGFILENAME = "$vars{'TEXDIR'}/install-tl.log";
  }
  if (!(defined($::LOGFILENAME)) or !(-e $::LOGFILENAME)) {
    $::LOGFILENAME = "";
  }
} # do_cleanup

sub check_env {
  # check for tex-related envvars.
  $::env_warns = "";
  for my $evar (sort keys %origenv) {
    next if $evar =~ /^(_.*
                        |.*PWD
                        |ARGS
                        |GENDOCS_TEMPLATE_DIR
                        |INSTROOT
                        |PATH
                        |PERL5LIB
                        |SHELLOPTS
                       )$/x; # don't worry about these
    if ("$evar $origenv{$evar}" =~ /tex/i) { # check both key and value
      $::env_warns .= "    $evar=$origenv{$evar}\n";
    }
  }
  if ($::env_warns) {
    $::env_warns = <<"EOF";

 ----------------------------------------------------------------------
 The following environment variables contain the string "tex"
 (case-independent).  If you're doing anything but adding personal
 directories to the system paths, they may well cause trouble somewhere
 while running TeX.  If you encounter problems, try unsetting them.
 Please ignore spurious matches unrelated to TeX.

$::env_warns ----------------------------------------------------------------------
EOF
  }
}


# Create a welcome message.
sub create_welcome {
  @::welcome_arr = ();
  push @::welcome_arr, "\n";
  push @::welcome_arr, __("Welcome to TeX Live!");
  push @::welcome_arr, "\n";
  push @::welcome_arr, __(
    "See %s/index.html for links to documentation.\nThe TeX Live web site (https://tug.org/texlive/) contains any updates and corrections. TeX Live is a joint project of the TeX user groups around the world; please consider supporting it by joining the group best for you. The list of groups is available on the web at https://tug.org/usergroups.html.",
    $::vars{'TEXDIR'});
  if (win32()
      || ($vars{'instopt_adjustpath'}
         && $vars{'tlpdbopt_desktop_integration'} != 2)) {
     ; # don't tell them to make path adjustments on Windows,
       # or if they chose to "create symlinks".
   } else {
    push @::welcome_arr, "\n";
    push @::welcome_arr, __(
      "Add %s/texmf-dist/doc/man to MANPATH.\nAdd %s/texmf-dist/doc/info to INFOPATH.\nMost importantly, add %s/bin/%s\nto your PATH for current and future sessions.",
      $::vars{'TEXDIR'}, $::vars{'TEXDIR'}, $::vars{'TEXDIR'},
      $::vars{'this_platform'});
  }
}


# remember the warnings issued
sub install_warnlines_hook {
  push @::warn_hook, sub { push @::WARNLINES, @_; };
}

## a summary of warnings if there were any
#sub warnings_summary {
#  return '' unless @::WARNLINES;
#  my $summary = <<EOF;
#
#Summary of warning messages during installation:
#EOF
#  $summary .= join ("", map { "  $_" } @::WARNLINES); # indent each warning
#  $summary .= "\n";  # extra blank line
#  return $summary;
#}



# some helper functions
# 
sub select_collections {
  my $varref = shift;
  foreach (@_) {
    $varref->{$_} = 1;
  }
}

sub deselect_collections {
  my $varref = shift;
  foreach (@_) {
    $varref->{$_} = 0;
  }
}

# assign \&___ to *__ if __ is not otherwise defined
sub ___ {
  my $s = shift;
  return wrapped (sprintf($s, @_));
}

sub wrapped {
  my $t = shift;
  my $toolong = '.{79}';
  if ($t !~ $toolong) {
    return $t;
  } else {
    my @lines = split /\n/, $t;
    foreach my $l (@lines) {
      if ($l !~ $toolong) {
        next; # leave $l alone
      }
      my @words = split /\s+/, $l;
      if (! @words) {
        $l = "";
        next;
      } else {
        my $indent = $l;
        $indent =~ s/^(\s*).*$/$1/; # extract leading spaces
        my @broken = ();
        my $inx = 0;
        while (@words) {
          if (not ((defined $broken[$inx]) && ($broken[$inx] =~ /\S/))) {
            $broken[$inx] = $indent . (shift @words);
          } elsif (($broken[$inx] . " " . $words[0]) =~ $toolong) {
            $inx++; # NO word consumed, still words remaining
          } else {
            $broken[$inx] = $broken[$inx] . " " . (shift @words);
          } # $l =~ $toolong
        } # while @words
        $l = join "\n", @broken;
      } # @words
    } # foreach my $l
    return join "\n", @lines;
  } # $t =~ $toolong
} # wrapped


  __END__

=head1 NAME

install-tl - TeX Live cross-platform installer

=head1 SYNOPSIS

install-tl [I<option>]...

install-tl-windows.bat [I<option>]...

install-tl-advanced.bat [I<option>]...

=head1 DESCRIPTION

This installer creates a runnable TeX Live installation from various
media, including over the network, from local hard disk, a DVD, etc. The
installer works on all platforms supported by TeX Live. For information
on initially downloading TeX Live, see
L<https://tug.org/texlive/acquire.html>.

The basic idea of TeX Live installation is for you to choose one of the
top-level I<schemes>, each of which is defined as a different set of
I<collections> and I<packages>, where a collection is a set of packages,
and a package is what contains actual files.

Within the installer, you can choose a scheme, and further customize the
set of collections to install, but not the set of the packages.  To work
at the package level, use C<tlmgr> (reference just below) after the
initial installation is complete.

The default is C<scheme-full>, which installs everything, and this is
highly recommended.


=head1 REFERENCES

Post-installation configuration, package updates, and more, are
handled through B<tlmgr>(1), the TeX Live Manager
(L<https://tug.org/texlive/tlmgr.html>).

The most up-to-date version of this installer documentation is on the
Internet at L<https://tug.org/texlive/doc/install-tl.html>.

For the full documentation of TeX Live, see
L<https://tug.org/texlive/doc>.


=head1 OPTIONS

As usual, all options can be specified in any order, and with either a
leading C<-> or C<-->.  An argument value can be separated from its
option by either a space or C<=>.

=over 4

=item B<-gui> [[=]I<module>]

If no I<module> is given, starts the Tcl/Tk (see below) GUI installer.

If I<module> is given loads the given installer module. Currently the
following modules are supported:

=over 4

=item C<text>

The text mode user interface (default on Unix systems).  Same as the
C<-no-gui> option.

=item C<tcl>

The Tcl/Tk user interface (default on Macs and Windows).  It starts
with a small number of configuration options, roughly equivalent
to what the wizard option below offers, but a button C<Advanced>
takes you to a screen with roughly the same options as the C<perltk>
interface.

=item C<wizard>

The wizard mode user interface, asking only minimal questions before
installing all of TeX Live.

=item C<expert>

A generic name for, currently, C<perltk>; it may select a different GUI
in the future.

=item C<perltk>

The expert GUI installer, providing access to more options.

=back

The C<perltk> and C<wizard> modules require the Perl/Tk module
(L<https://tug.org/texlive/distro.html#perltk>). if Perl/Tk is not
available, installation continues in text mode, except on Windows,
where all gui options except C<text> are diverted to the default
C<tcl> GUI.

The C<tcl> GUI requires Tcl/Tk. This is standard on Macs and is often
already installed on GNU/Linux. For Windows, TeX Live provides a Tcl/Tk
runtime.

=item B<-no-gui>

Use the text mode installer (default except on Windows and Macs).

=for comment Keep language list in sync with tlmgr.

=item B<-lang> I<llcode>

By default, the GUI tries to deduce your language from the
environment. The Tcl GUI uses the language detection built into
Tcl/Tk; the Perl/Tk GUIs use the C<LC_MESSAGES> environment
variable. If that fails you can select a different language by
giving this option with a language code (based on ISO 639-1).
Currently supported (but not necessarily completely translated) are:
English (en, default), Czech (cs), German (de), French (fr), Italian
(it), Japanese (ja), Dutch (nl), Polish (pl), Brazilian Portuguese
(pt_BR), Russian (ru), Slovak (sk), Slovenian (sl), Serbian (sr),
Ukrainian (uk), Vietnamese (vi), simplified Chinese (zh_CN), and
traditional Chinese (zh_TW).

=item B<-repository> I<url|path>

Specify the package repository to be used as the source of the
installation. In short, this can be a directory name or a url using
http(s), ftp, or scp. The documentation for C<tlmgr> has the details
(L<https://tug.org/texlive/doc/tlmgr.html#OPTIONS>).

For installation, the default is to pick a mirror automatically, using
L<http://mirror.ctan.org/systems/texlive/tlnet>; the chosen mirror is
used for the entire download. You can use the special argument C<ctan>
as an abbreviation for this. (See L<https://ctan.org> for more about CTAN
and its mirrors.)

After installation is complete, you can use that installation as the
repository for another installation.  If you chose to install less than
the full scheme containing all packages, the list of available schemes
will be adjusted accordingly.

=item B<-select-repository>

This option allows you to choose a particular mirror from the current
list of active CTAN mirrors. This option is supported in the C<text>,
C<wizard> and C<perltk> installer modes, and will also offer to install
from local media if available, or from a repository specified on the
command line. It's useful when the (default) automatic redirection does
not choose a good host for you.

=item B<-all-options>

Normally options not relevant to the current platform are not shown
(e.g., when running on Unix, Windows-specific options are omitted).
Giving this command line option allows configuring such "foreign"
settings.

=item B<-custom-bin> I<path>

If you have built your own set of TeX Live binaries (perhaps because
your platform was not supported by TeX Live out of the box), this option
allows you to specify the I<path> to a directory where the binaries for
the current system are present.  The installation will continue as
usual, but at the end all files from I<path> are copied over to
C<bin/custom/> under your installation directory and this C<bin/custom/>
directory is what will be added to the path for the post-install
actions.  To install multiple custom binary sets, manually rename
C<custom> before doing each.

For more information on custom binaries, see
L<https://tug.org/texlive/custom-bin.html>.  For general information on
building TeX Live, see L<https://tug.org/texlive/build.html>.

=item B<-debug-translation>

In the Perl/Tk GUI modes, this option reports any missing, or more
likely untranslated, messages to standard error. Helpful for
translators to see what remains to be done.

=item B<-force-platform> I<platform>

Instead of auto-detecting the current platform, use I<platform>.
Binaries for this platform must be present and they must actually be
runnable, or installation will fail.  C<-force-arch> is a synonym.

=item B<-help>, B<--help>, B<-?>

Display this help and exit. (This help is also on the web at
L<https://tug.org/texlive/doc/install-tl.html>). Sometimes the C<perldoc>
and/or C<PAGER> programs on the system have problems, possibly resulting
in control characters being literally output. This can't always be
detected, but you can set the C<NOPERLDOC> environment variable and
C<perldoc> will not be used.

=item B<-in-place>

This is a quick-and-dirty installation option in case you already have
an rsync or svn checkout of TeX Live.  It will use the checkout as-is
and will just do the necessary post-install.  Be warned that the file
C<tlpkg/texlive.tlpdb> may be rewritten, that removal has to be done
manually, and that the only realistic way to maintain this installation
is to redo it from time to time.  This option is not available via the
installer interfaces.  USE AT YOUR OWN RISK.

=item B<-init-from-profile> I<profile_file>

Similar to B<-profile> (see L</PROFILES> below), but only initializes
the installation configuration from I<profile_file> and then starts a
normal interactive session. Environment variables are not ignored.

=item B<-logfile> I<file>

Write both all messages (informational, debugging, warnings) to I<file>,
in addition to standard output or standard error.

If this option is not given, the installer will create a log file
in the root of the writable installation tree,
for example, C</usr/local/texlive/YYYY/install-tl.log> for the I<YYYY>
release.

=item B<-no-cls>

For the text mode installer only: do not clear the screen when entering
a new menu (for debugging purposes).

=item B<-no-persistent-downloads>

=item B<-persistent-downloads>

For network installs, activating this option makes the installer try to
set up a persistent connection using the C<Net::LWP> Perl module.  This
opens only one connection between your computer and the server per
session and reuses it, instead of initiating a new download for each
package, which typically yields a significant speed-up.

This option is turned on by default, and the installation program will
fall back to using C<wget> if this is not possible.  To disable usage of
LWP and persistent connections, use C<-no-persistent-downloads>.

=item B<-no-verify-downloads>

By default, if a GnuPG C<gpg> binary is found in PATH, downloads are
verified against a cryptographic signature. This option disables such
verification.  The full description is in the Crytographic Verification
section of the C<tlmgr> documentation, e.g.,
L<https://tug.org/texlive/doc/tlmgr.html#CRYPTOGRAPHIC-VERIFICATION>

=item B<-non-admin>

For Windows only: configure for the current user, not for all users.

=item B<-portable>

Install for portable use, e.g., on a USB stick.  Also selectable from
within the perltk and text installers.

=item B<-print-platform>

Print the TeX Live identifier for the detected platform
(hardware/operating system) combination to standard output, and exit.
C<-print-arch> is a synonym.

=item B<-profile> I<profile_file>

Load I<profile_file> and do the installation with no user interaction,
that is, a batch (unattended) install.  Environment variables are
ignored. See L</PROFILES> below.

=item B<-q>

Omit normal informational messages.

=item B<-scheme> I<scheme>

Schemes are the highest level of package grouping in TeX Live; the
default is to use the C<full> scheme, which includes everything.  This
option overrides that default.  You can change the scheme again before
the actual installation with the usual menu.  The I<scheme> argument may
optionally have a prefix C<scheme->.  The list of supported scheme names
depends on what your package repository provides; see the interactive
menu list.

=item B<-v>

Include verbose debugging messages; repeat for maximum debugging: C<-v
-v>.  (Further repeats are accepted but ignored.)

=item B<-version>, B<--version>

Output version information and exit.  If C<-v> is also given, the
versions of the TeX Live modules used are also reported.

=back


=head1 PROFILES

A I<profile> file contains all the values needed to perform an
installation.  After a normal installation has finished, a profile for
that exact installation is written to the file C<tlpkg/texlive.profile>.
In addition, from the text menu one can select C<P> to save the current
setup as a profile at any time.

Such a profile file can be given as the argument to C<-profile>, for
example to redo the exact same installation on a different system.
Alternatively, you can use a custom profile, most easily created by
starting from a generated one and changing values, or an empty file,
which will take all the defaults.

As mentioned above, the installer only supports selection by scheme and
collections, not individual packages, so packages cannot be specified in
profile files either. Use C<tlmgr> to work at the package level.

Within a profile file, each line consists of

I<variable> [I<value>]

except for comment lines starting with C<#>.  The possible variable
names are listed below.  Values, when present, are either C<0> or C<1>
for booleans, or strings (which must be specified without any quote
characters).  Leading whitespace is ignored.

If the variable C<selected_scheme> is defined and I<no> collection
variables at all are defined, then the collections required by the
specified scheme (which might change over time) are installed, without
explicitly listing them.  This eases maintenance of profile files.  If
any collections are specified in a profile, though, then all desired
collections must be given explicitly.

For example, a line 

  selected_scheme scheme-small

along with definitions for the installation directories (given below
under "path options") suffices to install the "small" scheme with all
default options.  The schemes are described in the C<S> menu in the
text installer, or equivalent.

Besides C<selected_scheme>, here is the list of variable names supported
in a profile:

B<collection options> (prefix C<collection->)

Collections are specified with a variable name with the prefix
C<collection-> followed by a collection name; there is no value.  For
instance, C<collection-basic>.  The collections are described in the
C<C> menu.

Schemes and collections (and packages) are ultimately defined by the
files in the C<tlpkg/tlpsrc/> source directory.

B<path options>

It is best to define all of these, even though they may not be used in
the installation, so as to avoid unintentionally getting a default value
that could cause problems later.

  TEXDIR
  TEXMFCONFIG
  TEXMFVAR
  TEXMFHOME
  TEXMFLOCAL
  TEXMFSYSCONFIG
  TEXMFSYSVAR

B<installer options> (prefix C<instopt_>)

=over 4

=item C<instopt_adjustpath> (default 0 on Unix, 1 on Windows)

Adjust C<PATH> environment variable.

=item C<instopt_adjustrepo> (default 1)

Set remote repository to a multiplexed CTAN mirror after installation;
see C<-repository> above.

=item C<instopt_letter> (default 0)

Set letter size paper as the default, instead of a4.

=item C<instopt_portable> (default 0)

Install for portable use, e.g., on a USB stick.

=item C<instopt_write18_restricted> (default 1)

Enable C<\write18> for a restricted set of programs.

=back

B<tlpdb options> (prefix C<tlpdbopt_>)

The definitive list is given in C<tlpkg/TeXLive/TLConfig.pm>, in the hash
C<%TeXLive::TLConfig::TLPDBOptions>, together with explanations.  All
items given there I<except> for C<tlpdbopt_location> can be specified.
Here is the current list:

  tlpdbopt_autobackup
  tlpdbopt_backupdir
  tlpdbopt_create_formats
  tlpdbopt_desktop_integration
  tlpdbopt_file_assocs
  tlpdbopt_generate_updmap
  tlpdbopt_install_docfiles
  tlpdbopt_install_srcfiles
  tlpdbopt_post_code
  tlpdbopt_sys_bin
  tlpdbopt_sys_info
  tlpdbopt_sys_man
  tlpdbopt_w32_multi_user

B<platform options> (prefix C<binary_>)

For each supported platform in TeX Live (directories under C<bin/>), the
variable C<binary_>I<PLATFORM> can be set with value 1.  For example:

  binary_x86_64-linux 1

If no C<binary_> settings are made, the default is whatever the
current machine is running.

In releases before 2017, many profile variables had different
names (not documented here; see the C<install-tl> source).  They are
accepted and transformed to the names given above.  When a profile is
written, the names above are always used.

For more details on all of the above options, consult the TeX Live
installation manual, linked from L<https://tug.org/texlive/doc>.


=head1 ENVIRONMENT VARIABLES

For ease in scripting and debugging, C<install-tl> looks for the
following environment variables. They are not of interest for normal
user installations.

=over 4

=item C<TEXLIVE_DOWNLOADER>

=item C<TL_DOWNLOAD_PROGRAM>

=item C<TL_DOWNLOAD_ARGS>

These override the normal choice of a download program; see the C<tlmgr>
documentation, e.g.,
L<https://tug.org/texlive/doc/tlmgr.html#ENVIRONMENT-VARIABLES>.

=item C<TEXLIVE_INSTALL_ENV_NOCHECK>

Omit the check for environment variables containing the string C<tex>.
People developing TeX-related software are likely to have many such
variables.

=item C<TEXLIVE_INSTALL_NO_CONTEXT_CACHE>

Omit creating the ConTeXt cache.  This is useful for redistributors.

=item C<TEXLIVE_INSTALL_NO_IMPORT>

Omit check for installing on top of a previous installation and then
asking about importing previous settings.

=item C<TEXLIVE_INSTALL_NO_WELCOME>

Omit printing the welcome message after successful installation, e.g.,
when testing.

=item C<TEXLIVE_INSTALL_PAPER>

Set the default paper size for all relevant programs; must be either
C<letter> or C<a4>. The default is C<a4>.

=item C<TEXLIVE_INSTALL_PREFIX>

=item C<TEXLIVE_INSTALL_TEXDIR>

=item C<TEXLIVE_INSTALL_TEXMFCONFIG>

=item C<TEXLIVE_INSTALL_TEXMFVAR>

=item C<TEXLIVE_INSTALL_TEXMFHOME>

=item C<TEXLIVE_INSTALL_TEXMFLOCAL>

=item C<TEXLIVE_INSTALL_TEXMFSYSCONFIG>

=item C<TEXLIVE_INSTALL_TEXMFSYSVAR>

Specify the respective directories.  C<TEXLIVE_INSTALL_PREFIX> defaults
to C</usr/local/texlive>, while C<TEXLIVE_INSTALL_TEXDIR> defaults to
the release directory within that prefix, e.g.,
C</usr/local/texlive/2016>.  All the defaults can be seen by running the
installer interactively and then typing C<D> for the directory menu.

=item C<NOPERLDOC>

Don't try to run the C<--help> message through C<perldoc>.

=back


=head1 AUTHORS AND COPYRIGHT

This script and its documentation were written for the TeX Live
distribution (L<https://tug.org/texlive>) and both are licensed under the
GNU General Public License Version 2 or later.

$Id: install-tl 54993 2020-05-03 21:57:54Z karl $
=cut

# to remake HTML version: pod2html --cachedir=/tmp install-tl >/tmp/itl.html

### Local Variables:
### perl-indent-level: 2
### tab-width: 2
### indent-tabs-mode: nil
### End:
# vim:set tabstop=2 expandtab: #
