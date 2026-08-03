package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"math/big"
	"net"
	"net/http"
	"sync"
	"time"
)

// certificateServer exposes a device-specific CA download before the Packet
// Tunnel starts and a TLS endpoint whose successful default validation proves
// that iOS has installed and fully trusted that CA.
type certificateServer struct {
	httpServer  *http.Server
	httpsServer *http.Server
	httpLn      net.Listener
	httpsLn     net.Listener
	leafSHA256  string
	closeOnce   sync.Once
	closeErr    error
}

func startCertificateServer(caCertPEM, caKeyPEM []byte) (*certificateServer, error) {
	ca, err := parseCA(caCertPEM, caKeyPEM)
	if err != nil {
		return nil, err
	}
	if !ca.Leaf.IsCA {
		return nil, errors.New("certificate server requires a CA certificate")
	}

	leaf, leafDER, err := issueLoopbackLeaf(ca)
	if err != nil {
		return nil, err
	}
	rootDER := ca.Leaf.Raw
	httpLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	httpsLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		_ = httpLn.Close()
		return nil, err
	}

	downloadMux := http.NewServeMux()
	downloadMux.HandleFunc("/ca.cer", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/x-x509-ca-cert")
		w.Header().Set("Content-Disposition", `attachment; filename="LocationSpoofer-CA.cer"`)
		_, _ = w.Write(rootDER)
	})

	probeMux := http.NewServeMux()
	probeMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		_, _ = w.Write([]byte("ok\n"))
	})

	server := &certificateServer{
		httpServer:  &http.Server{Handler: downloadMux},
		httpsServer: &http.Server{Handler: probeMux},
		httpLn:      httpLn,
		httpsLn:     httpsLn,
		leafSHA256:  sha256Base64(leafDER),
	}
	go func() {
		if err := server.httpServer.Serve(httpLn); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logEvent("certificate download server error: " + err.Error())
		}
	}()
	go func() {
		tlsListener := tls.NewListener(httpsLn, &tls.Config{Certificates: []tls.Certificate{leaf}, MinVersion: tls.VersionTLS12})
		if err := server.httpsServer.Serve(tlsListener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logEvent("certificate probe server error: " + err.Error())
		}
	}()
	return server, nil
}

func issueLoopbackLeaf(ca *tls.Certificate) (tls.Certificate, []byte, error) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return tls.Certificate{}, nil, err
	}
	serialLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, serialLimit)
	if err != nil {
		return tls.Certificate{}, nil, err
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "Location Spoofer Local Trust Probe"},
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage: []x509.ExtKeyUsage{
			x509.ExtKeyUsageServerAuth,
		},
		DNSNames:    []string{"localhost"},
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, ca.Leaf, &privateKey.PublicKey, ca.PrivateKey)
	if err != nil {
		return tls.Certificate{}, nil, err
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		return tls.Certificate{}, nil, err
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
	leaf, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		return tls.Certificate{}, nil, err
	}
	leaf.Leaf, err = x509.ParseCertificate(der)
	if err != nil {
		return tls.Certificate{}, nil, err
	}
	return leaf, der, nil
}

func sha256Base64(data []byte) string {
	sum := sha256.Sum256(data)
	return base64.StdEncoding.EncodeToString(sum[:])
}

func (s *certificateServer) DownloadURL() string {
	return "http://" + s.httpLn.Addr().String() + "/ca.cer"
}

func (s *certificateServer) ProbeURL() string {
	return "https://" + s.httpsLn.Addr().String() + "/health"
}

func (s *certificateServer) LeafSHA256() string { return s.leafSHA256 }

func (s *certificateServer) Close() error {
	s.closeOnce.Do(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if err := s.httpServer.Shutdown(ctx); err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.closeErr = err
		}
		if err := s.httpsServer.Shutdown(ctx); err != nil && !errors.Is(err, http.ErrServerClosed) && s.closeErr == nil {
			s.closeErr = err
		}
	})
	return s.closeErr
}
