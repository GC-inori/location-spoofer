package main

import (
	"crypto/x509"
	"encoding/pem"
	"testing"
	"time"
)

func TestGenerateCA(t *testing.T) {
	certPEM, keyPEM, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	if len(certPEM) == 0 || len(keyPEM) == 0 {
		t.Fatal("empty CA output")
	}
	block, _ := pem.Decode(certPEM)
	if block == nil {
		t.Fatal("invalid cert PEM")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	if !cert.IsCA {
		t.Fatal("certificate is not a CA")
	}
	if time.Until(cert.NotAfter).Hours() < 360*24 {
		t.Fatal("CA validity is too short")
	}
	if _, err := parseCA(certPEM, keyPEM); err != nil {
		t.Fatal(err)
	}
}

func TestGenerateCAUsesUniquePrivateKeys(t *testing.T) {
	_, firstKey, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	_, secondKey, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	if string(firstKey) == string(secondKey) {
		t.Fatal("generated CA private keys must not be deterministic")
	}
}
