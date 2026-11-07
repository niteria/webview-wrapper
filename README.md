# webview-wrapper

Small native Android apps that each wrap one website in the system WebView,
built from Nix with the Android SDK (`javac`, `aapt2`, `d8`; no Gradle).
Android 8 or newer, targeting Android 16 (API 36), all ABIs.

The flake exposes builders; the list of sites and the signing keys live in the
consumer.

```nix
inputs.webview-wrapper.url = "github:niteria/webview-wrapper";

let w = inputs.webview-wrapper.lib.x86_64-linux; in
rec {
  apks.gym = w.mkApk {
    name = "gym";                  # package io.github.niteria.gym
    title = "Gym";
    url = "http://gym.test/";
    icon = "M20,40h10v28h-10z";   # SVG path in a 108x108 viewport
    color = "#FF9944";
  };
  signer = w.mkSigner {
    inherit apks;
    # Runs with the app name as $1 and prints its PKCS#12 keystore.
    keyCommand = ''age -d -i ~/.ssh/id_ed25519 "keys/$1.p12.age"'';
  };
}
```

`webview-apk gym [OUTPUT]` (the signer) writes and verifies a v2/v3-signed APK;
the keystore exists only in a private temporary directory. `nix run
.#keygen -- NAME TITLE > release.p12` creates a new RSA-3072 key (store and key
password `android`; protect the file itself). Keep every key: updates install
only when signed with the same key.

## mkApk options

| Option | Default | |
|---|---|---|
| `name`, `title`, `url` | required | App name, launcher label, start page |
| `appId` | `io.github.niteria.<name>` | Package ID |
| `versionCode` | 1 | Raise it to make Android treat a build as newer |
| `icon`, `color`, `background` | square, blue, dark | Launcher icon |
| `noun` | `website` | Used in "Website address" and its error text |
| `unreachableMessage` | generic | Shown when the start page fails to load |
| `allowCleartext` | true | Permit HTTP |
| `trustedCertificate`, `trustedDomains` | none | An extra CA (e.g. a local HTTPS CA) trusted only for these hosts; HTTPS validation stays on |

## App behaviour

- Toolbar with the title and a menu: reload, home, change address (stored per
  app), open in browser.
- Back navigates web history, then exits.
- Links to the same host stay in the app; other HTTP(S) links open in the
  browser. No JavaScript bridge is exposed.
- File uploads through the system document picker, accepting any type.
- Loading progress, a reconnect screen for main-page failures, persistent
  cookies and storage, system bar and keyboard insets.

`nix flake check` builds two sample apps, one with a scoped CA.
