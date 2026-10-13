# marten-mpl

Modified copies of `plume_core` and `omnisette` from [Impactor](https://github.com/claration/Impactor) at commit 6a322e2, as used by the installer in Marten. Both are under the Mozilla Public License 2.0 (`LICENSE` in each folder).

Changed files:

- `plume_core/src/auth/account/login.rs`: follows the password protocol the server asks for (`s2k_fo`), sends a current client identity
- `plume_core/src/auth/account/mod.rs`, `token.rs`, `two_factor_auth.rs`: the same client identity
- `omnisette/src/lib.rs`: the anisette server can be set with `MARTEN_ANISETTE_URL`
- `Cargo.toml` in both: workspace fields written out so each builds on its own
