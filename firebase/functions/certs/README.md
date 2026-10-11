# Apple root certificates

The functions verify Apple's signatures against Apple's root CA certificates.
Download them once and drop the `.cer` files into THIS folder before deploying.

Get them from Apple's PKI page: https://www.apple.com/certificateauthority/

Download these (DER-encoded `.cer`):
- **Apple Root CA - G3 Root** (`AppleRootCA-G3.cer`) — required (App Store JWS chains to G3)
- Optionally also: **Apple Root CA - G2 Root** (`AppleRootCA-G2.cer`)

So this folder should contain, e.g.:
```
functions/certs/AppleRootCA-G3.cer
```

The code loads every `.cer` / `.der` / `.pem` file it finds here. They are
public certificates — safe to commit.
