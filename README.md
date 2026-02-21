# PQC-PoC — PQC-enabled Nginx server (proof-of-concept)

This repository demonstrates how to set up an Nginx server using PQC-capable TLS. The goal is a small, reproducible PoC showing the pieces needed to run an HTTPS server that can use post-quantum or hybrid post-quantum key agreements when OpenSSL and Nginx are built with PQC support.

## What you'll find in this repo

- `Dockerfile` — container image for the Nginx server used in this PoC.
- `nginx.conf` — main Nginx configuration (TLS listener, general config).
- `default.conf` — example site configuration for the server.

> Note: This repo is a configuration PoC. The actual PQC behavior depends on your OpenSSL build (or provider) and Nginx build linking to that OpenSSL.

## Quick summary

1. Install/obtain an OpenSSL build that supports PQC (for example, OpenSSL with the OQS provider or a distribution that includes PQC-enabled algorithms).
2. Use an Nginx build that is linked against that same OpenSSL (so Nginx can use PQC algorithms via `ssl_conf_command`).
3. Generate `server.key` and `server.crt` (see section below). For testing you can use a standard self-signed cert; for PQC/hybrid keys, use an OpenSSL that exposes PQC algorithms.
4. Build and run the provided Docker image (or run Nginx locally), mounting `server.key` and `server.crt` into the container.

## Prerequisites

- OpenSSL version that supports PQC algorithms (or an OpenSSL build with an OQS provider). The exact version/name depends on how you installed/compiled OpenSSL. Verify your OpenSSL exposes PQC/hybrid key names and ciphersuites.
- Nginx built/linked against the PQC-capable OpenSSL. Nginx must be compiled or packaged to use that OpenSSL so the `ssl_conf_command` directives work as intended.
- Docker (for running the provided container image) or a way to run Nginx locally.

Important checks:

- Check OpenSSL version and available providers/algorithms (example):

```bash
# Simple version check
openssl version

# List public-key algorithms or ciphers exposed by your OpenSSL build
openssl list -public-key-algorithms | head -n 50
openssl list -signature-algorithms | head -n 50

# If using providers (OpenSSL 3.x + OQS provider), list providers
openssl list -providers
```

If you do not see PQC or hybrid algorithms, you need an OpenSSL build that includes them (for example, OpenSSL + liboqs or an OQS provider build).

## Generating server.key and server.crt

Two approaches are shown: a standard self-signed cert (easy for testing) and notes for generating PQC/hybrid keys when you have a PQC-capable OpenSSL.

1) Standard self-signed certificate (for quick testing)

```bash
# From the repo root (or wherever you like to store certs)
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout server.key -out server.crt -days 365 \
  -subj "/CN=localhost"

# Or ECDSA alternative
openssl ecparam -genkey -name prime256v1 -noout -out server.key
openssl req -new -key server.key -out server.csr -subj "/CN=localhost"
openssl x509 -req -in server.csr -signkey server.key -days 365 -out server.crt
```

2) PQC / hybrid key generation (requires PQC-enabled OpenSSL)

- The exact algorithm names depend on your OpenSSL/provider. First, enumerate the algorithms available (see "Prerequisites" verification commands above).
- Example workflow (replace `<ALG>` with the algorithm name exposed by your build):

```bash
# List available public-key algorithms to find the PQC/hybrid name
openssl list -public-key-algorithms | grep -i -E "kyber|sike|ntru|oqs|hybrid"

# Generate the private key using the algorithm name you found
openssl genpkey -algorithm <ALG> -out server.key

# Create a CSR and self-signed cert as usual
openssl req -new -key server.key -out server.csr -subj "/CN=localhost"
openssl x509 -req -in server.csr -signkey server.key -out server.crt -days 365
```

Note: If your OpenSSL provides hybrid algorithms they often have names like `p256_kyber768` or provider-specific names. Use `openssl list` to discover exact names. If you compiled OpenSSL with a provider like liboqs, consult that provider's docs for algorithm names.

## Example Nginx TLS snippet (using OpenSSL 3.x `ssl_conf_command`)

If Nginx is built to pass config through to OpenSSL 3.x, you can tune groups (curves) and ciphersuites. The following is illustrative — tune the names and lists to the algorithms your OpenSSL exposes.

```nginx
ssl_protocols TLSv1.3;
ssl_prefer_server_ciphers off;

# Example: pass named groups (curves / KEM groups) to OpenSSL
# Adjust to match your OpenSSL provider's names
ssl_conf_command Curves X25519MLKEM768,X25519,prime256v1,secp384r1;

# Example: pass ciphersuites (TLS 1.3-style names)
# The exact ciphersuite names that include PQC/hybrid entries depend on OpenSSL/provider
ssl_conf_command Ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256;

# Point to cert/key
ssl_certificate /etc/nginx/ssl/server.crt;
ssl_certificate_key /etc/nginx/ssl/server.key;
```

Notes:
- `Curves` (sometimes called named groups or KEM groups in PQC-enabled builds) is a comma-separated list.
- `Ciphersuites` for TLS 1.3 are colon-separated.
- Replace `X25519MLKEM768` and other PQC-specific names with what your OpenSSL exposes; mixing names that are not present will cause OpenSSL/Nginx to fail or ignore the specific entries.

## Docker: build and run

A simple build and run example using the provided `Dockerfile`.

```bash
# From the repo root
# Build the image
docker build -t pqc-nginx .

# Run the container, mounting certs into the expected path
# Adjust paths if your Dockerfile/Nginx expects a different location
docker run --rm -p 443:443 pqc-nginx
```

If you want to run the container in the background:

```bash
docker run -d --name pqc-nginx -p 443:443 pqc-nginx
```

Adjust mount targets if the Dockerfile uses a different path for certs.

## Testing the server

- Quick test using curl (insecure, for self-signed certs):

```bash
curl -vk --tlsv1.3 https://localhost/
```

- If you have browser access, add the certificate to your OS/browser trust store (only for local testing) or use a CA-signed cert.

- To verify the negotiated key exchange/cipher and see whether a PQC/hybrid algorithm was used, check the TLS handshake details in the client output (for example `openssl s_client -connect localhost:443 -tls1_3 -msg -debug`) or use tools that show negotiated TLS details.

Example:

```bash
openssl s_client -connect localhost:443 -tls1_3 -msg
```

Look for lines that show the key exchange or KEM being used. The exact output depends on your OpenSSL/client tooling.

## Troubleshooting

- Nginx fails to start after adding `ssl_conf_command`: ensure Nginx was built against the OpenSSL that exposes those commands (mismatch often causes errors).
- OpenSSL does not list PQC algorithms: you need an OpenSSL build with an OQS provider or liboqs integrated.
- If `openssl genpkey` fails for a PQC algorithm, verify the algorithm name via `openssl list -public-key-algorithms`.

## Security notes

- PQC and hybrid algorithms are rapidly evolving. Treat this repository as an experimental PoC, not production-ready configuration.
- Keep libraries up to date and monitor vendor guidance for PQC algorithm selection and deprecation.
- If you deploy publicly, use CA-signed certificates and ensure key/cert files have restrictive file permissions.

