# marten-mpl

Modified copies of `plume_core` and `omnisette` from [Impactor](https://github.com/claration/Impactor) at commit 6a322e2, as used by the installer in Marten. Both are under the Mozilla Public License 2.0 (`LICENSE` in each folder).

Changed files:

- `plume_core/src/auth/account/login.rs`: follows the password protocol the server asks for (`s2k_fo`); as Impactor 2.7.2, an `hsc` 409 asks for the two-factor code, with the trusted phone numbers fetched for it
- `plume_core/src/auth/account/mod.rs`, `token.rs`, `two_factor_auth.rs`, `plume_core/src/lib.rs`: the User-Agent Impactor 2.7.2 sends (`akd/1.0 CFNetwork/978.0.7 Darwin/18.7.0`, and `Xcode` for two-factor; from 2026-10-13 to 2026-11-03 these sent AltSign's AuthKit identity instead), and an answer that is not 2xx is an error with its status (`GeneralHttpError`), as in Impactor 2.7.2
- `omnisette/src/lib.rs`: the default anisette server is `https://mac-ani.jkcoxson.com`, as in Impactor 2.7.2, and can be set with `MARTEN_ANISETTE_URL`; its HTTP clients check certificates, against the platform's roots and Apple's (`verified_client`), and provisioning addresses must be https on apple.com (`is_apple_address`)
- `omnisette/src/remote_anisette_v3.rs`: as Impactor 2.7.2, the URL bag lookup goes with a fixed Mac client info, provisioning with the server's own
- `omnisette/src/remote_anisette_v3.rs`, `omnisette/src/adi_proxy.rs`: certificates checked instead of accepted whatever they are, provisioning addresses checked, and the anisette state file written readable by its owner only
- `omnisette/src/apple_root.der`: Apple's root certificate, the same file as `plume_core/src/apple_root.der`
- `plume_core/src/utils/certificate.rs`: the signing key written readable by its owner only, in a folder only its owner can open
- `Cargo.toml` in both: workspace fields written out so each builds on its own

## ASSRenderer

`ASSRenderer/` is the package that builds the ASS and SSA subtitle library in Marten's Mac, Apple TV, iPhone and iPad apps: libass
0.17.5 with FreeType, HarfBuzz, FriBidi (LGPL-2.1 or later) and libunibreak, all unmodified, from mpvkit's libass-build 0.17.5,
linked with one Swift file of Marten's into one dynamic library, `ASSRenderer`. It is here so that anyone can build that library
again, with a changed FriBidi or any other part, and put it in place of the one in the app. The package's own files are under the
MIT License (`ASSRenderer/LICENSE`); each library keeps its own licence.

Build it with `swift build -c release` in `ASSRenderer/` (Xcode 26 or newer).
