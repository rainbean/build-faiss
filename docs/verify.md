# Verify a release

Every tag publishes a `SHA256SUMS-<tag>` file next to its archives, signed
keyless with [cosign](https://docs.sigstore.dev/cosign/signing/overview/) by the
GitHub Actions workflow that built them. The signature proves the checksums came
from that workflow at that tag; the checksums prove each archive is the one it
built, even if the bucket were tampered with.

Requires `cosign` 3.x (CI signs with v3, whose bundle format older releases
can't read) and `sha256sum`.

Download the archive(s) you want plus `SHA256SUMS-<tag>` and
`SHA256SUMS-<tag>.bundle` into one folder, then:

```shell
TAG=v1.15.1
cosign verify-blob --bundle "SHA256SUMS-$TAG.bundle" \
  --certificate-identity "https://github.com/rainbean/build-faiss/.github/workflows/build.yml@refs/tags/$TAG" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "SHA256SUMS-$TAG"
sha256sum -c --ignore-missing "SHA256SUMS-$TAG"
```

`--ignore-missing` skips archives you didn't download; each one you did must
print `OK`.

On Windows without `sha256sum`, compare by hand:

```powershell
$TAG = "v1.15.1"
(Get-FileHash faiss-win64-$TAG.7z -Algorithm SHA256).Hash.ToLower()
Select-String "faiss-win64-$TAG.7z" "SHA256SUMS-$TAG"
```

## Transparency log

Keyless signing records each signature in the public
[Rekor](https://docs.sigstore.dev/logging/overview/) transparency log. The entry
shows the repository, workflow, tag and the hash of `SHA256SUMS-<tag>`, but not
the archives themselves.
