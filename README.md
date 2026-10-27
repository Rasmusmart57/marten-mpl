# marten-mpl

Modified copies of `plume_core` and `omnisette` from [Impactor](https://github.com/claration/Impactor) at commit 6a322e2, as used by the installer in Marten. Both are under the Mozilla Public License 2.0 (`LICENSE` in each folder).

Changed files:

- `plume_core/src/auth/account/login.rs`: follows the password protocol the server asks for (`s2k_fo`), sends a current client identity
- `plume_core/src/auth/account/mod.rs`, `token.rs`, `two_factor_auth.rs`: the same client identity
- `omnisette/src/lib.rs`: the anisette server can be set with `MARTEN_ANISETTE_URL`; its HTTP clients check certificates, against the platform's roots and Apple's (`verified_client`), and provisioning addresses must be https on apple.com (`is_apple_address`)
- `omnisette/src/remote_anisette_v3.rs`, `omnisette/src/adi_proxy.rs`: certificates checked instead of accepted whatever they are, provisioning addresses checked, and the anisette state file written readable by its owner only
- `omnisette/src/apple_root.der`: Apple's root certificate, the same file as `plume_core/src/apple_root.der`
- `plume_core/src/utils/certificate.rs`: the signing key written readable by its owner only, in a folder only its owner can open
- `Cargo.toml` in both: workspace fields written out so each builds on its own
