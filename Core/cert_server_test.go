package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestCertificateServerServesCurrentCAAndTrustedProbe(t *testing.T) {
	certPEM, keyPEM, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}

	server, err := startCertificateServer(certPEM, keyPEM)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })

	download, err := http.Get(server.DownloadURL())
	if err != nil {
		t.Fatal(err)
	}
	defer download.Body.Close()
	body, err := io.ReadAll(download.Body)
	if err != nil {
		t.Fatal(err)
	}
	if download.StatusCode != http.StatusOK {
		t.Fatalf("download status = %d", download.StatusCode)
	}
	if download.Header.Get("Content-Type") != "application/x-x509-ca-cert" {
		t.Fatalf("unexpected content type: %q", download.Header.Get("Content-Type"))
	}
	if !strings.Contains(download.Header.Get("Content-Disposition"), "LocationSpoofer-CA.cer") {
		t.Fatalf("unexpected content disposition: %q", download.Header.Get("Content-Disposition"))
	}
	root, err := x509.ParseCertificate(blockBytes(certPEM))
	if err != nil {
		t.Fatal(err)
	}
	if string(body) != string(root.Raw) {
		t.Fatal("downloaded certificate did not match input CA DER")
	}

	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(certPEM) {
		t.Fatal("could not add CA to pool")
	}
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool}}}
	probe, err := client.Get(server.ProbeURL())
	if err != nil {
		t.Fatal(err)
	}
	defer probe.Body.Close()
	response, err := io.ReadAll(probe.Body)
	if err != nil {
		t.Fatal(err)
	}
	if probe.StatusCode != http.StatusOK || string(response) != "ok\n" {
		t.Fatalf("probe response = %d %q", probe.StatusCode, response)
	}
	if server.LeafSHA256() == "" {
		t.Fatal("missing leaf SHA-256 fingerprint")
	}
}

func TestCertificateServerOnlyServesKnownPaths(t *testing.T) {
	certPEM, keyPEM, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	server, err := startCertificateServer(certPEM, keyPEM)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })

	response, err := http.Get(strings.TrimSuffix(server.DownloadURL(), "/ca.cer") + "/unknown")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", response.StatusCode)
	}
}

func blockBytes(certPEM []byte) []byte {
	block, _ := pem.Decode(certPEM)
	if block == nil {
		return nil
	}
	return block.Bytes
}

func TestCertificateServerRejectsDefaultTrustBeforeInstallation(t *testing.T) {
	certPEM, keyPEM, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	server, err := startCertificateServer(certPEM, keyPEM)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })

	response, err := http.Get(server.ProbeURL())
	if response != nil {
		response.Body.Close()
	}
	if err == nil {
		t.Fatal("default TLS trust unexpectedly accepted an uninstalled CA")
	}
}
