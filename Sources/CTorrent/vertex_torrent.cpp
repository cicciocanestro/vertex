#include "vertex_torrent.h"

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/address.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/portmap.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/extensions/smart_ban.hpp>
#include <libtorrent/extensions/ut_metadata.hpp>
#include <libtorrent/extensions/ut_pex.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/socket.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <exception>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <locale>
#include <memory>
#include <set>
#include <unordered_set>
#include <sstream>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

// Same error contract for the public operations: report the exception through
// last_error and return the bridge's failure value.
#define VT_CATCH_ALL(session_ptr, fallback)                                      \
    catch (std::exception const& e)                                             \
    {                                                                           \
        (session_ptr)->last_error = e.what();                                   \
        return fallback;                                                        \
    }                                                                           \
    catch (...)                                                                 \
    {                                                                           \
        (session_ptr)->last_error = "Errore sconosciuto";                       \
        return fallback;                                                        \
    }

namespace {

/// Returns the length in bytes (1..4) of a valid RFC 3629 UTF-8 code point at
/// `p` when at least that many bytes are available in `remaining`, or 0 when
/// the byte sequence is malformed (overlong, surrogate, or > U+10FFFF).
std::size_t utf8_sequence_length(unsigned char const* p, std::size_t remaining)
{
    if (remaining == 0)
        return 0;
    unsigned char const c = p[0];
    if (c < 0x80)
        return 1;

    if (c >= 0xC2 && c <= 0xDF)
    {
        if (remaining < 2)
            return 0;
        return (p[1] & 0xC0) == 0x80 ? 2 : 0;
    }

    if (c >= 0xE0 && c <= 0xEF)
    {
        if (remaining < 3)
            return 0;
        unsigned char const c1 = p[1];
        unsigned char const c2 = p[2];
        if ((c2 & 0xC0) != 0x80)
            return 0;
        if (c == 0xE0)
            return (c1 >= 0xA0 && c1 <= 0xBF) ? 3 : 0; // reject overlong
        if (c == 0xED)
            return (c1 >= 0x80 && c1 <= 0x9F) ? 3 : 0; // reject surrogates
        return (c1 & 0xC0) == 0x80 ? 3 : 0;
    }

    if (c >= 0xF0 && c <= 0xF4)
    {
        if (remaining < 4)
            return 0;
        unsigned char const c1 = p[1];
        unsigned char const c2 = p[2];
        unsigned char const c3 = p[3];
        if ((c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80)
            return 0;
        if (c == 0xF0)
            return (c1 >= 0x90 && c1 <= 0xBF) ? 4 : 0; // reject overlong
        if (c == 0xF4)
            return (c1 >= 0x80 && c1 <= 0x8F) ? 4 : 0; // reject > U+10FFFF
        return (c1 & 0xC0) == 0x80 ? 4 : 0;
    }

    return 0;
}

/// Validate UTF-8 strictly according to RFC 3629 without allocating.
/// Rejects overlong sequences, UTF-16 surrogates, and values above U+10FFFF.
bool is_valid_utf8(std::string const& input)
{
    auto const* bytes = reinterpret_cast<unsigned char const*>(input.data());
    std::size_t i = 0;
    std::size_t const n = input.size();
    while (i < n)
    {
        std::size_t const len = utf8_sequence_length(bytes + i, n - i);
        if (len == 0)
            return false;
        i += len;
    }
    return true;
}

std::string json_escape(std::string const& input)
{
    std::string out;
    out.reserve(input.size() + 16);
    auto const* bytes = reinterpret_cast<unsigned char const*>(input.data());
    std::size_t i = 0;
    std::size_t const n = input.size();

    while (i < n)
    {
        std::size_t const len = utf8_sequence_length(bytes + i, n - i);
        if (len == 1)
        {
            unsigned char const c = bytes[i];
            switch (c)
            {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20)
                {
                    char buffer[7];
                    std::snprintf(buffer, sizeof(buffer), "\\u%04x", c);
                    out += buffer;
                }
                else
                {
                    out += static_cast<char>(c);
                }
            }
            ++i;
        }
        else if (len > 1)
        {
            out.append(input, i, len);
            i += len;
        }
        else
        {
            out += "\\ufffd";
            ++i;
        }
    }
    return out;
}

std::string to_hex(lt::sha1_hash const& hash)
{
    static char const* digits = "0123456789abcdef";
    std::string out;
    out.reserve(std::size_t(hash.size()) * 2);
    auto const* bytes = reinterpret_cast<unsigned char const*>(hash.data());
    for (int i = 0; i < hash.size(); ++i)
    {
        out += digits[bytes[i] >> 4];
        out += digits[bytes[i] & 0x0f];
    }
    return out;
}

namespace {
    int hexVal(char c)
    {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return 16;
    }
}

/// Decodes a hex string into a byte buffer. Returns false when the length does
/// not match `outSize * 2` or any character is invalid. It is the inverse of
/// `to_hex` and lives next to it so the pair cannot drift apart.
bool from_hex(std::string const& hex, char* out, std::size_t outSize)
{
    if (hex.size() != outSize * 2)
        return false;
    for (std::size_t i = 0; i < outSize; ++i)
    {
        int high = hexVal(hex[i * 2]);
        int low = hexVal(hex[i * 2 + 1]);
        if (high > 15 || low > 15)
            return false;
        out[i] = static_cast<char>((high << 4) | low);
    }
    return true;
}

std::string torrent_id(lt::torrent_status const& status)
{
    return to_hex(status.info_hashes.get_best());
}

// Mirrors Preferences.resolvedDownloadPath on the Swift side. The C++ copy is
// the last-resort safety net for resume data and callers without a save path;
// keep the two rule sets aligned and covered by the path tests.
std::string normalized_save_path(std::string const& requested, std::string const& fallback)
{
    namespace fs = std::filesystem;
    std::string candidate = requested.empty() ? fallback : requested;

    // MEDIUM #7: trim and expand ~ exactly like Preferences.resolvedDownloadPath,
    // so the path the Swift side normalizes and the one the C++ side uses for
    // resume data and save_path can never drift apart.
    auto trim = [](std::string& s) {
        auto first = s.find_first_not_of(" \t\n\r");
        if (first == std::string::npos) { s.clear(); return; }
        auto last = s.find_last_not_of(" \t\n\r");
        s = s.substr(first, last - first + 1);
    };
    trim(candidate);
    if (!candidate.empty() && candidate[0] == '~')
    {
        char const* home = std::getenv("HOME");
        if (home && *home)
            candidate = std::string(home) + candidate.substr(1);
    }

    std::error_code ec;
    fs::path path(candidate);
    auto status = fs::status(path, ec);
    if (!ec)
    {
        if (fs::is_regular_file(status))
        {
            // A file was used as destination (often a .torrent): use its folder.
            candidate = path.parent_path().string();
        }
    }
    else if (path.extension() == ".torrent")
    {
        candidate = path.parent_path().string();
    }

    return candidate.empty() ? fallback : candidate;
}

bool is_usable_directory(std::string const& path)
{
    namespace fs = std::filesystem;
    std::error_code ec;
    fs::create_directories(path, ec);
    return !ec && ::access(path.c_str(), W_OK) == 0;
}

std::string prepared_save_path(std::string const& requested, std::string const& fallback)
{
    std::string candidate = normalized_save_path(requested, fallback);
    if (!is_usable_directory(candidate) && is_usable_directory(fallback))
        candidate = fallback;
    return candidate;
}

bool has_flag(lt::torrent_flags_t flags, lt::torrent_flags_t flag)
{
    return bool(flags & flag);
}

std::string portmap_transport_string(lt::portmap_transport transport)
{
    return transport == lt::portmap_transport::upnp ? "UPnP" : "NAT-PMP";
}

// listen_interfaces expects "ip:port" pairs, with IPv6 literals in brackets.
// An empty bind address keeps the historical behaviour: every interface, IPv4
// and IPv6.
std::string listen_interfaces_setting(int listen_port, std::string const& bind_address)
{
    if (bind_address.empty())
        return "0.0.0.0:" + std::to_string(listen_port) +
               ",[::]:" + std::to_string(listen_port);

    if (bind_address.find(':') == std::string::npos)
        return bind_address + ":" + std::to_string(listen_port);
    return "[" + bind_address + "]:" + std::to_string(listen_port);
}

} // namespace

