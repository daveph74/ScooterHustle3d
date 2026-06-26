# Deploying Scooter Hustle to the web on AWS (S3 + CloudFront)

A Godot 4 web build is just static files, but it uses **threads**, which browsers
only allow when the page is "cross-origin isolated". That means the host must
send two response headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

S3 alone can't add those, but **CloudFront** can via a *Response Headers Policy*.
So the setup is: files in **S3** → served through **CloudFront** (which adds the
headers + HTTPS + CDN). Below is the one-time setup, then the repeat deploy.

> Prefer not to deal with headers? In Godot's Web export preset turn **Thread
> Support OFF**, and a plain S3 website bucket works with no CloudFront. Slightly
> lower performance. The rest of this doc assumes threads ON (recommended).

---

## One-time setup

### 1. Create the S3 bucket
- Any name, e.g. `scooter-hustle-web`. Region of your choice.
- **Keep "Block all public access" ON.** CloudFront reaches it privately via OAC
  (below), so the bucket itself stays private.

### 2. Create the COOP/COEP response-headers policy
Save this as `policy.json`:

```json
{
  "Name": "godot-coop-coep",
  "Comment": "Cross-origin isolation for Godot 4 web (threads)",
  "CustomHeadersConfig": {
    "Quantity": 2,
    "Items": [
      { "Header": "Cross-Origin-Opener-Policy",  "Value": "same-origin",  "Override": true },
      { "Header": "Cross-Origin-Embedder-Policy", "Value": "require-corp", "Override": true }
    ]
  }
}
```

Create it:

```bash
aws cloudfront create-response-headers-policy \
  --response-headers-policy-config file://policy.json
```

Note the returned policy **Id**.

### 3. Create the CloudFront distribution
Easiest in the console (*CloudFront → Create distribution*):
- **Origin**: your S3 bucket. Choose **"Origin access control settings (recommended)"**
  and let CloudFront create the **OAC**; click the button to **update the bucket
  policy** it generates (this is what lets CloudFront read the private bucket).
- **Viewer protocol policy**: *Redirect HTTP to HTTPS*.
- **Default root object**: `index.html`.
- **Response headers policy**: select **`godot-coop-coep`** from step 2.
- **Compression**: leave "Compress objects automatically" ON.

Wait for the distribution to deploy (~5 min). Your URL is `https://dXXXX.cloudfront.net`.

---

## Deploy (every time you update the game)

1. In Godot: **Project → Export → Web → Export Project** to `web/index.html`.
2. Run the deploy script with your bucket + distribution id:

```bash
S3_BUCKET=scooter-hustle-web CF_DISTRIBUTION_ID=E123ABC456 ./tools/deploy_web_aws.sh
```

It uploads the files with the correct content-types (notably `.wasm` →
`application/wasm`), removes stale files, and invalidates the CloudFront cache so
the new build shows up immediately.

3. Open `https://dXXXX.cloudfront.net` and play.

---

## Gotchas
- **`.wasm` content-type** must be `application/wasm` or the engine won't start —
  the deploy script enforces this.
- **Custom domain**: add an ACM certificate (in **us-east-1**) + an Alternate
  Domain Name (CNAME) on the distribution, then point your DNS at it.
- **It loads but errors about SharedArrayBuffer** → the COOP/COEP policy isn't
  attached to the distribution's default behavior (re-check step 3), or you're
  opening the S3 URL directly instead of the CloudFront URL.
- **Renderer**: web builds use the Compatibility renderer (set via
  `rendering_method.web` in `project.godot`); the rainstorm/shadows may look
  slightly different from desktop — worth a quick check.
