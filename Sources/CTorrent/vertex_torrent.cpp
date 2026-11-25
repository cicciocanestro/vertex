#include "vertex_torrent.h"
#include "vertex_strings.hpp"

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/address.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/peer_info.hpp>
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

using vertex::is_valid_utf8;
using vertex::json_escape;
using vertex::normalized_save_path;

#include <algorithm>
#include <arpa/inet.h>
#include <chrono>
#include <cstdio>
#include <exception>
#include <cstdlib>
#include <fcntl.h>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <ifaddrs.h>
#include <iomanip>
#include <locale>
#include <memory>
#include <mutex>
#include <net/if.h>
#include <set>
#include <string_view>
#include <sys/stat.h>
#include <unordered_set>
#include <sstream>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

// Same error contract for the public operations: report the exception through
// last_error and return the bridge's failure value without letting a secondary
// allocation failure escape across extern "C".
#define VT_CATCH_ALL(session_ptr, fallback)                                      \
    catch (std::exception const& e)                                             \
    {                                                                           \
        try                                                                     \
        {                                                                       \
            (session_ptr)->last_error = e.what();                               \
        }                                                                       \
        catch (...)                                                             \
        {                                                                       \
            (session_ptr)->last_error.clear();                                  \
        }                                                                       \
        return fallback;                                                        \
    }                                                                           \
    catch (...)                                                                 \
    {                                                                           \
        try                                                                     \
        {                                                                       \
            (session_ptr)->last_error = "Errore sconosciuto";                   \
        }                                                                       \
        catch (...)                                                             \
        {                                                                       \
            (session_ptr)->last_error.clear();                                  \
        }                                                                       \
        return fallback;                                                        \
    }

