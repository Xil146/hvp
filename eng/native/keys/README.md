# MSYS2 signing-key staging

The production toolchain lock remains closed until this directory contains the
reviewed public-key material used to verify the dated MSYS2 base and package
signatures. `toolchain.lock.json` binds the complete directory tree hash; CI
does not fetch keys from a keyserver or trust a runner-global keyring.

Do not add a key based only on a fingerprint copied from a package signature.
Record its authenticated upstream source and maintainer review with the lock.
