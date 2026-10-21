#!/bin/sh
# Generates the certificates for tls/Client.zig test:
# "chain verification rejects a non-CA certificate acting as an issuer".
#
# It builds a chain with a non-CA certificate which is used to sign a certificate
# for a hostname its owner does not control.
# A conforming TLS client rejects the chain because attacker_leaf is not a CA.
#
# Requires OpenSSL 3.4 or later.
#

set -eu
out=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# Trust anchor: a real self-signed CA.
openssl genrsa -out rootca.key 4096
openssl req -new -key rootca.key -x509 -out rootca.crt -not_before 20260101000000Z -not_after 20360101000000Z -sha256 \
  -subj "/C=DE/ST=Bavaria/L=Munich/O=MyOrg/OU=Engineering/CN=Trusted CA" \
  -addext "basicConstraints=critical,CA:TRUE"

# An ordinary leaf certificate which the attacker legitimately owns.
# Signed by the CA with no requested extensions so it is not a CA.
openssl req -new -nodes -newkey rsa:4096 -keyout attacker.key -out attacker.req -batch \
  -subj "/C=DE/ST=Bavaria/L=Munich/O=Music/OU=DJing/CN=trance.bayern"
openssl x509 -req -in attacker.req -CA rootca.crt -CAkey rootca.key -CAcreateserial \
  -out attacker.crt -not_before 20260101000000Z -not_after 20360101000000Z -sha256

# The forged certificate for wedontownit.com, signed with the attacker's leaf key.
openssl req -new -nodes -newkey rsa:4096 -keyout forged.key -out forged.req -batch \
  -subj "/C=DE/ST=Bavaria/L=Munich/O=MyOrg/OU=Engineering/CN=wedontownit.com"
openssl x509 -req -in forged.req -CA attacker.crt -CAkey attacker.key -CAcreateserial \
  -out forged.crt -not_before 20260101000000Z -not_after 20360101000000Z -sha256

openssl x509 -in rootca.crt   -outform DER -out "$out/root_ca.der"
openssl x509 -in attacker.crt -outform DER -out "$out/attacker_leaf.der"
openssl x509 -in forged.crt   -outform DER -out "$out/forged_leaf.der"

