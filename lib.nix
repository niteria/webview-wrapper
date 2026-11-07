{ pkgs }:
let
  inherit (pkgs) lib;
  android = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "36" ];
    buildToolsVersions = [ "36.0.0" ];
    includeEmulator = false;
  };
  sdk = "${android.androidsdk}/libexec/android-sdk";
  tools = "${sdk}/build-tools/36.0.0";
  platform = "${sdk}/platforms/android-36/android.jar";
  java = builtins.toJSON;

  # An unsigned, aligned APK wrapping one website.
  mkApk =
    {
      name,
      title,
      url,
      appId ? "io.github.niteria.${name}",
      versionCode ? 1,
      # Launcher icon: an SVG path in a 108x108 viewport, drawn in color.
      icon ? "M24,24h60v60h-60z",
      color ? "#5AA9E6",
      background ? "#17232E",
      # What the address points at, for menus and messages.
      noun ? "website",
      unreachableMessage ? "Cannot reach ${title}\n\nCheck your network connection and that ${url} is reachable.",
      allowCleartext ? true,
      # An extra CA trusted only for these domains, e.g. a local HTTPS CA.
      trustedCertificate ? null,
      trustedDomains ? [ ],
    }:
    let
      networkSecurity = lib.optionalString (
        trustedCertificate != null
      ) " android:networkSecurityConfig=\"@xml/network_security_config\"";
      Noun = lib.toUpper (lib.substring 0 1 noun) + lib.substring 1 (-1) noun;
      securityConfig = pkgs.writeText "${name}-network-security.xml" ''
        <?xml version="1.0" encoding="utf-8"?>
        <network-security-config>
            <base-config cleartextTrafficPermitted="${lib.boolToString allowCleartext}">
                <trust-anchors><certificates src="system" /></trust-anchors>
            </base-config>
            <domain-config cleartextTrafficPermitted="${lib.boolToString allowCleartext}">
                ${lib.concatMapStrings (
                  d: ''<domain includeSubdomains="false">${d}</domain>''
                ) trustedDomains}
                <trust-anchors>
                    <certificates src="system" />
                    <certificates src="@raw/trusted_ca" />
                </trust-anchors>
            </domain-config>
        </network-security-config>
      '';
      iconXml = pkgs.writeText "${name}-icon.xml" ''
        <vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
          <path android:fillColor="${background}" android:pathData="M0,0h108v108h-108z" />
          <path android:fillColor="${color}" android:fillType="evenOdd" android:pathData="${icon}" />
        </vector>
      '';
    in
    assert lib.assertMsg (
      trustedCertificate == null || trustedDomains != [ ]
    ) "${name}: trustedCertificate needs trustedDomains";
    pkgs.stdenvNoCC.mkDerivation {
      pname = "${name}-webview";
      version = toString versionCode;
      dontUnpack = true;
      nativeBuildInputs = [
        pkgs.jdk17
        pkgs.zip
      ];
      buildPhase = ''
        export HOME="$TMPDIR"
        mkdir -p res/drawable compiled classes dex src
        cp ${iconXml} res/drawable/icon.xml
        substitute ${./AndroidManifest.xml} AndroidManifest.xml \
          --subst-var-by package ${appId} \
          --subst-var-by label ${lib.escapeShellArg (lib.escapeXML title)} \
          --subst-var-by cleartext ${lib.boolToString allowCleartext} \
          --subst-var-by networkSecurity ${lib.escapeShellArg networkSecurity}
        sed -i 's/android:versionCode="1"/android:versionCode="${toString versionCode}"/' AndroidManifest.xml
        ${lib.optionalString (trustedCertificate != null) ''
          mkdir -p res/raw res/xml
          cp ${trustedCertificate} res/raw/trusted_ca.pem
          cp ${securityConfig} res/xml/network_security_config.xml
        ''}
        substitute ${./MainActivity.java} src/MainActivity.java \
          --subst-var-by package ${appId} \
          --subst-var-by url ${lib.escapeShellArg (java url)} \
          --subst-var-by title ${lib.escapeShellArg (java title)} \
          --subst-var-by menuDescription ${lib.escapeShellArg (java "${title} menu")} \
          --subst-var-by addressLabel ${lib.escapeShellArg (java "${Noun} address")} \
          --subst-var-by addressError ${lib.escapeShellArg (java "Enter an HTTP or HTTPS ${noun} address")} \
          --subst-var-by unreachableMessage ${lib.escapeShellArg (java unreachableMessage)}
        "${tools}/aapt2" compile --dir res -o compiled/
        "${tools}/aapt2" link -o unsigned.apk -I "${platform}" --manifest AndroidManifest.xml compiled/*.flat
        javac -encoding UTF-8 --release 8 -classpath "${platform}" -d classes src/MainActivity.java
        jar cf classes.jar -C classes .
        "${tools}/d8" --lib "${platform}" --min-api 26 --output dex classes.jar
        (cd dex; zip -X ../unsigned.apk classes.dex)
        "${tools}/zipalign" -p -f 4 unsigned.apk ${name}-unsigned.apk
        "${tools}/aapt2" dump badging ${name}-unsigned.apk | grep -F "package: name='${appId}'"
      '';
      installPhase = ''
        mkdir -p "$out"
        cp ${name}-unsigned.apk "$out/"
      '';
    };

  # `webview-apk NAME [OUTPUT]` signs NAME's APK. keyCommand runs with the app
  # name as $1 and prints its PKCS#12 keystore; the key only exists in a
  # private temporary directory.
  mkSigner =
    {
      apks,
      keyCommand,
      keyPassword ? "android",
      name ? "webview-apk",
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jdk17
      ];
      text = ''
        usage() { echo "usage: ${name} {${lib.concatStringsSep "|" (lib.attrNames apks)}} [OUTPUT]" >&2; exit 2; }
        [ $# -ge 1 ] || usage
        app=$1 out=''${2:-$1.apk}
        case $app in
          ${lib.concatStrings (
            lib.mapAttrsToList (n: apk: "${n}) unsigned=${apk}/${n}-unsigned.apk ;;\n") apks
          )}
          *) usage ;;
        esac
        umask 077
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        key() { ${keyCommand}
        }
        key "$app" > "$tmp/release.p12"
        "${tools}/apksigner" sign --ks "$tmp/release.p12" --ks-pass pass:${keyPassword} \
          --out "$out" "$unsigned"
        rm -f "$out.idsig"
        "${tools}/apksigner" verify --print-certs "$out" | grep -E 'Signer #1 certificate (DN|SHA-256)' >&2
        echo "$out"
      '';
    };

  # `webview-keygen NAME TITLE` prints a new PKCS#12 signing key.
  keygen = pkgs.writeShellApplication {
    name = "webview-keygen";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jdk17
    ];
    text = ''
      [ $# -eq 2 ] || { echo "usage: webview-keygen NAME TITLE > release.p12" >&2; exit 2; }
      umask 077
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      keytool -genkeypair -keystore "$tmp/release.p12" -storetype PKCS12 \
        -storepass android -keypass android -alias "$1" -keyalg RSA -keysize 3072 \
        -validity 10000 -dname "CN=$2 Personal App" >&2
      cat "$tmp/release.p12"
    '';
  };
in
{
  inherit mkApk mkSigner keygen;
}