struct portmap_state
{
    bool mapped = false;
    int external_port = 0;
    std::string transport;
    lt::port_mapping_t mapping{};
    std::string error;

    void reset()
    {
        mapped = false;
        external_port = 0;
        transport.clear();
        mapping = lt::port_mapping_t{};
        error.clear();
    }

    void mark_mapped(int port, std::string const& transport_name, lt::port_mapping_t map)
    {
        mapped = true;
        external_port = port;
        transport = transport_name;
        mapping = map;
        error.clear();
    }

    void mark_failed(std::string const& message)
    {
        mapped = false;
        external_port = 0;
        transport.clear();
        mapping = lt::port_mapping_t{};
        error = message;
    }
};

struct vt_session
{
    std::unique_ptr<lt::session> session;
    std::string default_save_path;
    std::string resume_dir;
    int listen_port = 6881;
    // Local address the session is pinned to. Empty means every interface.
    std::string bind_address;
    // Last listen_failed_alert, cleared by the next listen_succeeded_alert. It
    // is what tells the UI that the bound address disappeared (tunnel down).
    std::string listen_error;
    int dht_metric_index = -1;
    int dht_nodes = 0;
    // Synchronous operation error, read and cleared by vt_last_error().
    std::string last_error;
    // Asynchronous add_torrent/torrent_error alert, surfaced once by the
    // snapshot. Keeping it separate prevents an alert from overwriting the
    // error of an operation the UI is about to report.
    std::string last_alert_error;
    int actual_listen_port = 0;
    bool listening = false;
    bool upnp_enabled = true;
    portmap_state tcp;
    portmap_state udp;
    // Error whose TCP/UDP protocol could not be determined from the alert.
    std::string portmap_error;
    // Proxy configuration state
    int proxy_type = 0; // 0 = none, 1 = socks5
    // True when a username is configured: libtorrent only performs RFC 1929
    // authentication with the socks5_pw proxy type and a non-empty username.
    bool proxy_auth = false;
    std::string proxy_host;
    int proxy_port = 1080;
    std::string proxy_error;
    // Ids of torrents removed by the user: late resume-data alerts must not recreate their files.
    // Bounded FIFO: such alerts only arrive shortly after the removal. The set
    // mirrors the deque so membership tests stay O(1) instead of scanning the
    // up-to-256 entries linearly.
    std::deque<std::string> removed_ids;
    std::unordered_set<std::string> removed_ids_set;
    std::chrono::steady_clock::time_point last_stats;
    std::chrono::steady_clock::time_point last_resume_save;
};

