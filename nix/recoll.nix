# Spotlight's indexer (README "Spotlight"): recoll without its Qt GUI, with
# the Python module hearth-search queries through. nixpkgs' recoll points two
# rarely used filters at LyX (a Qt 5 app) and catdvi (TeX Live) and wraps its
# command-line tools with Qt 5's hook, which pulls Qt 5 and GTK 3 into the
# closure. Here those filters get stubs (.lyx and .dvi files are still found
# by name, just not by their text) and the tools are left unwrapped: every
# filter already calls its converter (pdftotext, antiword...) by full path.
{ lib, recoll-nox, writeShellScriptBin, libxml2, libxslt }:
let
  stub = name: writeShellScriptBin name "exit 1";
in
(recoll-nox.override {
  lyx = stub "lyx";
  catdvi = stub "catdvi";
}).overrideAttrs (old: {
  nativeBuildInputs = lib.filter (p: !(lib.hasInfix "wrap-qt" (p.name or ""))) old.nativeBuildInputs;
  # The Qt hook used to bring these in.
  buildInputs = old.buildInputs ++ [ libxml2 libxslt ];
  dontWrapQtApps = true;
})
