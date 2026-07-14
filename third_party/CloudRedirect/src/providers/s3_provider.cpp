#include "s3_provider.h"
#include "cloud_provider_base.h"  // IHttpTransport, CreateHttpTransport, HttpUtil::HttpResp
#include "json.h"
#include "log.h"

#include <windows.h>
#include <wincrypt.h>
#include <ctime>
#include <cstring>
#include <algorithm>
#include <map>

#pragma comment(lib, "advapi32.lib")

using HttpUtil::HttpResp;

namespace {

// ---- SHA-256 / HMAC-SHA256 via Windows CryptoAPI ---------------------------
// Mirrors the approach already used for ComputeFileSHA256 elsewhere in this
// codebase (CryptAcquireContext + CALG_SHA_256), extended to (a) operate on
// an in-memory buffer and (b) support a keyed HMAC via the standard
// ipad/opad construction, since CryptoAPI's CALG_HMAC plumbing is far more
// verbose than just building HMAC out of a trusted SHA-256 primitive.

bool Sha256Raw(const uint8_t* data, size_t len, uint8_t out[32]) {
    HCRYPTPROV hProv = 0;
    HCRYPTHASH hHash = 0;
    bool ok = false;
    if (CryptAcquireContextW(&hProv, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT)) {
        if (CryptCreateHash(hProv, CALG_SHA_256, 0, 0, &hHash)) {
            if (CryptHashData(hHash, data, (DWORD)len, 0)) {
                DWORD hashLen = 32;
                ok = CryptGetHashParam(hHash, HP_HASHVAL, out, &hashLen, 0) && hashLen == 32;
            }
            CryptDestroyHash(hHash);
        }
        CryptReleaseContext(hProv, 0);
    }
    return ok;
}

std::string ToHex(const uint8_t* data, size_t len) {
    static const char hex[] = "0123456789abcdef";
    std::string out;
    out.reserve(len * 2);
    for (size_t i = 0; i < len; i++) {
        out += hex[data[i] >> 4];
        out += hex[data[i] & 0xF];
    }
    return out;
}

std::string Sha256Hex(const std::string& data) {
    uint8_t hash[32] = {};
    Sha256Raw(reinterpret_cast<const uint8_t*>(data.data()), data.size(), hash);
    return ToHex(hash, 32);
}

// HMAC-SHA256(key, msg) -> 32 raw bytes.
void HmacSha256(const uint8_t* key, size_t keyLen, const std::string& msg, uint8_t out[32]) {
    uint8_t blockKey[64] = {};
    if (keyLen > 64) {
        Sha256Raw(key, keyLen, blockKey); // longer keys get hashed down first
    } else {
        memcpy(blockKey, key, keyLen);
    }

    uint8_t ipad[64], opad[64];
    for (int i = 0; i < 64; i++) {
        ipad[i] = blockKey[i] ^ 0x36;
        opad[i] = blockKey[i] ^ 0x5c;
    }

    // inner = SHA256(ipad || msg)
    std::string innerInput(reinterpret_cast<char*>(ipad), 64);
    innerInput.append(msg);
    uint8_t inner[32];
    Sha256Raw(reinterpret_cast<const uint8_t*>(innerInput.data()), innerInput.size(), inner);

    // out = SHA256(opad || inner)
    std::string outerInput(reinterpret_cast<char*>(opad), 64);
    outerInput.append(reinterpret_cast<char*>(inner), 32);
    Sha256Raw(reinterpret_cast<const uint8_t*>(outerInput.data()), outerInput.size(), out);
}

void HmacSha256(const std::string& key, const std::string& msg, uint8_t out[32]) {
    HmacSha256(reinterpret_cast<const uint8_t*>(key.data()), key.size(), msg, out);
}

// ---- URI encoding per AWS SigV4 rules ---------------------------------------
// Unreserved: A-Z a-z 0-9 - _ . ~. Everything else percent-encoded.
// encodeSlash=false leaves '/' literal (needed for the canonical URI path,
// where '/' separates segments); encodeSlash=true is used for query values.
std::string UriEncode(const std::string& s, bool encodeSlash) {
    static const char hex[] = "0123456789ABCDEF";
    std::string out;
    out.reserve(s.size());
    for (unsigned char c : s) {
        bool unreserved = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                          (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~';
        if (unreserved || (c == '/' && !encodeSlash)) {
            out += (char)c;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 0xF];
        }
    }
    return out;
}

// yyyymmdd + yyyymmddThhmmssZ, both UTC.
void AmzDates(std::string& outDateStamp, std::string& outAmzDate) {
    time_t now = time(nullptr);
    struct tm tmv;
    gmtime_s(&tmv, &now);
    char buf1[16], buf2[24];
    strftime(buf1, sizeof(buf1), "%Y%m%d", &tmv);
    strftime(buf2, sizeof(buf2), "%Y%m%dT%H%M%SZ", &tmv);
    outDateStamp = buf1;
    outAmzDate = buf2;
}

// Minimal field extractor for S3 ListObjectsV2's flat XML response - not a
// general XML parser. Assumes no nested/attribute-bearing tags of the same
// name inside <Contents>, which holds for every S3-compatible implementation
// observed (AWS, Backblaze B2, R2, MinIO).
std::vector<std::string> ExtractAllBetween(const std::string& xml, const std::string& openTag,
                                            const std::string& closeTag) {
    std::vector<std::string> out;
    size_t pos = 0;
    for (;;) {
        size_t start = xml.find(openTag, pos);
        if (start == std::string::npos) break;
        start += openTag.size();
        size_t end = xml.find(closeTag, start);
        if (end == std::string::npos) break;
        out.push_back(xml.substr(start, end - start));
        pos = end + closeTag.size();
    }
    return out;
}

// Parses "2024-01-02T03:04:05.000Z" (S3 LastModified) to a Unix timestamp.
uint64_t ParseIso8601ToUnix(const std::string& iso) {
    struct tm tmv = {};
    int y, mo, d, h, mi, s;
    if (sscanf_s(iso.c_str(), "%d-%d-%dT%d:%d:%d", &y, &mo, &d, &h, &mi, &s) != 6)
        return 0;
    tmv.tm_year = y - 1900;
    tmv.tm_mon = mo - 1;
    tmv.tm_mday = d;
    tmv.tm_hour = h;
    tmv.tm_min = mi;
    tmv.tm_sec = s;
    return (uint64_t)_mkgmtime(&tmv);
}

} // namespace

