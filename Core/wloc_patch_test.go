package main

import (
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"math"
	"testing"
)

func testLocation(lat, lon int64, accuracy uint64) []byte {
	var out []byte
	out = append(out, writeTag(1, wireVarint)...)
	out = append(out, writeVarint(uint64(lat))...)
	out = append(out, writeTag(2, wireVarint)...)
	out = append(out, writeVarint(uint64(lon))...)
	out = append(out, writeTag(3, wireVarint)...)
	out = append(out, writeVarint(accuracy)...)
	return out
}

func testWifiDevice(loc []byte) []byte {
	mac := []byte("aa:bb:cc:dd:ee:ff")
	var out []byte
	out = append(out, writeLengthDelimited(1, mac)...)
	out = append(out, writeLengthDelimited(2, loc)...)
	return out
}

func testFrame(payload []byte) []byte {
	magic := []byte{0, 1, 0, 0, 0, 1, 0, 0}
	var lenBytes [2]byte
	binary.BigEndian.PutUint16(lenBytes[:], uint16(len(payload)))
	var out []byte
	out = append(out, magic...)
	out = append(out, lenBytes[:]...)
	out = append(out, payload...)
	return out
}

func TestPatchWifiLocation(t *testing.T) {
	payload := writeLengthDelimited(2, testWifiDevice(testLocation(100, 200, 25)))
	body := testFrame(payload)
	c := wlocCoords{Latitude: 31.230416, Longitude: 121.473701, Accuracy: 50}

	patched, stats, err := patchWlocBody(body, c)
	if err != nil {
		t.Fatal(err)
	}
	if stats.WiFi != 1 || stats.Locations != 1 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
	if bytes.Equal(patched, body) {
		t.Fatal("body was not patched")
	}

	newLen := int(binary.BigEndian.Uint16(patched[8:10]))
	newPayload := patched[10 : 10+newLen]
	latBytes := append(writeTag(1, wireVarint), writeVarint(uint64(int64(math.Round(c.Latitude*1e8))))...)
	if !bytes.Contains(newPayload, latBytes) {
		t.Fatal("new latitude bytes not found")
	}
}

func TestPatchCellLocation(t *testing.T) {
	cell := writeLengthDelimited(5, testLocation(300, 400, 25))
	payload := writeLengthDelimited(22, cell)
	body := testFrame(payload)
	c := wlocCoords{Latitude: 22.544577, Longitude: 113.94114, Accuracy: 25}

	patched, stats, err := patchWlocBody(body, c)
	if err != nil {
		t.Fatal(err)
	}
	if stats.Cell != 1 || stats.Locations != 1 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
	if bytes.Equal(patched, body) {
		t.Fatal("body was not patched")
	}
}

func TestPatchGzip(t *testing.T) {
	payload := writeLengthDelimited(2, testWifiDevice(testLocation(100, 200, 25)))
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(testFrame(payload)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	c := wlocCoords{Latitude: 31.230416, Longitude: 121.473701, Accuracy: 50}

	patched, _, err := patchResponseBody(buf.Bytes(), c)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(patched, testFrame(payload)) {
		t.Fatal("gzip body was not patched")
	}
}

func TestTransparentBodyUnchanged(t *testing.T) {
	body := []byte{1, 2, 3, 4}
	_, _, err := patchResponseBody(body, wlocCoords{Latitude: 31.230416, Longitude: 121.473701, Accuracy: 25})
	if err == nil {
		t.Fatal("expected non-patchable body to error")
	}
}
