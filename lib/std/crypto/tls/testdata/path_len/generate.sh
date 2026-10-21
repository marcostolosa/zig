#!/bin/sh
# Generates the certificates for tls/Client.zig test:
# "chain verification enforces pathLenConstraint".
#
# It builds two chains under a root CA with pathLenConstraint=0.
# This means that no intermediate CA is allowed.
# One chain: leaf -> root should be accepted, but leaf -> intermediate -> root
# should be rejected.
#
# Requires OpenSSL 3.4 or later.
#

set -eu
out=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# Trust anchor: a self-signed CA that allows no intermediate CAs below it.
openssl genrsa -out rootca.key 4096
openssl req -new -key rootca.key -x509 -out rootca.crt -not_before 20260101000000Z -not_after 20360101000000Z -sha256 \
  -subj "/C=DE/ST=Bavaria/L=Munich/O=MyOrg/OU=Engineering/CN=Trusted CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0"

# A leaf issued directly by the root.
openssl req -new -nodes -newkey rsa:4096 -keyout leaf.key -out leaf.req -batch \
  -subj "/C=DE/ST=Bavaria/L=Munich/O=MyOrg/OU=Engineering/CN=leaf.example"
openssl x509 -req -in leaf.req -CA rootca.crt -CAkey rootca.key -CAcreateserial \
  -out leaf.crt -not_before 20260101000000Z -not_after 20360101000000Z -sha256

# An intermediate CA issued by the root.
printf 'basicConstraints=critical,CA:TRUE\n' > intermediate.ext
openssl req -new -nodes -newkey rsa:4096 -keyout intermediate.key -out intermediate.req -batch \
  -subj "/C=DE/ST=Bavaria/L=Munich/O=MyOrg/OU=Engineering/CN=Intermediate CA"
openssl x509 -req -in intermediate.req -CA rootca.crt -CAkey rootca.key -CAcreateserial \
  -out intermediate.crt -not_before 20260101000000Z -not_after 20360101000000Z -sha256 -extfile intermediate.ext

# A leaf issued by the intermediate CA.
openssl req -new -nodes -newkey rsa:4096 -keyout chain_leaf.key -out chain_leaf.req -batch \
  -subj "/C=DE/ST=Bavaria/L=Munich/O=MyOrg/OU=Engineering/CN=chain-leaf.example"
openssl x509 -req -in chain_leaf.req -CA intermediate.crt -CAkey intermediate.key -CAcreateserial \
  -out chain_leaf.crt -not_before 20260101000000Z -not_after 20360101000000Z -sha256

openssl x509 -in rootca.crt       -outform DER -out "$out/root_ca.der"
openssl x509 -in leaf.crt         -outform DER -out "$out/leaf.der"
openssl x509 -in intermediate.crt -outform DER -out "$out/intermediate_ca.der"
openssl x509 -in chain_leaf.crt   -outform DER -out "$out/chain_leaf.der"