// ─────────────────────────────────────────────────────────────────────────

class IHttpTransport* S3Provider::Transport() { return m_transport.get(); }

bool S3Provider::Init(const std::string& configJson) {
    auto cfg = Json::Parse(configJson);
    m_endpoint  = cfg["endpoint"].str();
    m_bucket    = cfg["bucket"].str();
    m_region    = cfg["region"].str();
    m_keyId     = cfg["key_id"].str();
    m_secretKey = cfg["secret_key"].str();

    if (m_endpoint.empty() || m_bucket.empty() || m_region.empty() ||
        m_keyId.empty() || m_secretKey.empty()) {
        LOG("[S3Provider] Init: missing one of endpoint/bucket/region/key_id/secret_key");
        m_ready = false;
        return false;
    }

    m_transport = CreateHttpTransport("[S3Provider]");
    if (!m_transport || !m_transport->Init()) {
        LOG("[S3Provider] Init: transport init failed");
        m_ready = false;
        return false;
    }

    m_ready = true;
    LOG("[S3Provider] Initialized: endpoint=%s bucket=%s region=%s",
        m_endpoint.c_str(), m_bucket.c_str(), m_region.c_str());
    return true;
}

void S3Provider::Shutdown() {
    m_ready = false;
}

S3Provider::SignedResult S3Provider::SignedRequest(const char* method, const std::string& objectKey,
                                                    const std::string& query, const std::string& body,
                                                    const char* contentSha256Override) {
    std::lock_guard<std::mutex> lock(m_mtx);
    SignedResult result;
    if (!m_ready || !Transport()) return result;

    std::string dateStamp, amzDate;
    AmzDates(dateStamp, amzDate);

    std::string contentSha256 = contentSha256Override ? contentSha256Override : Sha256Hex(body);

    // Path-style addressing: /{bucket}/{objectKey}. Each path segment is
    // percent-encoded individually; '/' stays literal between segments.
    std::string canonicalUri = "/" + UriEncode(m_bucket, true);
    if (!objectKey.empty()) {
        canonicalUri += "/";
        // Encode the key but keep internal '/' separators (it is itself a
        // "{accountId}/{appId}/blobs/{filename}"-shaped relative path).
        size_t start = 0;
        std::string encodedKey;
        while (start <= objectKey.size()) {
            size_t slash = objectKey.find('/', start);
            std::string seg = objectKey.substr(start, slash == std::string::npos ? std::string::npos : slash - start);
            if (!encodedKey.empty() || start > 0) encodedKey += "/";
            encodedKey += UriEncode(seg, true);
            if (slash == std::string::npos) break;
            start = slash + 1;
        }
        canonicalUri += encodedKey;
    }

    std::map<std::string, std::string> headers; // sorted by key (std::map default)
    headers["host"] = m_endpoint;
    headers["x-amz-content-sha256"] = contentSha256;
    headers["x-amz-date"] = amzDate;

    std::string canonicalHeaders, signedHeaders;
    for (auto& [k, v] : headers) {
        canonicalHeaders += k + ":" + v + "\n";
        if (!signedHeaders.empty()) signedHeaders += ";";
        signedHeaders += k;
    }

    std::string canonicalRequest = std::string(method) + "\n" +
        canonicalUri + "\n" +
        query + "\n" +
        canonicalHeaders + "\n" +
        signedHeaders + "\n" +
        contentSha256;

    std::string scope = dateStamp + "/" + m_region + "/s3/aws4_request";
    std::string stringToSign = "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" +
        Sha256Hex(canonicalRequest);

    uint8_t kSecret[32];
    std::string seedKey = "AWS4" + m_secretKey;
    HmacSha256(seedKey, dateStamp, kSecret);
    uint8_t kRegion[32];
    HmacSha256(kSecret, 32, m_region, kRegion);
    uint8_t kService[32];
    HmacSha256(kRegion, 32, std::string("s3"), kService);
    uint8_t kSigning[32];
    HmacSha256(kService, 32, std::string("aws4_request"), kSigning);
    uint8_t sig[32];
    HmacSha256(kSigning, 32, stringToSign, sig);
    std::string signature = ToHex(sig, 32);

    std::string authHeader = "AWS4-HMAC-SHA256 Credential=" + m_keyId + "/" + scope +
        ", SignedHeaders=" + signedHeaders + ", Signature=" + signature;

    std::vector<std::string> httpHeaders = {
        "x-amz-content-sha256: " + contentSha256,
        "x-amz-date: " + amzDate,
        "Authorization: " + authHeader,
    };

    std::string path = canonicalUri;
    if (!query.empty()) path += "?" + query;

    HttpResp resp = Transport()->Request(method, m_endpoint.c_str(), path, body, httpHeaders);
    result.status = resp.status;
    result.body = resp.body;
    return result;
}