namespace {

lt::torrent_handle find_handle(vt_session* session, std::string const& id)
{
    // Fast path: ids are always 40 hex (get_best() truncates a v2 hash to
    // SHA-1). libtorrent indexes v1 hashes, so a v1 id resolves in O(1)
    // without scanning every torrent or allocating a hex string per torrent.
    // A v2-only torrent's truncated hash may not be indexed; the linear
    // fallback below compares get_best() and covers it.
    if (id.size() == 40)
    {
        lt::sha1_hash hash;
        if (from_hex(id, hash.data(), static_cast<std::size_t>(lt::sha1_hash::size())))
        {
            auto handle = session->session->find_torrent(hash);
            if (handle.is_valid())
                return handle;
        }
    }

    for (auto const& handle : session->session->get_torrents())
    {
        try
        {
            if (handle.is_valid() && to_hex(handle.info_hashes().get_best()) == id)
                return handle;
        }
        catch (...)
        {
        }
    }
    return {};
}

constexpr std::size_t removed_ids_limit = 256;

bool is_removed(vt_session const* session, std::string const& id)
{
    return session->removed_ids_set.find(id) != session->removed_ids_set.end();
}

void mark_removed(vt_session* session, std::string const& id)
{
    if (!session->removed_ids_set.insert(id).second)
        return;
    session->removed_ids.push_back(id);
    while (session->removed_ids.size() > removed_ids_limit)
    {
        session->removed_ids_set.erase(session->removed_ids.front());
        session->removed_ids.pop_front();
    }
}

void unmark_removed(vt_session* session, std::string const& id)
{
    session->removed_ids_set.erase(id);
    session->removed_ids.erase(
        std::remove(session->removed_ids.begin(), session->removed_ids.end(), id),
        session->removed_ids.end());
}

void reset_portmap_state(vt_session* session)
{
    session->tcp.reset();
    session->udp.reset();
    session->portmap_error.clear();
}

void apply_link_settings(lt::settings_pack& settings,
                         int download_limit_bytes,
                         int upload_limit_bytes,
                         int enable_dht,
                         int enable_upnp,
                         int enable_lsd)
{
    settings.set_int(lt::settings_pack::download_rate_limit, (std::max)(0, download_limit_bytes));
    settings.set_int(lt::settings_pack::upload_rate_limit, (std::max)(0, upload_limit_bytes));
    settings.set_bool(lt::settings_pack::enable_dht, enable_dht != 0);
    settings.set_bool(lt::settings_pack::enable_upnp, enable_upnp != 0);
    settings.set_bool(lt::settings_pack::enable_natpmp, enable_upnp != 0);
    settings.set_bool(lt::settings_pack::enable_lsd, enable_lsd != 0);
}

int add_torrent_common(vt_session* session,
                       lt::add_torrent_params& params,
                       const char* save_path,
                       int paused,
                       int sequential)
{
    params.save_path = prepared_save_path(
        save_path && *save_path ? save_path : session->default_save_path,
        session->default_save_path);
    params.flags |= lt::torrent_flags::duplicate_is_error;
    params.flags &= ~lt::torrent_flags::auto_managed;
    // add_torrent_params::default_flags includes `paused`: clear it unless requested.
    if (paused)
        params.flags |= lt::torrent_flags::paused;
    else
        params.flags &= ~lt::torrent_flags::paused;
    if (sequential)
        params.flags |= lt::torrent_flags::sequential_download;

    auto const added_id = to_hex(params.info_hashes.get_best());
    lt::error_code add_ec;
    session->session->add_torrent(std::move(params), add_ec);
    if (add_ec)
    {
        session->last_error = add_ec.message();
        return -1;
    }
    unmark_removed(session, added_id);
    return 0;
}

bool write_resume_impl(std::string const& resume_dir, lt::add_torrent_params const& params)
{
    try
    {
        auto buffer = lt::write_resume_data_buf(params);
        auto id = to_hex(params.info_hashes.get_best());
        if (id.empty())
            return false;

        fs::path final_path = fs::path(resume_dir) / (id + ".resume");
        fs::path tmp_path = final_path;
        tmp_path += ".tmp";

        auto write_file = [&]() -> bool {
            std::ofstream file(tmp_path, std::ios::binary | std::ios::trunc);
            if (!file)
                return false;
            file.write(buffer.data(), static_cast<std::streamsize>(buffer.size()));
            return bool(file);
        };

        // The directory is created once with the session; recreate it only if
        // it disappeared, so the periodic save does not hit the filesystem.
        if (!write_file())
        {
            std::error_code dir_ec;
            fs::create_directories(resume_dir, dir_ec);
            if (dir_ec || !write_file())
                return false;
        }

        std::error_code ec;
        fs::rename(tmp_path, final_path, ec);
        if (ec)
        {
            fs::remove(tmp_path, ec);
            return false;
        }
        return true;
    }
    catch (...)
    {
        return false;
    }
}

void append_torrent_json(std::ostringstream& out, lt::torrent_status const& status)
{
    std::int64_t size = status.total;
    if (size <= 0)
        size = status.total_done;

    std::int64_t wanted = status.total_wanted > 0 ? status.total_wanted : size;
    std::int64_t remaining = (std::max)(std::int64_t(0), wanted - status.total_wanted_done);
    std::int64_t eta = -1;
    if (status.is_finished || status.is_seeding)
        eta = 0;
    else if (status.download_payload_rate > 0)
        eta = remaining / status.download_payload_rate;

    double ratio = 0.0;
    if (status.all_time_download > 0)
        ratio = double(status.all_time_upload) / double(status.all_time_download);
    else if (status.total_download > 0)
        ratio = double(status.total_upload) / double(status.total_download);

    out << "{";
    out << "\"id\":\"" << torrent_id(status) << "\",";
    out << "\"name\":\"" << json_escape(status.name) << "\",";
    out << "\"state_code\":" << static_cast<int>(status.state) << ",";
    out << "\"progress\":" << std::fixed << std::setprecision(5) << double(status.progress) << ",";
    out << "\"size\":" << size << ",";
    out << "\"downloaded\":" << status.total_done << ",";
    out << "\"uploaded\":" << (status.all_time_upload > 0 ? status.all_time_upload : status.total_upload) << ",";
    out << "\"download_rate\":" << status.download_payload_rate << ",";
    out << "\"upload_rate\":" << status.upload_payload_rate << ",";
    out << "\"peers\":" << status.num_peers << ",";
    out << "\"seeds\":" << status.num_seeds << ",";
    out << "\"eta\":" << eta << ",";
    out << "\"finished\":" << ((status.is_finished || status.is_seeding) ? "true" : "false") << ",";
    out << "\"seeding\":" << (status.is_seeding ? "true" : "false") << ",";
    out << "\"paused\":" << (has_flag(status.flags, lt::torrent_flags::paused) ? "true" : "false") << ",";
    out << "\"sequential\":" << (has_flag(status.flags, lt::torrent_flags::sequential_download) ? "true" : "false") << ",";
    out << "\"has_metadata\":" << (status.has_metadata ? "true" : "false") << ",";
    out << "\"save_path\":\"" << json_escape(status.save_path) << "\",";
    out << "\"ratio\":" << std::fixed << std::setprecision(3) << ratio << ",";
    out << "\"added\":" << static_cast<long long>(status.added_time) << ",";
    std::string error_message;
    if (status.errc)
        error_message = status.errc.message();
    out << "\"error\":\"" << json_escape(error_message) << "\"";
    out << "}";
}

} // namespace

