# Install from an online config

Build the general ISO with `nix build .#iso`. Choose **Online config** in Setup,
enter `github:doromiert/zenos-next-config`, and select `doromi-tul-2`. The next
page asks for the existing account name (`doromiert`) and a new password.

The personal config remains in its own repository; it is not a distribution or
installer default. Setup fetches the immutable source, validates its canonical
host layout, and evaluates the complete host before disk operations. It retains
only that host and the single-ZenPkgs flake. Hardware, graphics and disk files
are regenerated from detection and the disk selection. The password is hashed
locally and appended to the selected account's ZCFG; plaintext is not written.

The configuration must directly import `hardware.zcfg`, `graphics.zcfg` and
`drives.zcfg`. Remote copies of these files are discarded. Online configs must
provide `users/<account>/main.zcfg` for the account selected on the user page;
Setup does not create additional accounts or enable OOBE for online installs.
Existing user preferences are retained through the usual canonical user-source
publication and materialized build snapshot.