bool S3Provider::Upload(const std::string& path, const uint8_t* data, size_t len) {
    std::string body(reinterpret_cast<const char*>(data), len);
    auto r = SignedRequest("PUT", path, "", body);
    if (r.status < 200 || r.status >= 300) {
        LOG("[S3Provider] Upload failed for %s: HTTP %d", path.c_str(), r.status);
        return false;
    }
    return true;
}

bool S3Provider::Download(const std::string& path, std::vector<uint8_t>& outData) {
    // Empty-body GET: content sha256 is the well-known hash of the empty string.
    auto r = SignedRequest("GET", path, "", "",
                           "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    if (r.status != 200) {
        LOG("[S3Provider] Download failed for %s: HTTP %d", path.c_str(), r.status);
        return false;
    }
    outData.assign(r.body.begin(), r.body.end());
    return true;
}

bool S3Provider::Remove(const std::string& path) {
    auto r = SignedRequest("DELETE", path, "", "",
                           "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    // S3-compatible DELETE returns 204 on success, and typically 204 even if
    // the key never existed (idempotent delete) - treat both as success.
    return r.status == 204 || r.status == 200;
}

ICloudProvider::ExistsStatus S3Provider::CheckExists(const std::string& path) {
    auto r = SignedRequest("HEAD", path, "", "",
                           "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    if (r.status == 200) return ExistsStatus::Exists;
    if (r.status == 404) return ExistsStatus::Missing;
    return ExistsStatus::Error;
}

std::vector<ICloudProvider::FileInfo> S3Provider::List(const std::string& prefix) {
    std::vector<FileInfo> out;
    std::string continuationToken;
    for (;;) {
        std::string query = "list-type=2&prefix=" + UriEncode(prefix, true) + "&max-keys=1000";
        if (!continuationToken.empty())
            query += "&continuation-token=" + UriEncode(continuationToken, true);

        auto r = SignedRequest("GET", "", query, "",
                               "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        if (r.status != 200) {
            LOG("[S3Provider] List failed for prefix %s: HTTP %d", prefix.c_str(), r.status);
            break;
        }

        auto keys = ExtractAllBetween(r.body, "<Key>", "</Key>");
        auto sizes = ExtractAllBetween(r.body, "<Size>", "</Size>");
        auto mtimes = ExtractAllBetween(r.body, "<LastModified>", "</LastModified>");
        size_t n = keys.size();
        for (size_t i = 0; i < n; i++) {
            FileInfo fi;
            fi.path = keys[i];
            fi.size = i < sizes.size() ? strtoull(sizes[i].c_str(), nullptr, 10) : 0;
            fi.modifiedTime = i < mtimes.size() ? ParseIso8601ToUnix(mtimes[i]) : 0;
            out.push_back(std::move(fi));
        }

        auto truncated = ExtractAllBetween(r.body, "<IsTruncated>", "</IsTruncated>");
        auto nextToken = ExtractAllBetween(r.body, "<NextContinuationToken>", "</NextContinuationToken>");
        if (!truncated.empty() && truncated[0] == "true" && !nextToken.empty()) {
            continuationToken = nextToken[0];
            continue;
        }
        break;
    }
    return out;
}