extern "C" {

vt_session* vt_session_create_full(const char* download_dir,
                                   const char* resume_dir,
                                   int listen_port,
                                   int download_limit_bytes,
                                   int upload_limit_bytes,
                                   int enable_dht,
                                   int enable_pex,
                                   int enable_lsd,
                                   int enable_upnp,
                                   const char* bind_address,
                                   char** error_message)
{
    if (error_message)
        *error_message = nullptr;

    try
    {
        auto session = std::make_unique<vt_session>();
        session->default_save_path = download_dir ? download_dir : "";
        session->resume_dir = resume_dir ? resume_dir : "";
        session->listen_port = listen_port > 0 ? listen_port : 6881;
        session->bind_address = bind_address ? bind_address : "";
        session->upnp_enabled = enable_upnp != 0;

        auto ensure_directory = [&](std::string const& path) {
            std::error_code ec;
            fs::create_directories(path, ec);
            if (ec)
            {
                if (error_message)
                    *error_message = ::strdup((path + ": " + ec.message()).c_str());
                return false;
            }
            return true;
        };

        if (!session->default_save_path.empty()
            && !ensure_directory(session->default_save_path))
            return nullptr;
        if (!session->resume_dir.empty()
            && !ensure_directory(session->resume_dir))
            return nullptr;

        lt::settings_pack settings;
        settings.set_str(lt::settings_pack::user_agent, "Vertex/1.0 libtorrent/" LIBTORRENT_VERSION);
        settings.set_str(lt::settings_pack::peer_fingerprint, "-VT1000-");
        settings.set_int(lt::settings_pack::alert_mask,
                         int(static_cast<std::uint32_t>(lt::alert_category::error |
                                                        lt::alert_category::storage |
                                                        lt::alert_category::status |
                                                        lt::alert_category::port_mapping)));
        settings.set_str(lt::settings_pack::listen_interfaces,
                         listen_interfaces_setting(session->listen_port, session->bind_address));
        if (!session->bind_address.empty())
        {
            settings.set_str(lt::settings_pack::outgoing_interfaces, session->bind_address);
        }
        apply_link_settings(settings, download_limit_bytes, upload_limit_bytes,
                            enable_dht, enable_upnp, enable_lsd);
        settings.set_str(lt::settings_pack::dht_bootstrap_nodes,
                         "router.bittorrent.com:6881,dht.libtorrent.org:25401,"
                         "dht.transmissionbt.com:6881,router.utorrent.com:6881");
        settings.set_int(lt::settings_pack::connections_limit, 400);
        settings.set_int(lt::settings_pack::active_limit, 100);
        settings.set_int(lt::settings_pack::alert_queue_size, 1000);
        settings.set_int(lt::settings_pack::stop_tracker_timeout, 1);
        settings.set_bool(lt::settings_pack::announce_to_all_tiers, true);
        settings.set_bool(lt::settings_pack::announce_to_all_trackers, true);

        // Do not use the implicit default plugin list: ut_pex must be
        // controllable per session. ut_metadata is required for magnet links
        // and smart_ban keeps corrupt peers out.
        lt::session_params params(std::move(settings), {});
        session->session = std::make_unique<lt::session>(std::move(params));
        session->session->add_extension(&lt::create_ut_metadata_plugin);
        session->session->add_extension(&lt::create_smart_ban_plugin);
        if (enable_pex != 0)
            session->session->add_extension(&lt::create_ut_pex_plugin);
        session->dht_metric_index = lt::find_metric_idx("dht.dht_nodes");
        session->last_stats = std::chrono::steady_clock::now();
        session->last_resume_save = std::chrono::steady_clock::now();

        if (!session->resume_dir.empty())
        {
            std::error_code ec;
            for (auto const& entry : fs::directory_iterator(session->resume_dir, ec))
            {
                if (ec)
                    break;
                if (!entry.is_regular_file() || entry.path().extension() != ".resume")
                    continue;

                try
                {
                    std::ifstream file(entry.path(), std::ios::binary);
                    std::vector<char> data((std::istreambuf_iterator<char>(file)),
                                           std::istreambuf_iterator<char>());
                    if (data.empty())
                        continue;

                    lt::error_code resume_ec;
                    auto params = lt::read_resume_data(
                        lt::span<char const>(data.data(), int(data.size())), resume_ec);
                    if (resume_ec)
                        continue;

                    params.save_path = prepared_save_path(params.save_path, session->default_save_path);
                    params.flags &= ~lt::torrent_flags::auto_managed;
                    lt::error_code add_ec;
                    session->session->add_torrent(std::move(params), add_ec);
                }
                catch (...)
                {
                }
            }
        }

        return session.release();
    }
    catch (std::exception const& e)
    {
        if (error_message)
            *error_message = ::strdup(e.what());
        return nullptr;
    }
    catch (...)
    {
        if (error_message)
            *error_message = ::strdup("Errore sconosciuto");
        return nullptr;
    }
}

void vt_session_destroy(vt_session* session)
{
    if (!session)
        return;

    try
    {
        // Only wait for resume data of torrents that are still in the session
        // and either need saving or do not yet have a resume file on disk.
        // Stale alerts from removed torrents must neither recreate their files
        // nor decrement the pending counter.
        std::set<std::string> requested_ids;
        for (auto const& handle : session->session->get_torrents())
        {
            try
            {
                if (!handle.is_valid())
                    continue;

                auto id = to_hex(handle.info_hashes().get_best());
                if (id.empty() || is_removed(session, id))
                    continue;

                bool resume_exists = false;
                if (!session->resume_dir.empty())
                {
                    std::error_code ec;
                    resume_exists = fs::is_regular_file(
                        fs::path(session->resume_dir) / (id + ".resume"), ec);
                }
                if (!handle.need_save_resume_data() && resume_exists)
                    continue;

                handle.save_resume_data(lt::torrent_handle::save_info_dict);
                requested_ids.insert(id);
            }
            catch (...)
            {
            }
        }

        int pending = int(requested_ids.size());
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
        while (pending > 0)
        {
            auto now = std::chrono::steady_clock::now();
            if (now >= deadline)
                break;

            std::vector<lt::alert*> alerts;
            session->session->pop_alerts(&alerts);
            if (alerts.empty())
            {
                auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
                session->session->wait_for_alert(
                    (std::min)(remaining, std::chrono::milliseconds(50)));
                session->session->pop_alerts(&alerts);
            }

            for (auto* alert : alerts)
            {
                if (auto* saved = lt::alert_cast<lt::save_resume_data_alert>(alert))
                {
                    auto const id = to_hex(saved->params.info_hashes.get_best());
                    if (requested_ids.erase(id) == 0)
                        continue;

                    if (!is_removed(session, id) && saved->handle.is_valid())
                        write_resume_impl(session->resume_dir, saved->params);
                    --pending;
                }
                else if (auto* failed = lt::alert_cast<lt::save_resume_data_failed_alert>(alert))
                {
                    bool identified = false;
                    bool matched = false;
                    try
                    {
                        if (failed->handle.is_valid())
                        {
                            auto const id = to_hex(failed->handle.info_hashes().get_best());
                            if (!id.empty())
                            {
                                identified = true;
                                if (requested_ids.erase(id) > 0)
                                {
                                    --pending;
                                    matched = true;
                                }
                            }
                        }
                    }
                    catch (...)
                    {
                    }

                    if (!matched && !identified)
                    {
                        try
                        {
                            auto id = torrent_id(
                                failed->handle.status(lt::status_flags_t{}));
                            if (!id.empty())
                            {
                                identified = true;
                                if (requested_ids.erase(id) > 0)
                                {
                                    --pending;
                                    matched = true;
                                }
                            }
                        }
                        catch (...)
                        {
                        }
                    }

                    // A valid handle whose id is not in requested_ids is a
                    // stale alert: it must not release a slot for another
                    // torrent. Only unknown/invalid handles are forgiven.
                    if (!matched && !identified && pending > 0)
                    {
                        --pending;
                    }
                }
            }
        }
    }
    catch (...)
    {
    }

    delete session;
}

void vt_session_poll(vt_session* session)
{
    if (!session || !session->session)
        return;

    try
    {
        auto now = std::chrono::steady_clock::now();

        if (now - session->last_stats > std::chrono::milliseconds(1500))
        {
            session->session->post_session_stats();
            session->last_stats = now;
        }

        if (now - session->last_resume_save > std::chrono::seconds(20))
        {
            for (auto const& handle : session->session->get_torrents())
            {
                try
                {
                    if (handle.need_save_resume_data())
                        handle.save_resume_data(lt::torrent_handle::save_info_dict);
                }
                catch (...)
                {
                }
            }
            session->last_resume_save = now;
        }

        std::vector<lt::alert*> alerts;
        session->session->pop_alerts(&alerts);
        for (auto* alert : alerts)
        {
            if (auto* saved = lt::alert_cast<lt::save_resume_data_alert>(alert))
            {
                auto const id = to_hex(saved->params.info_hashes.get_best());
                if (!is_removed(session, id) && saved->handle.is_valid())
                    write_resume_impl(session->resume_dir, saved->params);
            }
            else if (auto* stats = lt::alert_cast<lt::session_stats_alert>(alert))
            {
                auto counters = stats->counters();
                if (session->dht_metric_index >= 0 &&
                    session->dht_metric_index < int(counters.size()))
                {
                    session->dht_nodes = int(counters[session->dht_metric_index]);
                }
            }
            else if (auto* listen_failed = lt::alert_cast<lt::listen_failed_alert>(alert))
            {
                // Only meaningful when the session is pinned to an address: with
                // the default 0.0.0.0/[::] pair a missing IPv6 stack would
                // report a failure the user cannot act on.
                if (!session->bind_address.empty())
                    session->listen_error = listen_failed->message();
            }
            else if (lt::alert_cast<lt::listen_succeeded_alert>(alert))
            {
                session->listen_error.clear();
            }
            else if (auto* mapped = lt::alert_cast<lt::portmap_alert>(alert))
            {
                std::string transport = portmap_transport_string(mapped->map_transport);
                if (mapped->map_protocol == lt::portmap_protocol::tcp)
                {
                    session->tcp.mark_mapped(mapped->external_port, transport, mapped->mapping);
                }
                else if (mapped->map_protocol == lt::portmap_protocol::udp)
                {
                    session->udp.mark_mapped(mapped->external_port, transport, mapped->mapping);
                }
            }
            else if (auto* map_error = lt::alert_cast<lt::portmap_error_alert>(alert))
            {
                // portmap_error_alert does not carry the TCP/UDP protocol. Mapping indices
                // are per transport (UPnP and NAT-PMP both start at 0), so match both the
                // index and the transport recorded from the successful portmap_alert.
                std::string const transport = portmap_transport_string(map_error->map_transport);
                std::string const message = transport + ": " + map_error->error.message();
                bool attributed = false;
                if (session->tcp.mapped && map_error->mapping == session->tcp.mapping
                    && transport == session->tcp.transport)
                {
                    session->tcp.mark_failed(message);
                    attributed = true;
                }
                if (session->udp.mapped && map_error->mapping == session->udp.mapping
                    && transport == session->udp.transport)
                {
                    session->udp.mark_failed(message);
                    attributed = true;
                }
                if (!attributed)
                {
                    // libtorrent registers the TCP mapping before the UDP one for
                    // each port mapper, so slots 0 and 1 identify them even when
                    // the first attempt fails before any portmap_alert arrives.
                    int const slot = static_cast<int>(map_error->mapping);
                    if (slot == 0)
                        session->tcp.mark_failed(message);
                    else if (slot == 1)
                        session->udp.mark_failed(message);
                    else
                        session->portmap_error = message;
                }
            }
            else if (auto* added = lt::alert_cast<lt::add_torrent_alert>(alert))
            {
                if (added->error)
                    session->last_alert_error = added->error.message();
            }
            else if (auto* error = lt::alert_cast<lt::torrent_error_alert>(alert))
            {
                session->last_alert_error = error->error.message();
            }
            else if (auto* socks = lt::alert_cast<lt::socks5_alert>(alert))
            {
                if (socks->error)
                    session->proxy_error = socks->error.message();
            }
            else if (auto* peer_conn = lt::alert_cast<lt::peer_connect_alert>(alert))
            {
                // If a peer connection succeeded over proxy, clear previous proxy error
                if (session->proxy_type != 0 && !session->proxy_error.empty())
                    session->proxy_error.clear();
            }
        }
    }
    catch (...)
    {
    }
}

char* vt_snapshot_json(vt_session* session)
{
    if (!session || !session->session)
        return nullptr;

    try
    {
        std::ostringstream out;
        out.imbue(std::locale::classic());

        std::string alert_error = session->last_alert_error;
        session->last_alert_error.clear();

        std::int64_t download_rate = 0;
        std::int64_t upload_rate = 0;
        int active = 0;
        int paused = 0;

        out << "{\"torrents\":[";
        bool first = true;
        for (auto const& handle : session->session->get_torrents())
        {
            try
            {
                // Only the fields used below: skip pieces and verified pieces, but keep
                // accurate counters so progress/ETA don't jump by whole pieces.
                auto status = handle.status(lt::torrent_handle::query_name
                                            | lt::torrent_handle::query_save_path
                                            | lt::torrent_handle::query_accurate_download_counters);
                download_rate += status.download_payload_rate;
                upload_rate += status.upload_payload_rate;
                bool is_paused = has_flag(status.flags, lt::torrent_flags::paused);
                if (is_paused)
                    ++paused;
                else
                    ++active;

                if (!first)
                    out << ",";
                first = false;
                append_torrent_json(out, status);
            }
            catch (...)
            {
            }
        }
        out << "],";
        out << "\"download_rate\":" << download_rate << ",";
        out << "\"upload_rate\":" << upload_rate << ",";
        out << "\"active\":" << active << ",";
        out << "\"paused_count\":" << paused << ",";
        out << "\"dht_nodes\":" << session->dht_nodes << ",";
        out << "\"alert_error\":\"" << json_escape(alert_error) << "\",";

        try
        {
            session->actual_listen_port = int(session->session->listen_port());
            session->listening = session->session->is_listening();
        }
        catch (...)
        {
            session->actual_listen_port = 0;
            session->listening = false;
        }

        out << "\"listen_actual_port\":" << session->actual_listen_port << ",";
        out << "\"listening\":" << (session->listening ? "true" : "false") << ",";
        out << "\"bind_address\":\"" << json_escape(session->bind_address) << "\",";
        out << "\"listen_error\":\"" << json_escape(session->listen_error) << "\",";
        out << "\"proxy\":{";
        out << "\"enabled\":" << (session->proxy_type != 0 ? "true" : "false") << ",";
        out << "\"type\":\"" << (session->proxy_type == 1 ? "SOCKS5" : "None") << "\",";
        out << "\"hostname\":\"" << json_escape(session->proxy_host) << "\",";
        out << "\"port\":" << session->proxy_port << ",";
        out << "\"auth\":" << (session->proxy_auth ? "true" : "false") << ",";
        out << "\"error\":\"" << json_escape(session->proxy_error) << "\"";
        out << "},";
        out << "\"portmap\":{";
        out << "\"tcp\":{\"mapped\":" << (session->tcp.mapped ? "true" : "false")
            << ",\"external_port\":" << session->tcp.external_port
            << ",\"transport\":\"" << json_escape(session->tcp.transport)
            << "\",\"error\":\"" << json_escape(session->tcp.error) << "\"},";
        out << "\"udp\":{\"mapped\":" << (session->udp.mapped ? "true" : "false")
            << ",\"external_port\":" << session->udp.external_port
            << ",\"transport\":\"" << json_escape(session->udp.transport)
            << "\",\"error\":\"" << json_escape(session->udp.error) << "\"},";
        out << "\"error\":\"" << json_escape(session->portmap_error) << "\"},";
        out << "\"port\":" << session->listen_port;
        out << "}";

        auto text = out.str();
        return ::strdup(text.c_str());
    }
    catch (...)
    {
        return nullptr;
    }
}

char* vt_detail_json(vt_session* session, const char* torrent_id_value)
{
    if (!session || !torrent_id_value)
        return nullptr;

    try
    {
        std::string id(torrent_id_value);
        auto handle = find_handle(session, id);
        std::ostringstream out;
        out.imbue(std::locale::classic());

        out << "{\"files\":[";
        bool has_metadata = false;
        if (handle.is_valid())
        {
            auto info = handle.torrent_file();
            if (info)
            {
                has_metadata = true;
                // Piece granularity is much cheaper for libtorrent: it counts
                // only hash-checked pieces instead of computing per-block
                // progress on every inspector refresh.
                auto progress = handle.file_progress(lt::torrent_handle::piece_granularity);
                auto priorities = handle.get_file_priorities();
                auto const& storage = info->layout();
                bool first = true;
                for (int i = 0; i < storage.num_files(); ++i)
                {
                    auto index = lt::file_index_t(i);
                    std::int64_t size = storage.file_size(index);
                    std::int64_t done = i < int(progress.size()) ? progress[std::size_t(i)] : 0;
                    double fraction = size > 0 ? double(done) / double(size) : 0.0;
                    int priority = i < int(priorities.size())
                                       ? int(static_cast<std::uint8_t>(priorities[std::size_t(i)]))
                                       : 4;

                    if (!first)
                        out << ",";
                    first = false;
                    out << "{";
                    out << "\"index\":" << i << ",";
                    out << "\"path\":\"" << json_escape(storage.file_path(index)) << "\",";
                    out << "\"size\":" << size << ",";
                    out << "\"progress\":" << std::fixed << std::setprecision(4) << fraction << ",";
                    out << "\"priority\":" << priority;
                    out << "}";
                }
            }
        }
        out << "],\"trackers\":[";

        if (handle.is_valid())
        {
            auto trackers = handle.trackers();
            auto const hashes = handle.info_hashes();
            auto const has_scrape = [](lt::announce_infohash const& info) {
                return info.scrape_complete >= 0 || info.scrape_incomplete >= 0;
            };
            auto const has_stats = [&](lt::announce_infohash const& info) {
                return has_scrape(info) || !info.message.empty() || info.fails > 0;
            };
            bool first = true;
            for (auto const& tracker : trackers)
            {
                std::string message;
                int fails = 0;
                int peers = -1;
                int seeds = -1;
                if (!tracker.endpoints.empty())
                {
                    auto const& endpoint = tracker.endpoints.front();
                    auto const& v1 = endpoint.info_hashes[lt::protocol_version::V1];
                    auto const& v2 = endpoint.info_hashes[lt::protocol_version::V2];
                    auto const* infohash = &v1;
                    if (!hashes.has_v1())
                        infohash = &v2;
                    else if (hashes.has_v2() && !has_scrape(v1) && has_scrape(v2))
                        infohash = &v2;
                    else if (hashes.has_v2() && !has_stats(v1) && has_stats(v2))
                        infohash = &v2;
                    message = infohash->message;
                    fails = infohash->fails;
                    peers = infohash->scrape_incomplete;
                    seeds = infohash->scrape_complete;
                }

                if (!first)
                    out << ",";
                first = false;
                out << "{";
                out << "\"url\":\"" << json_escape(tracker.url) << "\",";
                out << "\"verified\":" << (tracker.verified ? "true" : "false") << ",";
                out << "\"fails\":" << fails << ",";
                out << "\"message\":\"" << json_escape(message) << "\",";
                out << "\"peers\":" << peers << ",";
                out << "\"seeds\":" << seeds;
                out << "}";
            }
        }

        out << "],\"metadata\":" << (has_metadata ? "true" : "false");
        out << "}";

        auto text = out.str();
        return ::strdup(text.c_str());
    }
    catch (...)
    {
        return nullptr;
    }
}

char* vt_last_error(vt_session* session)
{
    if (!session)
        return nullptr;
    auto text = session->last_error;
    session->last_error.clear();
    return ::strdup(text.c_str());
}

char* vt_magnet_uri(vt_session* session, const char* torrent_id_value)
{
    if (!session || !torrent_id_value)
        return nullptr;

    try
    {
        auto handle = find_handle(session, torrent_id_value);
        if (!handle.is_valid())
            return ::strdup("");

        // Build only the fields a magnet link needs instead of serializing the
        // whole resume data. The torrent_handle overload of make_magnet_uri is
        // deprecated in libtorrent 2.1.
        lt::add_torrent_params params;
        params.info_hashes = handle.info_hashes();
        try
        {
            params.name = handle.status(lt::torrent_handle::query_name).name;
        }
        catch (...)
        {
        }
        try
        {
            for (auto const& tracker : handle.trackers())
                params.trackers.push_back(tracker.url);
        }
        catch (...)
        {
        }

        auto uri = lt::make_magnet_uri(params);
        return ::strdup(uri.c_str());
    }
    VT_CATCH_ALL(session, ::strdup(""))
}

int vt_add_magnet(vt_session* session,
                  const char* uri,
                  const char* save_path,
                  int paused,
                  int sequential)
{
    if (!session || !uri)
        return -1;

    // MEDIUM #5: reject magnet URIs larger than 8 KiB before handing to libtorrent
    constexpr std::size_t MAX_MAGNET_URI = 8 * 1024;
    std::size_t uri_len = std::strlen(uri);
    if (uri_len > MAX_MAGNET_URI)
    {
        session->last_error = "Magnet URI exceeds maximum size";
        return -1;
    }

    try
    {
        lt::error_code ec;
        auto params = lt::parse_magnet_uri(lt::string_view(uri), ec);
        if (ec)
        {
            session->last_error = ec.message();
            return -1;
        }

        return add_torrent_common(session, params, save_path, paused, sequential);
    }
    VT_CATCH_ALL(session, -1)
}

int vt_add_torrent_file(vt_session* session,
                        const char* path,
                        const char* save_path,
                        int paused,
                        int sequential)
{
    if (!session || !path)
        return -1;

    // MEDIUM #6: validate torrent file path before loading
    // - canonicalize
    // - must be a regular file
    // - reject if > 10 MiB
    std::string canonical_path;
    try
    {
        fs::path canonical = fs::canonical(fs::path(path));
        std::error_code ec_fs;
        if (!fs::is_regular_file(canonical, ec_fs))
        {
            session->last_error = "Torrent path is not a regular file";
            return -1;
        }
        auto file_size = fs::file_size(canonical, ec_fs);
        if (ec_fs)
        {
            session->last_error = "Cannot stat torrent file";
            return -1;
        }
        constexpr std::uintmax_t MAX_TORRENT_FILE = 10 * 1024 * 1024; // 10 MiB
        if (file_size > MAX_TORRENT_FILE)
        {
            session->last_error = "Torrent file exceeds maximum size";
            return -1;
        }
        canonical_path = canonical.string();
        path = canonical_path.c_str();
    }
    catch (std::exception const& e)
    {
        session->last_error = std::string("Invalid torrent path: ") + e.what();
        return -1;
    }

    try
    {
        lt::error_code ec;
        auto params = lt::load_torrent_file(path, ec, lt::load_torrent_limits{});
        if (ec)
        {
            session->last_error = ec.message();
            return -1;
        }

        return add_torrent_common(session, params, save_path, paused, sequential);
    }
    VT_CATCH_ALL(session, -1)
}

int vt_add_peer(vt_session* session,
                const char* torrent_id_value,
                const char* host,
                int port)
{
    if (!session || !torrent_id_value || !host || port <= 0 || port > 65535)
        return -1;

    try
    {
        auto handle = find_handle(session, torrent_id_value);
        if (!handle.is_valid())
        {
            session->last_error = "Torrent non trovato";
            return -1;
        }

        lt::error_code ec;
        auto address = lt::make_address(host, ec);
        if (ec)
        {
            session->last_error = ec.message();
            return -1;
        }

        handle.connect_peer(lt::tcp::endpoint(
            address, static_cast<unsigned short>(port)));
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

namespace {

/// Commands accepted by `vt_control`. The enum is the allowlist: the string
/// coming from the Swift layer is mapped to it once, and the switch below
/// exhaustively covers every value. Adding a new command means adding one
/// enum value and one case — there is no string to keep in sync, and no
/// unvalidated input can reach a libtorrent call.
enum class ControlAction {
    pause,
    resume,
    reannounce,
    sequentialOn,
    sequentialOff,
    remove,
    removeFiles,
    unknown,
};

ControlAction parse_control_action(std::string const& action)
{
    if (action == "pause")         return ControlAction::pause;
    if (action == "resume")        return ControlAction::resume;
    if (action == "reannounce")    return ControlAction::reannounce;
    if (action == "sequential_on") return ControlAction::sequentialOn;
    if (action == "sequential_off")return ControlAction::sequentialOff;
    if (action == "remove")        return ControlAction::remove;
    if (action == "remove_files")  return ControlAction::removeFiles;
    return ControlAction::unknown;
}

} // namespace

int vt_control(vt_session* session, const char* torrent_id_value, const char* action)
{
    if (!session || !torrent_id_value || !action)
        return -1;

    try
    {
        auto handle = find_handle(session, torrent_id_value);
        if (!handle.is_valid())
        {
            session->last_error = "Torrent non trovato";
            return -1;
        }

        ControlAction const command = parse_control_action(action);

        switch (command)
        {
        case ControlAction::pause:
            handle.pause();
            break;

        case ControlAction::resume:
            // A torrent stopped by an error stays stopped until the error is cleared.
            if (handle.status(lt::status_flags_t{}).errc)
                handle.clear_error();
            handle.resume();
            break;

        case ControlAction::reannounce:
            handle.force_reannounce();
            break;

        case ControlAction::sequentialOn:
            handle.set_flags(lt::torrent_flags::sequential_download);
            break;

        case ControlAction::sequentialOff:
            handle.unset_flags(lt::torrent_flags::sequential_download);
            break;

        case ControlAction::remove:
        case ControlAction::removeFiles:
            mark_removed(session, torrent_id_value);
            if (command == ControlAction::removeFiles)
                session->session->remove_torrent(handle, lt::session::delete_files);
            else
                session->session->remove_torrent(handle);
            if (!session->resume_dir.empty())
            {
                std::error_code ec;
                fs::remove(fs::path(session->resume_dir) / (std::string(torrent_id_value) + ".resume"),
                           ec);
            }
            break;

        case ControlAction::unknown:
            session->last_error = "Comando non supportato";
            return -1;
        }

        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_set_file_priority(vt_session* session, const char* torrent_id_value, int file_index, int priority)
{
    if (!session)
        return -1;
    if (!torrent_id_value || file_index < 0 || priority < 0 || priority > 7)
    {
        session->last_error = "Parametri non validi";
        return -1;
    }

    try
    {
        auto handle = find_handle(session, torrent_id_value);
        if (!handle.is_valid())
        {
            session->last_error = "Torrent non trovato";
            return -1;
        }
        handle.file_priority(lt::file_index_t(file_index),
                             lt::download_priority_t(std::uint8_t(priority)));
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_set_all_file_priorities(vt_session* session, const char* torrent_id_value, int priority)
{
    if (!session)
        return -1;
    if (!torrent_id_value || priority < 0 || priority > 7)
    {
        session->last_error = "Parametri non validi";
        return -1;
    }

    try
    {
        auto handle = find_handle(session, torrent_id_value);
        if (!handle.is_valid())
        {
            session->last_error = "Torrent non trovato";
            return -1;
        }
        auto info = handle.torrent_file();
        if (!info)
        {
            session->last_error = "Metadati non disponibili";
            return -1;
        }
        int const count = info->layout().num_files();
        std::vector<lt::download_priority_t> priorities(
            std::size_t((std::max)(0, count)),
            lt::download_priority_t(std::uint8_t(priority)));
        handle.prioritize_files(priorities);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_apply_settings_ex(vt_session* session,
                         int listen_port,
                         int download_limit_bytes,
                         int upload_limit_bytes,
                         int enable_dht,
                         int enable_upnp,
                         int enable_lsd,
                         const char* bind_address)
{
    if (!session || !session->session)
        return -1;

    try
    {
        lt::settings_pack settings;
        std::string const requested_bind = bind_address ? bind_address : "";
        bool const port_changed = listen_port > 0 && listen_port != session->listen_port;
        if (port_changed || requested_bind != session->bind_address)
        {
            if (listen_port > 0)
                session->listen_port = listen_port;
            session->bind_address = requested_bind;
            // A port mapping belongs to the address that requested it.
            reset_portmap_state(session);
            session->listen_error.clear();
            settings.set_str(lt::settings_pack::listen_interfaces,
                             listen_interfaces_setting(session->listen_port,
                                                       session->bind_address));
            settings.set_str(lt::settings_pack::outgoing_interfaces,
                             session->bind_address);
        }
        if ((enable_upnp != 0) != session->upnp_enabled)
        {
            session->upnp_enabled = enable_upnp != 0;
            reset_portmap_state(session);
        }
        bool const effective_upnp = (enable_upnp != 0) && (session->proxy_type == 0);
        apply_link_settings(settings, download_limit_bytes, upload_limit_bytes,
                            enable_dht, effective_upnp ? 1 : 0, enable_lsd);
        session->session->apply_settings(settings);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_apply_proxy_settings(vt_session* session,
                            int proxy_type,
                            const char* hostname,
                            int port,
                            const char* username,
                            const char* password)
{
    if (!session || !session->session)
        return -1;

    try
    {
        lt::settings_pack settings;
        if (proxy_type == 1 && hostname && *hostname)
        {
            session->proxy_type = 1;
            session->proxy_host = hostname;
            session->proxy_port = port > 0 ? port : 1080;
            session->proxy_error.clear();

            // libtorrent offers username/password authentication only when the
            // proxy type is socks5_pw AND the username is non-empty
            // (socks5_stream.hpp sends the no-auth method when m_user is empty).
            // A password without a username therefore cannot authenticate.
            session->proxy_auth = username && *username;
            settings.set_int(lt::settings_pack::proxy_type,
                             session->proxy_auth ? lt::settings_pack::socks5_pw
                                                 : lt::settings_pack::socks5);
            settings.set_str(lt::settings_pack::proxy_hostname, session->proxy_host);
            settings.set_int(lt::settings_pack::proxy_port, session->proxy_port);

            if (username && *username)
                settings.set_str(lt::settings_pack::proxy_username, username);
            else
                settings.set_str(lt::settings_pack::proxy_username, "");

            if (password && *password)
                settings.set_str(lt::settings_pack::proxy_password, password);
            else
                settings.set_str(lt::settings_pack::proxy_password, "");

            // Leak prevention: all tracker and peer traffic routed through SOCKS5 proxy
            settings.set_bool(lt::settings_pack::proxy_tracker_connections, true);
            settings.set_bool(lt::settings_pack::proxy_peer_connections, true);
            settings.set_bool(lt::settings_pack::proxy_hostnames, true);

            // Enforce strict anonymous mode: if the proxy fails, connections are never
            // fallen back to the clearnet adapter and active connections drop.
            settings.set_bool(lt::settings_pack::anonymous_mode, true);

            // With SOCKS5 active, router UPnP/NAT-PMP mapping is disabled
            settings.set_bool(lt::settings_pack::enable_upnp, false);
            settings.set_bool(lt::settings_pack::enable_natpmp, false);
            reset_portmap_state(session);
        }
        else
        {
            session->proxy_type = 0;
            session->proxy_auth = false;
            session->proxy_host.clear();
            session->proxy_port = 0;
            session->proxy_error.clear();

            settings.set_int(lt::settings_pack::proxy_type, lt::settings_pack::none);
            settings.set_str(lt::settings_pack::proxy_hostname, "");
            settings.set_str(lt::settings_pack::proxy_username, "");
            settings.set_str(lt::settings_pack::proxy_password, "");
            settings.set_bool(lt::settings_pack::anonymous_mode, false);

            // Restore UPnP / NAT-PMP setting according to session preference
            settings.set_bool(lt::settings_pack::enable_upnp, session->upnp_enabled);
            settings.set_bool(lt::settings_pack::enable_natpmp, session->upnp_enabled);
            reset_portmap_state(session);
        }

        session->session->apply_settings(settings);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

void vt_clear_proxy_error(vt_session* session)
{
    if (session)
        session->proxy_error.clear();
}

char* vt_normalize_save_path(const char* requested, const char* fallback)
{
    try
    {
        auto value = normalized_save_path(
            requested ? requested : "",
            fallback ? fallback : "");
        return ::strdup(value.c_str());
    }
    catch (...)
    {
        return nullptr;
    }
}

int vt_set_default_save_path(vt_session* session, const char* path)
{
    if (!session || !path || !*path)
        return -1;

    try
    {
        fs::path target(path);
        std::error_code ec;
        fs::create_directories(target, ec);
        if (ec)
        {
            session->last_error = ec.message();
            return -1;
        }
        if (!fs::is_directory(target, ec) || ec)
        {
            session->last_error = "La destinazione non è una cartella.";
            return -1;
        }
        if (::access(target.c_str(), W_OK) != 0)
        {
            session->last_error = "La cartella di destinazione non è scrivibile.";
            return -1;
        }
        session->default_save_path = target.string();
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

char* vt_json_escape(const char* input)
{
    if (!input)
        return ::strdup("");
    try
    {
        auto escaped = json_escape(std::string(input));
        return ::strdup(escaped.c_str());
    }
    catch (...)
    {
        return ::strdup("");
    }
}

int vt_is_valid_utf8(const char* input)
{
    if (!input)
        return 0;
    return is_valid_utf8(std::string(input)) ? 1 : 0;
}

void vt_free_string(char* value)
{
    std::free(value);
}

} // extern "C"
