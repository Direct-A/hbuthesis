# package requirement
XETEX_PKGS="fontname fontspec l3packages xetex";
CTEX_PKGS="cjk ctex environ ms trimspaces ulem xecjk zhnumber";
HYPERREF_PKGS="bitset letltxmacro pdfescape pdflscape";
NOMENCL_PKGS="nomencl koma-script xkeyval";

BIN_PKGS="latexmk l3build";
REQUIRED_PKGS="$XETEX_PKGS $CTEX_PKGS amsmath amsfonts";
FONT_PKGS="fandol";
EXTRA_PKGS="$HYPERREF_PKGS $NOMENCL_PKGS siunitx zhlineskip";
DOC_PKGS="booktabs listings xcolor";

tlmgr install $BIN_PKGS $REQUIRED_PKGS $FONT_PKGS $EXTRA_PKGS $DOC_PKGS;