namespace {

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

bool is_usable_directory(std::string const& path)
{
    namespace fs = std::filesystem;
    std::error_code ec;
    fs::create_directories(path, ec);
    return !ec && fs::is_directory(path, ec) && !ec && ::access(path.c_str(), W_OK | X_OK) == 0;
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

// Validates and canonicalizes an optional bind_address. Empty means all
// interfaces; bracketed IPv6 literals ("[::1]") are unwrapped so
// listen_interfaces_setting never produces "[[::1]]:port", and device names
// or malformed strings are rejected.
bool normalize_bind_address_c(const char* raw, std::string& out)
{
    out.clear();
    if (!raw || !*raw)
        return true;

    std::string candidate(raw);
    auto const first = candidate.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
        return true;
    auto const last = candidate.find_last_not_of(" \t\r\n");
    candidate = candidate.substr(first, last - first + 1);
    if (candidate.size() >= 2 && candidate.front() == '[' && candidate.back() == ']')
        candidate = candidate.substr(1, candidate.size() - 2);

    lt::error_code ec;
    auto const parsed = lt::make_address(candidate, ec);
    if (ec)
        return false;
    out = parsed.to_string();
    return true;
}

bool is_local_address_present(std::string const& bind_address)
{
    if (bind_address.empty())
        return true;

    lt::error_code ec;
    auto const target = lt::make_address(bind_address, ec);
    if (ec)
        return false;

    ifaddrs* head = nullptr;
    if (::getifaddrs(&head) != 0 || !head)
        return false;

    bool found = false;
    for (ifaddrs* cur = head; cur != nullptr; cur = cur->ifa_next)
    {
        if (!cur->ifa_addr || (cur->ifa_flags & IFF_UP) == 0)
            continue;
        if (cur->ifa_addr->sa_family == AF_INET && target.is_v4())
        {
            auto const* sin = reinterpret_cast<sockaddr_in const*>(cur->ifa_addr);
            lt::address_v4::bytes_type bytes{};
            std::memcpy(bytes.data(), &sin->sin_addr, bytes.size());
            if (lt::address_v4(bytes) == target.to_v4())
            {
                found = true;
                break;
            }
        }
        else if (cur->ifa_addr->sa_family == AF_INET6 && target.is_v6())
        {
            auto const* sin6 = reinterpret_cast<sockaddr_in6 const*>(cur->ifa_addr);
            lt::address_v6::bytes_type bytes{};
            std::memcpy(bytes.data(), &sin6->sin6_addr, bytes.size());
            if (lt::address_v6(bytes) == target.to_v6())
            {
                found = true;
                break;
            }
        }
    }
    ::freeifaddrs(head);
    return found;
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
    // Asynchronous add_torrent/torrent_error/storage alerts, surfaced once by
    // the snapshot. A queue, not a single slot: with several torrents failing
    // between two polls, a single string silently lost all but one message.
    static constexpr std::size_t max_alert_errors = 8;
    std::deque<std::string> alert_errors;
    int actual_listen_port = 0;
    bool listening = false;
    bool dht_enabled = true;
    bool upnp_enabled = true;
    // True when both bind_address and SOCKS5 are active and bind_address is not
    // present on any UP local interface: libtorrent's use_proxy listener binds
    // 0.0.0.0, so the bridge pauses the session itself to stay fail-closed.
    bool bound_interface_down = false;
    portmap_state tcp;
    portmap_state udp;
    // Error whose TCP/UDP protocol could not be determined from the alert.
    std::string portmap_error;
    // Proxy configuration state
    // Configured active-torrent limit (0 = unlimited), mirrored in the snapshot.
    int max_active = 0;
    int proxy_type = 0; // 0 = none, 1 = socks5
    // True when a username is configured: libtorrent only performs RFC 1929
    // authentication with the socks5_pw proxy type and a non-empty username.
    bool proxy_auth = false;
    std::string proxy_host;
    int proxy_port = 1080;
    std::string proxy_user;
    std::string proxy_password;
    std::string proxy_error;
    // Ids of torrents removed by the user: late resume-data alerts must not recreate their files.
    // Bounded FIFO: such alerts only arrive shortly after the removal. The set
    // mirrors the deque so membership tests stay O(1) instead of scanning the
    // up-to-256 entries linearly.
    std::deque<std::string> removed_ids;
    std::unordered_set<std::string> removed_ids_set;
    std::chrono::steady_clock::time_point last_stats;
    std::chrono::steady_clock::time_point last_resume_save;
    // Last known status per torrent, refreshed by state_update_alert. The
    // snapshot reads this cache instead of calling status() on every handle:
    // with a large library that per-handle query dominates the poll.
    std::unordered_map<std::string, lt::torrent_status> status_cache;
    // Serializes every public entry point: the bridge owns mutable state
    // (errors, portmap, config) and libtorrent calls are synchronous. A caller
    // may therefore use one session from several threads.
    std::mutex mutex;
};

namespace {

// RAII lock for the public `vt_*` entry points. Null-safe, so it can be the
// first statement of a function that still has to validate its arguments.
struct session_lock
{
    explicit session_lock(vt_session* value) : session(value)
    {
        if (session)
            session->mutex.lock();
    }

    session_lock(session_lock const&) = delete;
    session_lock& operator=(session_lock const&) = delete;

    ~session_lock()
    {
        if (session)
            session->mutex.unlock();
    }

    // vt_session_destroy deletes the object: release the mutex first.
    void unlock()
    {
        if (session)
        {
            session->mutex.unlock();
            session = nullptr;
        }
    }

    vt_session* session;
};

#define VT_LOCK_SESSION(value) session_lock vt_session_lock_guard_((value))

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

void push_alert_error(vt_session* session, std::string const& message)
{
    if (!session || message.empty())
        return;
    // libtorrent reports some adds twice (sync error + alert): one event.
    if (!session->alert_errors.empty() && session->alert_errors.back() == message)
        return;
    session->alert_errors.push_back(message);
    while (session->alert_errors.size() > vt_session::max_alert_errors)
        session->alert_errors.pop_front();
}

void unmark_removed(vt_session* session, std::string const& id)
{
    session->removed_ids_set.erase(id);
    session->removed_ids.erase(
        std::remove(session->removed_ids.begin(), session->removed_ids.end(), id),
        session->removed_ids.end());
}

void drop_all_peer_connections(vt_session* session);

// When both bind_address and SOCKS5 proxy are active, libtorrent 2.1's
// use_proxy path binds its internal proxy listener to 0.0.0.0, ignoring
// listen_interfaces for HTTP tracker SOCKS5 connections and suppressing
// listen_failed_alert when the VPN interface goes down. Enforce fail-closed
// semantics explicitly by pausing the libtorrent session whenever the bound
// local address is absent, and resuming when it returns.
void enforce_bound_proxy_guard(vt_session* session)
{
    if (!session || !session->session)
        return;

    if (session->proxy_type == 1 && !session->bind_address.empty())
    {
        if (!is_local_address_present(session->bind_address))
        {
            if (!session->bound_interface_down)
            {
                session->bound_interface_down = true;
                session->session->pause();
                drop_all_peer_connections(session);
            }
            if (session->listen_error.empty())
                session->listen_error = session->bind_address + ": address not available";
        }
        else if (session->bound_interface_down)
        {
            session->bound_interface_down = false;
            session->listen_error.clear();
            session->session->resume();
        }
    }
    else if (session->bound_interface_down)
    {
        session->bound_interface_down = false;
        if (session->bind_address.empty())
            session->listen_error.clear();
        session->session->resume();
    }
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

// Returns false when proxy_type asks for a proxy but no hostname was supplied.
// The caller must fail instead of applying a clearnet configuration: a silent
// fallback would leave the UI showing an active proxy that is not in use.
bool configure_proxy_pack(vt_session* session,
                          lt::settings_pack& settings,
                          int proxy_type,
                          const char* hostname,
                          int port,
                          const char* username,
                          const char* password)
{
    if (proxy_type == 1)
    {
        if (!hostname || !*hostname)
            return false;
    }

    if (proxy_type == 1)
    {
        session->proxy_type = 1;
        session->proxy_host = hostname;
        session->proxy_port = (port > 0 && port <= 65535) ? port : 1080;
        session->proxy_user = (username && *username) ? username : "";
        session->proxy_password = (password && *password) ? password : "";
        session->proxy_error.clear();

        // libtorrent offers username/password authentication only when the
        // proxy type is socks5_pw AND the username is non-empty
        // (socks5_stream.hpp sends the no-auth method when m_user is empty).
        // A password without a username therefore cannot authenticate.
        session->proxy_auth = !session->proxy_user.empty();
        settings.set_int(lt::settings_pack::proxy_type,
                         session->proxy_auth ? lt::settings_pack::socks5_pw
                                             : lt::settings_pack::socks5);
        settings.set_str(lt::settings_pack::proxy_hostname, session->proxy_host);
        settings.set_int(lt::settings_pack::proxy_port, session->proxy_port);
        settings.set_str(lt::settings_pack::proxy_username, session->proxy_user);
        settings.set_str(lt::settings_pack::proxy_password, session->proxy_password);

        // Leak prevention: all tracker and peer traffic routed through SOCKS5 proxy
        settings.set_bool(lt::settings_pack::proxy_tracker_connections, true);
        settings.set_bool(lt::settings_pack::proxy_peer_connections, true);
        settings.set_bool(lt::settings_pack::proxy_hostnames, true);

        // Enforce strict anonymous mode: if the proxy fails, libtorrent never
        // falls back to the clearnet adapter. Existing connections are dropped
        // by the caller (see drop_all_peer_connections).
        settings.set_bool(lt::settings_pack::anonymous_mode, true);

        // With SOCKS5 active, router UPnP/NAT-PMP mapping and DHT are disabled:
        // libtorrent resolves dht_bootstrap_nodes via the system DNS resolver
        // even when proxy_hostnames and anonymous_mode are enabled.
        settings.set_bool(lt::settings_pack::enable_dht, false);
        settings.set_bool(lt::settings_pack::enable_upnp, false);
        settings.set_bool(lt::settings_pack::enable_natpmp, false);
        session->dht_nodes = 0;
        reset_portmap_state(session);
    }
    else
    {
        session->proxy_type = 0;
        session->proxy_auth = false;
        session->proxy_host.clear();
        session->proxy_port = 0;
        session->proxy_user.clear();
        session->proxy_password.clear();
        session->proxy_error.clear();

        settings.set_int(lt::settings_pack::proxy_type, lt::settings_pack::none);
        settings.set_str(lt::settings_pack::proxy_hostname, "");
        settings.set_str(lt::settings_pack::proxy_username, "");
        settings.set_str(lt::settings_pack::proxy_password, "");
        settings.set_bool(lt::settings_pack::anonymous_mode, false);

        // Restore DHT and UPnP / NAT-PMP settings according to session preferences
        settings.set_bool(lt::settings_pack::enable_dht, session->dht_enabled);
        settings.set_bool(lt::settings_pack::enable_upnp, session->upnp_enabled);
        settings.set_bool(lt::settings_pack::enable_natpmp, session->upnp_enabled);
        reset_portmap_state(session);
    }
    return true;
}

// Applying proxy settings does not reconnect the peers that were established
// before the change: libtorrent keeps serving them over the old path. Drop
// them explicitly, so enabling a proxy cannot leave a transfer running from
// the real address (the "fail-closed" promise of the SOCKS5 feature).
void drop_all_peer_connections(vt_session* session)
{
    if (!session || !session->session)
        return;
    try
    {
        for (auto handle : session->session->get_torrents())
        {
            if (handle.is_valid())
                handle.clear_peers();
        }
    }
    catch (...)
    {
    }
}

std::string format_peer_flags(lt::peer_info const& peer)
{
    std::string flags;
    bool const interesting = bool(peer.flags & lt::peer_info::interesting);
    bool const remote_choked = bool(peer.flags & lt::peer_info::remote_choked);
    bool const remote_interested = bool(peer.flags & lt::peer_info::remote_interested);
    bool const choked = bool(peer.flags & lt::peer_info::choked);

    if (interesting)
        flags += remote_choked ? 'd' : 'D';
    if (remote_interested)
        flags += choked ? 'u' : 'U';
    if (bool(peer.flags & lt::peer_info::optimistic_unchoke))
        flags += 'O';
    if (bool(peer.flags & lt::peer_info::seed))
        flags += 'S';
    if (!bool(peer.flags & lt::peer_info::outgoing_connection))
        flags += 'I';
    if (bool(peer.flags & lt::peer_info::utp_socket))
        flags += 'P';
    if (bool(peer.flags & (lt::peer_info::rc4_encrypted
                           | lt::peer_info::plaintext_encrypted
                           | lt::peer_info::ssl_socket)))
        flags += 'E';
    return flags;
}

std::string format_peer_source(lt::peer_info const& peer)
{
    if (bool(peer.source & lt::peer_info::lsd))
        return "LSD";
    if (bool(peer.source & lt::peer_info::pex))
        return "PEX";
    if (bool(peer.source & lt::peer_info::dht))
        return "DHT";
    if (bool(peer.source & lt::peer_info::tracker))
        return "Tracker";
    return "";
}

int add_torrent_common(vt_session* session,
                       lt::add_torrent_params& params,
                       const char* save_path,
                       int paused,
                       int sequential)
{
    // An unusable destination is reported, not silently replaced with the
    // session default: the user would find the torrent in a folder they did not
    // choose. (Loading resume data still uses prepared_save_path: there the
    // original folder may legitimately be gone.)
    std::string const requested = save_path && *save_path ? save_path : session->default_save_path;
    std::string const destination = normalized_save_path(requested, session->default_save_path);
    if (!is_usable_directory(destination))
    {
        session->last_error = "La cartella di destinazione non è scrivibile.";
        return -1;
    }
    params.save_path = destination;
    params.flags |= lt::torrent_flags::duplicate_is_error;
    // The active-torrent limit is enforced by libtorrent's auto-manager, which
    // only acts on auto-managed torrents. A torrent the user wants paused must
    // leave auto-management, otherwise the manager would start it again on the
    // next recalculation.
    if (paused)
    {
        params.flags |= lt::torrent_flags::paused;
        params.flags &= ~lt::torrent_flags::auto_managed;
    }
    else
    {
        params.flags &= ~lt::torrent_flags::paused;
        params.flags |= lt::torrent_flags::auto_managed;
    }
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
    // An empty resume directory has no meaning: joining it with "<hash>.resume"
    // would write into the process working directory instead of failing.
    if (resume_dir.empty())
        return false;

    try
    {
        auto buffer = lt::write_resume_data_buf(params);
        auto id = to_hex(params.info_hashes.get_best());
        if (id.empty())
            return false;

        fs::path final_path = fs::path(resume_dir) / (id + ".resume");
        fs::path tmp_path = final_path;
        tmp_path += ".tmp";

        // Open no-follow with 0600 permissions, write all bytes, and fsync on
        // the same descriptor before atomic rename so symlinks cannot be
        // followed and resume files (which hold tracker URLs and names) are
        // private to the user.
        auto write_and_sync_file = [&]() -> bool {
            int const fd = ::open(
                tmp_path.c_str(),
                O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC,
                0600);
            if (fd < 0)
                return false;
            ::fchmod(fd, 0600);
            char const* ptr = buffer.data();
            std::size_t remaining = buffer.size();
            while (remaining > 0)
            {
                ssize_t const written = ::write(fd, ptr, remaining);
                if (written < 0)
                {
                    if (errno == EINTR)
                        continue;
                    ::close(fd);
                    return false;
                }
                ptr += written;
                remaining -= static_cast<std::size_t>(written);
            }
            bool const ok = ::fsync(fd) == 0;
            ::close(fd);
            return ok;
        };

        // The directory is created once with the session; recreate it only if
        // it disappeared, so the periodic save does not hit the filesystem.
        if (!write_and_sync_file())
        {
            std::error_code dir_ec;
            fs::create_directories(resume_dir, dir_ec);
            if (dir_ec || !write_and_sync_file())
            {
                std::error_code remove_ec;
                fs::remove(tmp_path, remove_ec);
                return false;
            }
        }

        std::error_code ec;
        fs::rename(tmp_path, final_path, ec);
        if (ec)
        {
            fs::remove(tmp_path, ec);
            return false;
        }

        // Hybrid torrents added from a v1-only magnet switch get_best() from
        // v1 to truncated v2 once metadata arrives: clean up any earlier
        // <v1>.resume so restarts and removals stay consistent.
        if (params.info_hashes.has_v1() && params.info_hashes.has_v2())
        {
            auto const v1_id = to_hex(params.info_hashes.v1);
            if (!v1_id.empty() && v1_id != id)
            {
                std::error_code stale_ec;
                fs::remove(fs::path(resume_dir) / (v1_id + ".resume"), stale_ec);
            }
        }

        // Persist the directory entry too, so the new name survives a crash.
        int const dir_fd = ::open(resume_dir.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (dir_fd >= 0)
        {
            ::fsync(dir_fd);
            ::close(dir_fd);
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
    std::int64_t total_size = status.total;
    if (total_size <= 0)
        total_size = status.total_done;

    std::int64_t wanted = status.total_wanted > 0 ? status.total_wanted : total_size;
    std::int64_t size = (status.has_metadata && status.total_wanted > 0) ? status.total_wanted : total_size;
    std::int64_t downloaded = (status.has_metadata && status.total_wanted > 0) ? status.total_wanted_done : status.total_done;

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
    out << "\"downloaded\":" << downloaded << ",";
    out << "\"uploaded\":" << (status.all_time_upload > 0 ? status.all_time_upload : status.total_upload) << ",";
    out << "\"download_rate\":" << status.download_payload_rate << ",";
    out << "\"upload_rate\":" << status.upload_payload_rate << ",";
    out << "\"peers\":" << status.num_peers << ",";
    out << "\"seeds\":" << status.num_seeds << ",";
    out << "\"eta\":" << eta << ",";
    out << "\"finished\":" << ((status.is_finished || status.is_seeding) ? "true" : "false") << ",";
    out << "\"seeding\":" << (status.is_seeding ? "true" : "false") << ",";
    out << "\"paused\":" << (has_flag(status.flags, lt::torrent_flags::paused) ? "true" : "false") << ",";
    // paused + auto_managed is the queued state: libtorrent's auto-manager pauses
    // the torrents that do not fit in `active_limit`.
    out << "\"auto_managed\":" << (has_flag(status.flags, lt::torrent_flags::auto_managed) ? "true" : "false") << ",";
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

vt_session* vt_session_create_configured(const char* download_dir,
                                         const char* resume_dir,
                                         int listen_port,
                                         int download_limit_bytes,
                                         int upload_limit_bytes,
                                         int enable_dht,
                                         int enable_pex,
                                         int enable_lsd,
                                         int enable_upnp,
                                         const char* bind_address,
                                         int proxy_type,
                                         const char* proxy_host,
                                         int proxy_port,
                                         const char* proxy_user,
                                         const char* proxy_password,
                                         const char* app_version,
                                         char** error_message)
{
    if (error_message)
        *error_message = nullptr;

    try
    {
        auto session = std::make_unique<vt_session>();
        session->default_save_path = download_dir ? download_dir : "";
        session->resume_dir = resume_dir ? resume_dir : "";
        session->listen_port = (listen_port > 0 && listen_port <= 65535) ? listen_port : 6881;
        if (!normalize_bind_address_c(bind_address, session->bind_address))
        {
            if (error_message)
                *error_message = ::strdup("Parametri non validi");
            return nullptr;
        }
        session->dht_enabled = enable_dht != 0;
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

        std::string const version_str = (app_version && *app_version) ? app_version : "1.17.11";
        lt::settings_pack settings;
        settings.set_str(lt::settings_pack::user_agent,
                         "Vertex/" + version_str + " libtorrent/" LIBTORRENT_VERSION);
        settings.set_str(lt::settings_pack::peer_fingerprint, "-VT1E00-");
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
        bool const effective_dht = session->dht_enabled && (proxy_type != 1);
        apply_link_settings(settings, download_limit_bytes, upload_limit_bytes,
                            effective_dht ? 1 : 0, enable_upnp, enable_lsd);
        if (proxy_type == 1)
        {
            // Configure SOCKS5 and anonymous_mode in the initial settings_pack
            // BEFORE starting lt::session and loading resume files, so no packet
            // can leave over clearnet during startup. A missing host is an error,
            // not a reason to start in clearnet.
            if (!configure_proxy_pack(session.get(), settings, proxy_type, proxy_host,
                                      proxy_port, proxy_user, proxy_password))
            {
                if (error_message)
                    *error_message = ::strdup("Host proxy non valido");
                return nullptr;
            }
        }
        settings.set_str(lt::settings_pack::dht_bootstrap_nodes,
                         "router.bittorrent.com:6881,dht.libtorrent.org:25401,"
                         "dht.transmissionbt.com:6881,router.utorrent.com:6881");
        settings.set_int(lt::settings_pack::connections_limit, 400);
        settings.set_int(lt::settings_pack::active_limit, -1);
        settings.set_int(lt::settings_pack::active_downloads, -1);
        settings.set_int(lt::settings_pack::active_seeds, -1);
        settings.set_bool(lt::settings_pack::dont_count_slow_torrents, false);
        settings.set_int(lt::settings_pack::alert_queue_size, 4096);
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
        enforce_bound_proxy_guard(session.get());

        if (!session->resume_dir.empty())
        {
            // A resume file that cannot be parsed would be retried at every
            // startup and never reported. Move it aside instead, so it stops
            // being read and the problem is visible in the folder.
            auto quarantine = [](fs::path const& path) {
                std::error_code qec;
                fs::path target = path;
                target += ".bad";
                fs::rename(path, target, qec);
            };

            std::error_code ec;
            fs::directory_iterator it(session->resume_dir, ec);
            fs::directory_iterator const end;
            for (; !ec && it != end; it.increment(ec))
            {
                auto const entry_path = it->path();
                // symlink_status does not follow links: a symlink named
                // *.resume must never make the bridge read another file.
                std::error_code type_ec;
                if (!fs::is_regular_file(fs::symlink_status(entry_path, type_ec))
                    || type_ec || entry_path.extension() != ".resume")
                    continue;

                try
                {
                    // Open no-follow and bound the read on the file descriptor
                    // itself so neither a swapped symlink nor a file growing past
                    // MAX_RESUME_FILE can be read into memory.
                    constexpr std::size_t MAX_RESUME_FILE = 10 * 1024 * 1024; // 10 MiB
                    int const fd = ::open(entry_path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
                    if (fd < 0)
                        continue;

                    struct stat st{};
                    if (::fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)
                        || st.st_size <= 0
                        || static_cast<std::uintmax_t>(st.st_size) > MAX_RESUME_FILE)
                    {
                        bool const bad_size = S_ISREG(st.st_mode)
                            && (st.st_size <= 0
                                || static_cast<std::uintmax_t>(st.st_size) > MAX_RESUME_FILE);
                        ::close(fd);
                        if (bad_size)
                            quarantine(entry_path);
                        continue;
                    }

                    std::vector<char> data;
                    data.reserve(static_cast<std::size_t>(st.st_size));
                    char chunk[65536];
                    bool read_failed = false;
                    while (true)
                    {
                        ssize_t const n = ::read(fd, chunk, sizeof(chunk));
                        if (n < 0)
                        {
                            if (errno == EINTR)
                                continue;
                            read_failed = true;
                            break;
                        }
                        if (n == 0)
                            break;
                        if (data.size() + static_cast<std::size_t>(n) > MAX_RESUME_FILE)
                        {
                            read_failed = true;
                            break;
                        }
                        data.insert(data.end(), chunk, chunk + n);
                    }
                    ::close(fd);

                    if (read_failed || data.empty() || data.size() > MAX_RESUME_FILE)
                    {
                        quarantine(entry_path);
                        continue;
                    }

                    lt::error_code resume_ec;
                    auto params = lt::read_resume_data(
                        lt::span<char const>(data.data(), static_cast<int>(data.size())), resume_ec);
                    if (resume_ec)
                    {
                        quarantine(entry_path);
                        continue;
                    }

                    params.save_path = prepared_save_path(params.save_path, session->default_save_path);
                    // The resume data carries the flags of the last session: a
                    // torrent that was queued must stay queued, and one paused by
                    // the user must stay paused (no auto_managed).
                    lt::error_code add_ec;
                    session->session->add_torrent(std::move(params), add_ec);
                    if (add_ec && add_ec != lt::errors::duplicate_torrent)
                        quarantine(entry_path);
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
    return vt_session_create_configured(
        download_dir,
        resume_dir,
        listen_port,
        download_limit_bytes,
        upload_limit_bytes,
        enable_dht,
        enable_pex,
        enable_lsd,
        enable_upnp,
        bind_address,
        0,
        nullptr,
        0,
        nullptr,
        nullptr,
        nullptr,
        error_message
    );
}

void vt_session_destroy(vt_session* session)
{
    if (!session)
        return;
    VT_LOCK_SESSION(session);

    try
    {
        // Only wait for resume data of torrents that are still in the session
        // and either need saving or do not yet have a resume file on disk.
        // Stale alerts from removed torrents must neither recreate their files
        // nor decrement the pending counter.
        std::set<std::string> requested_ids;

        // Drain any save_resume_data_alert already posted before shutdown
        // (for instance by vt_set_file_priority, vt_set_trackers, vt_control or
        // the periodic timer). libtorrent clears need_save_resume_data() as soon
        // as the alert is posted, so skipping this drain would lose updates made
        // right before Cmd-Q. If file_prio_alert or storage_moved_alert arrives
        // here, request a fresh save and track its id in requested_ids so the
        // loop below waits for the updated resume buffer.
        {
            std::vector<lt::alert*> pre_alerts;
            session->session->pop_alerts(&pre_alerts);
            for (auto* alert : pre_alerts)
            {
                if (auto* saved = lt::alert_cast<lt::save_resume_data_alert>(alert))
                {
                    auto const id = to_hex(saved->params.info_hashes.get_best());
                    if (!id.empty() && !is_removed(session, id) && saved->handle.is_valid())
                        write_resume_impl(session->resume_dir, saved->params);
                }
                else if (auto* prio = lt::alert_cast<lt::file_prio_alert>(alert))
                {
                    if (prio->handle.is_valid())
                    {
                        try
                        {
                            auto const id = to_hex(prio->handle.info_hashes().get_best());
                            if (!id.empty() && !is_removed(session, id))
                            {
                                prio->handle.save_resume_data(lt::torrent_handle::save_info_dict);
                                requested_ids.insert(id);
                            }
                        }
                        catch (...)
                        {
                        }
                    }
                }
                else if (auto* moved = lt::alert_cast<lt::storage_moved_alert>(alert))
                {
                    if (moved->handle.is_valid())
                    {
                        try
                        {
                            auto const id = to_hex(moved->handle.info_hashes().get_best());
                            if (!id.empty() && !is_removed(session, id))
                            {
                                moved->handle.save_resume_data(lt::torrent_handle::save_info_dict);
                                requested_ids.insert(id);
                            }
                        }
                        catch (...)
                        {
                        }
                    }
                }
            }
        }

        for (auto const& handle : session->session->get_torrents())
        {
            try
            {
                if (!handle.is_valid())
                    continue;

                auto id = to_hex(handle.info_hashes().get_best());
                if (id.empty() || is_removed(session, id) || requested_ids.count(id) > 0)
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
                    if (!id.empty() && !is_removed(session, id) && saved->handle.is_valid())
                        write_resume_impl(session->resume_dir, saved->params);
                    if (requested_ids.erase(id) > 0)
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

                    // A stale alert must not release a slot for another torrent:
                    // decrementing here truncated the drain and could lose the
                    // resume data of the torrents that were actually requested.
                    // The deadline below bounds the pathological case instead.
                }
            }
        }
    }
    catch (...)
    {
    }

    // The object is about to disappear: release the mutex before deleting it.
    vt_session_lock_guard_.unlock();
    delete session;
}

void vt_session_poll(vt_session* session)
{
    if (!session || !session->session)
        return;
    VT_LOCK_SESSION(session);

    try
    {
        enforce_bound_proxy_guard(session);
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

        // Ask for the torrents that changed since the last poll. The resulting
        // alert fills status_cache, so the snapshot only queries the handles it
        // has never seen (first poll after a resume) instead of all of them.
        try
        {
            session->session->post_torrent_updates(
                lt::torrent_handle::query_name
                | lt::torrent_handle::query_save_path
                | lt::torrent_handle::query_accurate_download_counters);
        }
        catch (...)
        {
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
            else if (auto* moved = lt::alert_cast<lt::storage_moved_alert>(alert))
            {
                if (moved->handle.is_valid())
                {
                    try
                    {
                        moved->handle.save_resume_data(lt::torrent_handle::save_info_dict);
                    }
                    catch (...)
                    {
                    }
                }
            }
            else if (auto* prio = lt::alert_cast<lt::file_prio_alert>(alert))
            {
                if (prio->handle.is_valid())
                {
                    try
                    {
                        prio->handle.save_resume_data(lt::torrent_handle::save_info_dict);
                    }
                    catch (...)
                    {
                    }
                }
            }
            else if (lt::alert_cast<lt::alerts_dropped_alert>(alert))
            {
                // A dropped state_update_alert or save_resume_data_alert would
                // leave status_cache stale or skip persisting a dirty torrent:
                // invalidate the cache and re-request pending resume saves.
                session->status_cache.clear();
                for (auto const& handle : session->session->get_torrents())
                {
                    try
                    {
                        if (handle.is_valid())
                            handle.save_resume_data(lt::torrent_handle::save_info_dict);
                    }
                    catch (...)
                    {
                    }
                }
            }
            else if (auto* move_failed = lt::alert_cast<lt::storage_moved_failed_alert>(alert))
            {
                push_alert_error(session, move_failed->error.message());
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
                if (!session->bound_interface_down)
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
                    push_alert_error(session, added->error.message());
            }
            else if (auto* error = lt::alert_cast<lt::torrent_error_alert>(alert))
            {
                push_alert_error(session, error->error.message());
            }
            else if (auto* socks = lt::alert_cast<lt::socks5_alert>(alert))
            {
                if (socks->error)
                    session->proxy_error = socks->error.message();
            }
            else if (auto* update = lt::alert_cast<lt::state_update_alert>(alert))
            {
                for (auto const& status : update->status)
                {
                    try
                    {
                        session->status_cache[to_hex(status.info_hashes.get_best())] = status;
                    }
                    catch (...)
                    {
                    }
                }
            }
            // No peer_connect_alert handler here on purpose: its alert category
            // (`connect`) is not part of the session alert mask, so the alert
            // never arrives. The proxy error is cleared by the TCP health probe
            // in TorrentEngine+Polling through vt_clear_proxy_error().
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
    VT_LOCK_SESSION(session);

    try
    {
        std::ostringstream out;
        out.imbue(std::locale::classic());

        std::deque<std::string> alert_errors;
        alert_errors.swap(session->alert_errors);

        std::int64_t download_rate = 0;
        std::int64_t upload_rate = 0;
        int active = 0;
        int paused = 0;

        auto handles = session->session->get_torrents();
        // Drop the cache of removed torrents once it is clearly larger than the
        // live set; the snapshot repopulates it lazily.
        if (session->status_cache.size() > handles.size() * 2 + 64)
            session->status_cache.clear();

        out << "{\"torrents\":[";
        bool first = true;
        for (auto const& handle : handles)
        {
            try
            {
                // Only the fields used below: skip pieces and verified pieces, but keep
                // accurate counters so progress/ETA don't jump by whole pieces.
                auto const query = lt::torrent_handle::query_name
                                   | lt::torrent_handle::query_save_path
                                   | lt::torrent_handle::query_accurate_download_counters;
                std::string const cache_id = to_hex(handle.info_hashes().get_best());
                lt::torrent_status status;
                auto cached = session->status_cache.find(cache_id);
                if (cached != session->status_cache.end())
                {
                    status = cached->second;
                }
                else
                {
                    // Cold cache (first poll after a resume): one direct query,
                    // then the state_update_alert keeps the entry fresh.
                    status = handle.status(query);
                    session->status_cache[cache_id] = status;
                }

                // Build the whole object in its own stream: `append_torrent_json`
                // writes dozens of fields, and an exception in the middle of it
                // would leave the shared document truncated, invalidating the
                // snapshot (and the poll) for every other torrent as well.
                std::ostringstream entry;
                entry.imbue(std::locale::classic());
                append_torrent_json(entry, status);

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
                out << entry.str();
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
        // `alert_error` stays for compatibility (last message); the array is the
        // complete set collected between two polls.
        out << "\"alert_error\":\""
            << json_escape(alert_errors.empty() ? std::string() : alert_errors.back())
            << "\",";
        out << "\"alert_errors\":[";
        for (std::size_t i = 0; i < alert_errors.size(); ++i)
        {
            if (i)
                out << ',';
            out << '"' << json_escape(alert_errors[i]) << '"';
        }
        out << "],";

        try
        {
            if (session->bound_interface_down)
            {
                session->actual_listen_port = 0;
                session->listening = false;
            }
            else
            {
                session->actual_listen_port = int(session->session->listen_port());
                session->listening = session->session->is_listening();
            }
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
        out << "\"port\":" << session->listen_port << ",";
        out << "\"max_active\":" << session->max_active;
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
    VT_LOCK_SESSION(session);

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

        out << "],\"peers\":[";

        if (handle.is_valid())
        {
            std::vector<lt::peer_info> peers;
            handle.get_peer_info(peers);
            bool first = true;
            for (auto const& peer : peers)
            {
                if (bool(peer.flags & lt::peer_info::connecting))
                    continue;

                std::string endpoint_str;
                if (bool(peer.flags & lt::peer_info::i2p_socket))
                {
                    endpoint_str = "i2p";
                }
                else
                {
                    auto const ep = peer.remote_endpoint();
                    auto const addr = ep.address();
                    if (addr.is_v6())
                        endpoint_str = "[" + addr.to_string() + "]:" + std::to_string(ep.port());
                    else
                        endpoint_str = addr.to_string() + ":" + std::to_string(ep.port());
                }

                double const progress = (std::min)((std::max)(double(peer.progress), 0.0), 1.0);
                std::int64_t const down_rate = (std::max)(0, peer.payload_down_speed);
                std::int64_t const up_rate = (std::max)(0, peer.payload_up_speed);
                std::string const flags = format_peer_flags(peer);
                std::string const source = format_peer_source(peer);

                if (!first)
                    out << ",";
                first = false;
                out << "{";
                out << "\"endpoint\":\"" << json_escape(endpoint_str) << "\",";
                out << "\"client\":\"" << json_escape(peer.client) << "\",";
                out << "\"progress\":" << std::fixed << std::setprecision(4) << progress << ",";
                out << "\"download_rate\":" << down_rate << ",";
                out << "\"upload_rate\":" << up_rate << ",";
                out << "\"flags\":\"" << json_escape(flags) << "\",";
                out << "\"source\":\"" << json_escape(source) << "\"";
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
    VT_LOCK_SESSION(session);
    auto text = session->last_error;
    session->last_error.clear();
    return ::strdup(text.c_str());
}

char* vt_magnet_uri(vt_session* session, const char* torrent_id_value)
{
    if (!session || !torrent_id_value)
        return nullptr;
    VT_LOCK_SESSION(session);

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
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
    if (!uri)
    {
        session->last_error = "Parametri non validi";
        return -1;
    }

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
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
    if (!path)
    {
        session->last_error = "Parametri non validi";
        return -1;
    }

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
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
    if (!torrent_id_value || !host || port <= 0 || port > 65535)
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
    forceStart,
    reannounce,
    sequentialOn,
    sequentialOff,
    dequeue,
    remove,
    removeFiles,
    unknown,
};

ControlAction parse_control_action(std::string const& action)
{
    if (action == "pause")         return ControlAction::pause;
    if (action == "resume")        return ControlAction::resume;
    if (action == "force_start")   return ControlAction::forceStart;
    if (action == "reannounce")    return ControlAction::reannounce;
    if (action == "sequential_on") return ControlAction::sequentialOn;
    if (action == "sequential_off")return ControlAction::sequentialOff;
    if (action == "dequeue")      return ControlAction::dequeue;
    if (action == "remove")        return ControlAction::remove;
    if (action == "remove_files")  return ControlAction::removeFiles;
    return ControlAction::unknown;
}

} // namespace

int vt_control(vt_session* session, const char* torrent_id_value, const char* action)
{
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
    if (!torrent_id_value || !action)
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

        ControlAction const command = parse_control_action(action);

        switch (command)
        {
        case ControlAction::pause:
            // A manual pause must leave auto-management: otherwise the queue
            // manager would restart the torrent on the next recalculation.
            handle.unset_flags(lt::torrent_flags::auto_managed);
            handle.pause();
            handle.save_resume_data(lt::torrent_handle::save_info_dict);
            break;

        case ControlAction::resume:
        {
            // A torrent stopped by an error stays stopped until the error is cleared.
            auto const st = handle.status(lt::status_flags_t{});
            if (st.errc)
                handle.clear_error();
            // Resuming hands the torrent back to the auto-manager: when no queue
            // limit is active (max_active <= 0), unpause immediately; when a
            // positive limit is active, let the auto-manager assign a slot so a
            // queued torrent cannot exceed max_active.
            handle.set_flags(lt::torrent_flags::auto_managed);
            if (session->max_active <= 0)
                handle.resume();
            handle.save_resume_data(lt::torrent_handle::save_info_dict);
            break;
        }

        case ControlAction::forceStart:
            // Force start starts the torrent immediately, bypassing queue limits
            // by disabling auto_managed and resuming.
            if (handle.status(lt::status_flags_t{}).errc)
                handle.clear_error();
            handle.unset_flags(lt::torrent_flags::auto_managed);
            handle.resume();
            handle.save_resume_data(lt::torrent_handle::save_info_dict);
            break;

        case ControlAction::dequeue:
            // Leave the queue without starting: the torrent stays paused but
            // stops competing for an active slot.
            handle.unset_flags(lt::torrent_flags::auto_managed);
            handle.save_resume_data(lt::torrent_handle::save_info_dict);
            break;

        case ControlAction::reannounce:
            handle.force_reannounce();
            break;

        case ControlAction::sequentialOn:
            handle.set_flags(lt::torrent_flags::sequential_download);
            handle.save_resume_data(lt::torrent_handle::save_info_dict);
            break;

        case ControlAction::sequentialOff:
            handle.unset_flags(lt::torrent_flags::sequential_download);
            handle.save_resume_data(lt::torrent_handle::save_info_dict);
            break;

        case ControlAction::remove:
        case ControlAction::removeFiles:
        {
            auto const hashes = handle.info_hashes();
            auto const best_id = to_hex(hashes.get_best());
            auto const v1_id = hashes.has_v1() ? to_hex(hashes.v1) : std::string{};
            if (!best_id.empty())
            {
                mark_removed(session, best_id);
                session->status_cache.erase(best_id);
            }
            if (!v1_id.empty() && v1_id != best_id)
            {
                mark_removed(session, v1_id);
                session->status_cache.erase(v1_id);
            }
            if (command == ControlAction::removeFiles)
                session->session->remove_torrent(handle, lt::session::delete_files);
            else
                session->session->remove_torrent(handle);
            if (!session->resume_dir.empty())
            {
                std::error_code ec;
                if (!best_id.empty())
                    fs::remove(fs::path(session->resume_dir) / (best_id + ".resume"), ec);
                if (!v1_id.empty() && v1_id != best_id)
                    fs::remove(fs::path(session->resume_dir) / (v1_id + ".resume"), ec);
            }
            break;
        }

        case ControlAction::unknown:
            session->last_error = "Comando non supportato";
            return -1;
        }

        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_set_trackers(vt_session* session, const char* torrent_id_value, const char* urls)
{
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
    if (!torrent_id_value || !urls)
    {
        session->last_error = "Parametri non validi";
        return -1;
    }

    // Bounds for a list that comes from a text field: a torrent with hundreds of
    // trackers is a configuration mistake, and a huge URL is not a URL.
    constexpr std::size_t max_trackers = 128;
    constexpr std::size_t max_url_length = 2048;

    try
    {
        auto handle = find_handle(session, torrent_id_value);
        if (!handle.is_valid())
        {
            session->last_error = "Torrent non trovato";
            return -1;
        }

        std::vector<lt::announce_entry> entries;
        std::istringstream stream(urls);
        std::string line;
        while (std::getline(stream, line))
        {
            auto const first = line.find_first_not_of(" \t\r\n");
            if (first == std::string::npos)
                continue;
            auto const last = line.find_last_not_of(" \t\r\n");
            line = line.substr(first, last - first + 1);

            if (line.size() > max_url_length)
            {
                session->last_error = "URL del tracker troppo lungo";
                return -1;
            }
            // Only absolute URLs: libtorrent would ignore anything else, and the
            // user would see the tracker disappear after a restart.
            if (line.find("://") == std::string::npos)
            {
                session->last_error = "URL del tracker non valido";
                return -1;
            }
            if (entries.size() >= max_trackers)
            {
                session->last_error = "Troppi tracker";
                return -1;
            }
            entries.emplace_back(line);
        }

        handle.replace_trackers(entries);
        handle.save_resume_data(lt::torrent_handle::save_info_dict);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_set_file_priority(vt_session* session, const char* torrent_id_value, int file_index, int priority)
{
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
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
        auto info = handle.torrent_file();
        if (!info)
        {
            session->last_error = "Metadati non disponibili";
            return -1;
        }
        if (file_index >= info->layout().num_files())
        {
            session->last_error = "Parametri non validi";
            return -1;
        }
        handle.file_priority(lt::file_index_t(file_index),
                             lt::download_priority_t(std::uint8_t(priority)));
        handle.save_resume_data(lt::torrent_handle::save_info_dict);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_set_all_file_priorities(vt_session* session, const char* torrent_id_value, int priority)
{
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
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
        handle.save_resume_data(lt::torrent_handle::save_info_dict);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_move_storage(vt_session* session, const char* torrent_id_value, const char* save_path)
{
    if (!session || !session->session)
        return -1;
    VT_LOCK_SESSION(session);
    if (!torrent_id_value || !save_path || !*save_path)
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

        std::string const destination = normalized_save_path(save_path, "");
        if (destination.empty() || !is_usable_directory(destination))
        {
            session->last_error = "La cartella di destinazione non è scrivibile.";
            return -1;
        }

        auto const current_save = handle.status(lt::torrent_handle::query_save_path).save_path;
        if (!current_save.empty())
        {
            std::error_code eq_ec;
            if (fs::equivalent(destination, current_save, eq_ec) && !eq_ec)
                return 0;
        }

        if (auto info = handle.torrent_file())
        {
            auto const& storage = info->layout();
            std::error_code ec;
            for (int i = 0; i < storage.num_files(); ++i)
            {
                fs::path target_file = fs::path(destination) / storage.file_path(lt::file_index_t(i));
                if (fs::exists(target_file, ec) && !ec)
                {
                    session->last_error = "Esiste già un file con lo stesso nome nella cartella di destinazione.";
                    return -1;
                }
            }
        }

        handle.move_storage(destination, lt::move_flags_t::fail_if_exist);
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
    VT_LOCK_SESSION(session);

    try
    {
        std::string requested_bind;
        if (!normalize_bind_address_c(bind_address, requested_bind))
        {
            session->last_error = "Parametri non validi";
            return -1;
        }
        if (listen_port > 65535)
        {
            session->last_error = "Parametri non validi";
            return -1;
        }

        lt::settings_pack settings;
        bool const port_changed = listen_port > 0 && listen_port != session->listen_port;
        bool const bind_changed = requested_bind != session->bind_address;
        if (port_changed || bind_changed)
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
        session->dht_enabled = enable_dht != 0;
        if ((enable_upnp != 0) != session->upnp_enabled)
        {
            session->upnp_enabled = enable_upnp != 0;
            reset_portmap_state(session);
        }
        bool const effective_dht = session->dht_enabled && (session->proxy_type == 0);
        bool const effective_upnp = (enable_upnp != 0) && (session->proxy_type == 0);
        apply_link_settings(settings, download_limit_bytes, upload_limit_bytes,
                            effective_dht ? 1 : 0, effective_upnp ? 1 : 0, enable_lsd);
        session->session->apply_settings(settings);
        if (bind_changed)
            drop_all_peer_connections(session);
        enforce_bound_proxy_guard(session);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

int vt_set_active_limit(vt_session* session, int max_active)
{
    if (!session || !session->session)
        return -1;
    VT_LOCK_SESSION(session);

    try
    {
        // libtorrent maps any negative value to "unlimited" (session_impl's
        // get_int_setting), while `active_limit <= 0` would pause *everything*.
        // One positive value caps downloads, seeds and the total at the same
        // number: min(active_downloads + active_seeds, active_limit) == N.
        int const value = max_active > 0 ? max_active : -1;

        lt::settings_pack settings;
        settings.set_int(lt::settings_pack::active_limit, value);
        settings.set_int(lt::settings_pack::active_downloads, value);
        settings.set_int(lt::settings_pack::active_seeds, value);
        // Deterministic queue: slow torrents count against the limit like any
        // other, so the number of active rows in the UI matches the setting.
        settings.set_bool(lt::settings_pack::dont_count_slow_torrents, false);
        session->session->apply_settings(settings);

        session->max_active = max_active;
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
    VT_LOCK_SESSION(session);

    try
    {
        bool const was_active = session->proxy_type == 1;
        std::string const previous_host = session->proxy_host;
        int const previous_port = session->proxy_port;
        bool const previous_auth = session->proxy_auth;
        std::string const previous_user = session->proxy_user;
        std::string const previous_password = session->proxy_password;

        lt::settings_pack settings;
        if (!configure_proxy_pack(session, settings, proxy_type, hostname, port, username, password))
        {
            session->last_error = "Host proxy non valido";
            return -1;
        }
        session->session->apply_settings(settings);

        bool const now_active = session->proxy_type == 1;
        bool const endpoint_changed = was_active != now_active
            || (now_active
                && (previous_host != session->proxy_host
                    || previous_port != session->proxy_port
                    || previous_auth != session->proxy_auth
                    || previous_user != session->proxy_user
                    || previous_password != session->proxy_password));
        if (endpoint_changed)
            drop_all_peer_connections(session);
        enforce_bound_proxy_guard(session);
        return 0;
    }
    VT_CATCH_ALL(session, -1)
}

void vt_clear_proxy_error(vt_session* session)
{
    if (!session)
        return;
    VT_LOCK_SESSION(session);
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
    if (!session)
        return -1;
    VT_LOCK_SESSION(session);
    if (!path || !*path)
    {
        session->last_error = "Parametri non validi";
        return -1;
    }

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
        if (::access(target.c_str(), W_OK | X_OK) != 0)
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
    return is_valid_utf8(std::string_view(input)) ? 1 : 0;
}

void vt_free_string(char* value)
{
    std::free(value);
}

} // extern "C"
