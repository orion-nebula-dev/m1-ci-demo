package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSum(t *testing.T) {
	if sum(-8, 50) != 42 {
		t.Fatal("incorrect sum")
	}
}

func TestHealth(t *testing.T) {
	response := httptest.NewRecorder()
	health(response, httptest.NewRequest(http.MethodGet, "/health", nil))
	var body map[string]string
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &body) != nil || body["status"] != "ok" {
		t.Fatal(response.Code, response.Body.String())
	}
}

func TestNotFound(t *testing.T) {
	response := httptest.NewRecorder()
	health(response, httptest.NewRequest(http.MethodGet, "/missing", nil))
	if response.Code != 404 {
		t.Fatal(response.Code)
	}
}
