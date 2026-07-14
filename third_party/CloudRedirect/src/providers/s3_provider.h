#pragma once
#include "cloud_provider.h"
#include <string>
#include <mutex>

// Generic S3-compatible provider (tested against Backblaze B2's S3-compatible
// API; should also work with AWS S3, Cloudflare R2, MinIO, etc.).
//
// Unlike GoogleDriveProvider/OneDriveProvider, this does NOT extend
// CloudProviderBase: there is no OAuth refresh-token dance here, just a
// static Key ID / Application Key signed into every request with AWS
// Signature Version 4 (SigV4). Always "authenticated" once Init() parses a
// valid config blob - there is no separate sign-in step.
//
// Config: Init() receives a single JSON string (built by the caller from
// config.json's s3_* fields - see cloud_intercept.cpp) shaped like:
//   {"endpoint":"s3.eu-central-003.backblazeb2.com",
//    "bucket":"mybucket","region":"eu-central-003",
//    "key_id":"...","secret_key":"..."}
//
// Addressing: path-style (https://ENDPOINT/BUCKET/key), not virtual-hosted
// style, since the endpoint given by Backblaze does not include the bucket.
class S3Provider : public ICloudProvider {
public:
    const char* Name() const override { return "S3/Backblaze B2"; }

    bool Init(const std::string& configJson) override;
    void Shutdown() override;
    bool IsAuthenticated() const override { return m_ready; }

    bool Upload(const std::string& path, const uint8_t* data, size_t len) override;
    bool Download(const std::string& path, std::vector<uint8_t>& outData) override;
    bool Remove(const std::string& path) override;
    ExistsStatus CheckExists(const std::string& path) override;
    std::vector<FileInfo> List(const std::string& prefix) override;

private:
    bool m_ready = false;
    std::string m_endpoint;   // host, e.g. "s3.eu-central-003.backblazeb2.com"
    std::string m_bucket;
    std::string m_region;     // e.g. "eu-central-003"
    std::string m_keyId;
    std::string m_secretKey;

    std::mutex m_mtx;
    class IHttpTransport* Transport();
    std::unique_ptr<class IHttpTransport> m_transport;

    // Performs one SigV4-signed request against m_endpoint. objectKey may be
    // empty for bucket-level operations (e.g. ListObjectsV2); query is the
    // already-encoded query string without a leading '?', or empty.
    struct SignedResult {
        int status = 0;
        std::string body;
    };
    SignedResult SignedRequest(const char* method, const std::string& objectKey,
                               const std::string& query, const std::string& body,
                               const char* contentSha256Override = nullptr);
};
