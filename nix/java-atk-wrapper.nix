# Java ATK Wrapper (GNOME): the accessibility bridge for Java Swing/AWT apps.
# Loaded into every Java program by JAVA_TOOL_OPTIONS (arbor/config.kdl),
# it gives Swing windows an AT-SPI tree, which hearth's global menu reads
# (README "Global menu": JDownloader, Ghidra, DBeaver's dialogs...). No app
# is changed. Not in nixpkgs.
#
# Changes for loading from JAVA_TOOL_OPTIONS into any JVM:
# - The JNI library is loaded by its store path (System.load), not by
#   name from java.library.path, which an app may set itself; xprop and
#   dbus-send (its "is accessibility on?" checks) by store path too.
# - Its start-up catches every Throwable, not just Exceptions: a native
#   library that can't load (UnsatisfiedLinkError) must leave the app
#   without accessibility, not end it (Java ends a Swing app whose
#   assistive technology fails to initialize).
# - Compiled for Java 8 (--release 8): apps that bundle an old JRE would
#   otherwise fail to load the class, and Java ends a Swing app whose
#   assistive technology can't be loaded. The Java 9 AccessibilityProvider
#   class is left out (non-modular jar); newer JDKs load the class by name.
# Installed as lib/java-atk-wrapper/java-atk-wrapper.jar and
# lib/java-atk-wrapper/libatk-wrapper.so (lib is linked into
# /run/current-system/sw, where config.kdl points).
{ lib, stdenv, fetchurl, pkg-config, jdk, glib, atk, at-spi2-atk, at-spi2-core, dbus, xprop, libX11 }:

stdenv.mkDerivation rec {
  pname = "java-atk-wrapper";
  version = "0.44.0";
  src = fetchurl {
    url = "https://download.gnome.org/sources/java-atk-wrapper/${lib.versions.majorMinor version}/java-atk-wrapper-${version}.tar.gz";
    sha256 = "93d304831660972d5f5b8081c361be80283defe248924ef6c90db90e972ebb44";
  };

  nativeBuildInputs = [ pkg-config jdk ];
  buildInputs = [ glib atk at-spi2-atk at-spi2-core dbus libX11 ];

  postPatch = ''
    substituteInPlace wrapper/org/GNOME/Accessibility/AtkWrapper.java.in \
      --replace-fail 'System.loadLibrary("atk-wrapper");' \
                     "System.load(\"$out/lib/java-atk-wrapper/libatk-wrapper.so\");" \
      --replace-fail '"dbus-send --session' '"${dbus}/bin/dbus-send --session'
    # The first catch is the static start-up block's (see above).
    sed -i '0,/catch (Exception e)/s//catch (Throwable e)/' wrapper/org/GNOME/Accessibility/AtkWrapper.java.in
    grep -q 'catch (Throwable e)' wrapper/org/GNOME/Accessibility/AtkWrapper.java.in
  '';

  configureFlags = [
    "--with-jardir=${placeholder "out"}/lib/java-atk-wrapper"
    "--with-propertiesdir=${placeholder "out"}/share/java-atk-wrapper"
    "--libdir=${placeholder "out"}/lib/java-atk-wrapper"
  ];
  JAVACFLAGS = "--release 8 -nowarn";
  XPROP = "${xprop}/bin/xprop";
  JAVA_HOME = jdk.home;

  postInstall = ''
    rm -f $out/lib/java-atk-wrapper/*.la
    test -f $out/lib/java-atk-wrapper/java-atk-wrapper.jar
    test -f $out/lib/java-atk-wrapper/libatk-wrapper.so
  '';

  meta = {
    description = "ATK bridge for Java Swing/AWT (AT-SPI accessibility for Java apps)";
    homepage = "https://gitlab.gnome.org/GNOME/java-atk-wrapper";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.linux;
  };
}
