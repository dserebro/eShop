import { test, expect } from "@playwright/test";

// QA Report (qa-report.md) confirmed both endpoints respond within 5 ms.
// Tests use the Playwright `request` API — no browser needed for plain HTTP endpoints.

test.describe("PaymentProcessor health endpoint", () => {
  test("returns HTTP 200", async ({ request }) => {
    const response = await request.get("http://localhost:5226/health");
    expect(response.status()).toBe(200);
  });

  test("returns body 'Healthy'", async ({ request }) => {
    const response = await request.get("http://localhost:5226/health");
    const body = await response.text();
    expect(body.trim()).toBe("Healthy");
  });

  test("returns Content-Type text/plain", async ({ request }) => {
    const response = await request.get("http://localhost:5226/health");
    const contentType = response.headers()["content-type"] ?? "";
    expect(contentType).toContain("text/plain");
  });

  test("returns Server: Kestrel header", async ({ request }) => {
    const response = await request.get("http://localhost:5226/health");
    const server = response.headers()["server"] ?? "";
    expect(server).toContain("Kestrel");
  });
});

test.describe("OrderProcessor health endpoint", () => {
  test("returns HTTP 200", async ({ request }) => {
    const response = await request.get("http://localhost:16888/health");
    expect(response.status()).toBe(200);
  });

  test("returns body 'Healthy'", async ({ request }) => {
    const response = await request.get("http://localhost:16888/health");
    const body = await response.text();
    expect(body.trim()).toBe("Healthy");
  });

  test("returns Content-Type text/plain", async ({ request }) => {
    const response = await request.get("http://localhost:16888/health");
    const contentType = response.headers()["content-type"] ?? "";
    expect(contentType).toContain("text/plain");
  });

  test("returns Server: Kestrel header", async ({ request }) => {
    const response = await request.get("http://localhost:16888/health");
    const server = response.headers()["server"] ?? "";
    expect(server).toContain("Kestrel");
  });
});
