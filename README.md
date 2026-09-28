# Image proxy service — Varnish + imgproxy

## Layout
- `default.vcl` — public entry point: tenant resolution, param
  validation/clamping, cache-key normalization, imgproxy URL building.
- `tenants.vcl` — per-customer origin + plan limits. Regenerate and
  reload whenever a customer signs up, changes plan, or is removed.
- `docker-compose.yml` — Varnish (public) in front of imgproxy
  (private, unreachable from outside the stack).

## Dependency: `libvmod-querystring`
`default.vcl` uses `import querystring;`, which is the community
`libvmod-querystring` module, not part of core Varnish. Either:
- install `varnish-modules` in your Varnish image (`apt install
  varnish-modules` on Debian-based images covers it), or
- swap the three `querystring.get(...)` calls for manual `regsub()`
  parsing if you'd rather avoid the extra dependency.

## Usage
```
GET https://img.yourservice.com/t/acme/products/shoe-42.jpg?w=400&h=300&fit=cover&q=80
```
Unknown `w`/`h`/`fit`/`q` values fall back to sane defaults rather than
erroring; unknown `t/<tenant_id>` returns 404.

## Reloading tenants
```
docker compose exec varnish varnishreload   # or restart the container
```
For a handful to low hundreds of tenants, regenerating and reloading
`tenants.vcl` is fine. Past that, replace `vcl_tenant_lookup` with a
call into a fast external store (`vmod_redis`, or an internal HTTP
lookup via `vmod_curl`) so onboarding a customer doesn't require a
VCL reload at all.

## Testing

### Path A — real stack, with Docker
```
docker compose up -d
curl -D - "http://localhost/t/acme/some/path.jpg?w=300&h=200&fit=cover&q=70"
```
First request → `X-Cache: MISS`. Repeat it → `X-Cache: HIT`. Point
`tenants.vcl`'s `acme` origin at an image host you actually control
before doing this for real — `media.acme-corp.com` in the shipped file
is a placeholder.

### Path B — VCL logic only, no Docker needed
This is what was actually used to validate this VCL before handing it
to you (Varnish installed directly, imgproxy swapped for a stub that
echoes the request path back so you can see exactly what Varnish
built, without needing a real image backend):

```
apt-get install -y varnish
python3 -m http.server 9090 --directory ./origin-content &   # stand-in origin
python3 stub_imgproxy.py &                                    # echoes path it receives

sed 's/.host = "imgproxy";/.host = "127.0.0.1";/' default.vcl > /tmp/default.vcl
sed 's#http://origin:80#http://127.0.0.1:9090#' tenants.vcl > /tmp/tenants.vcl

varnishd -a :6081 -f /tmp/default.vcl -p vcl_path=/tmp -n /tmp/vinst
curl -D - "http://127.0.0.1:6081/t/acme/shoe-42.jpg?w=300&h=200&fit=cover&q=70"
```

Worth checking specifically:
- First request → `X-Cache: MISS`; repeat → `HIT`.
- `?h=200&w=300...` vs `?w=300&h=200...` (params reordered) → same
  cache entry, confirming the canonical-key normalization works.
- Unknown tenant (`/t/nope/...`) → `404`.
- Oversized `w`/`h` → clamped to that tenant's `MaxDim`, not silently
  zeroed. **This VCL originally had a real bug here** caught by
  running exactly this test: an over-the-global-ceiling value was
  being reset to `0` (meaning "unconstrained") before the per-tenant
  clamp ever ran, so a request for `w=9999` came out completely
  unclamped instead of capped at the tenant's plan limit. Fixed by
  clamping to the global ceiling first, then to the tenant's limit,
  instead of zeroing on overflow.
- `Accept: image/avif` vs a plain browser `Accept` → different `f:`
  value in the URL imgproxy would receive, confirming format bucketing
  works without needing `Vary: Accept`.

## Not yet included — worth adding before real external launch
- **Per-tenant rate limiting.** `X-Tenant-MaxRPS` is set in
  `tenants.vcl` but not enforced yet. `vmod_vsthrottle` (a community
  vmod, token-bucket style) is the usual way to do this in VCL —
  happy to wire it in.
- **Metrics/billing hooks.** You'll likely want per-tenant
  request/byte counters for usage-based billing — `varnishncsa` piping
  to your own log processor, keyed on `X-Tenant-Id`, is the simplest
  start.
- **TLS termination.** This compose file serves plain HTTP on :80.
  Put a TLS-terminating proxy (or Varnish's own PROXY-protocol setup
  behind an LB) in front for production.
