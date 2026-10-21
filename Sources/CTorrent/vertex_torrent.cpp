#include "vertex_torrent.h"

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/portmap.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <locale>
#include <memory>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

namespace {

std::string json_escape(std::string const& input)
{
    std::string out;
    out.reserve(input.size() + 16);
    for (unsigned char c : input)
    {
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

std::string torrent_id(lt::torrent_status const& status)
{
    return to_hex(status.info_hashes.get_best());
}

std::string prepared_save_path(std::string const& requested, std::string const& fallback)
{
    namespace fs = std::filesystem;
    std::string candidate = requested.empty() ? fallback : requested;

    std::error_code ec;
    fs::path path(candidate);
    auto status = fs::status(path, ec);
    if (!ec)
    {
        if (fs::is_directory(status))
        {
            // ok as-is
        }
        else if (fs::is_regular_file(status))
        {
            // A file was used as destination (often a .torrent): use its folder.
            candidate = path.parent_path().string();
        }
    }
    else if (path.extension() == ".torrent")
    {
        candidate = path.parent_path().string();
    }

    if (candidate.empty())
        candidate = fallback;

    fs::create_directories(candidate, ec);
    if (ec || ::access(candidate.c_str(), W_OK) != 0)
    {
        std::error_code fallback_ec;
        fs::create_directories(fallback, fallback_ec);
        if (!fallback_ec && ::access(fallback.c_str(), W_OK) == 0)
            candidate = fallback;
    }

    return candidate;
}

bool has_flag(lt::torrent_flags_t flags, lt::torrent_flags_t flag)
{
    return bool(flags & flag);
}

std::string state_string(lt::torrent_status::state_t state)
{
    switch (state)
    {
    case lt::torrent_status::checking_files: return "checking";
    case lt::torrent_status::downloading_metadata: return "metadata";
    case lt::torrent_status::downloading: return "downloading";
    case lt::torrent_status::finished: return "finished";
    case lt::torrent_status::seeding: return "seeding";
    case lt::torrent_status::checking_resume_data: return "checking";
    default: return "queued";
    }
}

bool write_resume_impl(std::string const& resume_dir, lt::add_torrent_params const& params);
void append_torrent_json(std::ostringstream& out, lt::torrent_handle const& handle);

} // namespace

struct vt_session
{
    std::unique_ptr<lt::session> session;
    std::string default_save_path;
    std::string resume_dir;
    int listen_port = 6881;
    int dht_metric_index = -1;
    int dht_nodes = 0;
    std::string last_error;
    int actual_listen_port = 0;
    bool listening = false;
    bool upnp_enabled = true;
    bool tcp_mapped = false;
    int tcp_external_port = 0;
    std::string tcp_map_transport;
    bool udp_mapped = false;
    int udp_external_port = 0;
    std::string udp_map_transport;
    std::string portmap_error;
    // Ids of torrents removed by the user: late resume-data alerts must not recreate their files.
    std::set<std::string> removed_ids;
    std::chrono::steady_clock::time_point last_stats;
    std::chrono::steady_clock::time_point last_resume_save;
};

namespace {

lt::torrent_handle find_handle(vt_session* session, std::string const& id)
{
    for (auto const& handle : session->session->get_torrents())
    {
        try
        {
            auto status = handle.status(lt::torrent_handle::query_name | lt::torrent_handle::query_save_path);
            if (torrent_id(status) == id)
                return handle;
        }
        catch (...)
        {
        }
    }
    return {};
}

bool write_resume_impl(std::string const& resume_dir, lt::add_torrent_params const& params)
{
    try
    {
        auto buffer = lt::write_resume_data_buf(params);
        auto id = to_hex(params.info_hashes.get_best());
        if (id.empty())
            return false;

        fs::create_directories(resume_dir);
        fs::path final_path = fs::path(resume_dir) / (id + ".resume");
        fs::path tmp_path = final_path;
        tmp_path += ".tmp";

        {
            std::ofstream file(tmp_path, std::ios::binary | std::ios::trunc);
            if (!file)
                return false;
            file.write(buffer.data(), static_cast<std::streamsize>(buffer.size()));
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

void append_torrent_json(std::ostringstream& out, lt::torrent_handle const& handle)
{
    auto status = handle.status();

    auto info = status.torrent_file.lock();
    std::int64_t size = info ? info->total_size() : status.total;
    if (size <= 0)
        size = status.total_done;

    int files = 0;
    if (info)
        files = info->num_files();

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
    out << "\"state\":\"" << state_string(status.state) << "\",";
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
    out << "\"files\":" << files << ",";
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

vt_session* vt_session_create(const char* download_dir,
                             const char* resume_dir,
                             int listen_port,
                             int download_limit_bytes,
                             int upload_limit_bytes,
                             int enable_dht)
{
    try
    {
        auto session = std::make_unique<vt_session>();
        session->default_save_path = download_dir ? download_dir : "";
        session->resume_dir = resume_dir ? resume_dir : "";
        session->listen_port = listen_port > 0 ? listen_port : 6881;
        session->upnp_enabled = true;

        if (!session->default_save_path.empty())
            fs::create_directories(session->default_save_path);
        if (!session->resume_dir.empty())
            fs::create_directories(session->resume_dir);

        lt::settings_pack settings;
        settings.set_str(lt::settings_pack::user_agent, "Vertex/1.0 libtorrent/" LIBTORRENT_VERSION);
        settings.set_str(lt::settings_pack::peer_fingerprint, "-VT1000-");
        settings.set_int(lt::settings_pack::alert_mask,
                         int(static_cast<std::uint32_t>(lt::alert_category::error |
                                                        lt::alert_category::storage |
                                                        lt::alert_category::status |
                                                        lt::alert_category::port_mapping)));
        settings.set_str(lt::settings_pack::listen_interfaces,
                         "0.0.0.0:" + std::to_string(session->listen_port) +
                             ",[::]:" + std::to_string(session->listen_port));
        settings.set_bool(lt::settings_pack::enable_dht, enable_dht != 0);
        settings.set_bool(lt::settings_pack::enable_lsd, true);
        settings.set_bool(lt::settings_pack::enable_upnp, true);
        settings.set_bool(lt::settings_pack::enable_natpmp, true);
        settings.set_str(lt::settings_pack::dht_bootstrap_nodes,
                         "router.bittorrent.com:6881,dht.libtorrent.org:25401,"
                         "dht.transmissionbt.com:6881,router.utorrent.com:6881");
        settings.set_int(lt::settings_pack::download_rate_limit, (std::max)(0, download_limit_bytes));
        settings.set_int(lt::settings_pack::upload_rate_limit, (std::max)(0, upload_limit_bytes));
        settings.set_int(lt::settings_pack::connections_limit, 400);
        settings.set_int(lt::settings_pack::active_limit, 100);
        settings.set_int(lt::settings_pack::alert_queue_size, 1000);
        settings.set_bool(lt::settings_pack::announce_to_all_tiers, true);
        settings.set_bool(lt::settings_pack::announce_to_all_trackers, true);

        session->session = std::make_unique<lt::session>(settings);
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
    catch (...)
    {
        return nullptr;
    }
}

void vt_session_destroy(vt_session* session)
{
    if (!session)
        return;

    try
    {
        // Only wait for resume data of torrents that are still in the session.
        // Stale alerts from removed torrents must neither recreate their files
        // nor decrement the pending counter.
        std::set<std::string> requested_ids;
        for (auto const& handle : session->session->get_torrents())
        {
            try
            {
                if (!handle.is_valid())
                    continue;

                auto status = handle.status();
                auto id = torrent_id(status);
                handle.save_resume_data();
                requested_ids.insert(id);
            }
            catch (...)
            {
            }
        }

        int pending = int(requested_ids.size());
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
        while (pending > 0 && std::chrono::steady_clock::now() < deadline)
        {
            std::vector<lt::alert*> alerts;
            session->session->pop_alerts(&alerts);
            for (auto* alert : alerts)
            {
                if (auto* saved = lt::alert_cast<lt::save_resume_data_alert>(alert))
                {
                    auto const id = to_hex(saved->params.info_hashes.get_best());
                    if (requested_ids.erase(id) == 0)
                        continue;

                    if (session->removed_ids.count(id) == 0 && saved->handle.is_valid())
                        write_resume_impl(session->resume_dir, saved->params);
                    --pending;
                }
                else if (auto* failed = lt::alert_cast<lt::save_resume_data_failed_alert>(alert))
                {
                    try
                    {
                        auto id = torrent_id(failed->handle.status());
                        if (requested_ids.erase(id) > 0)
                            --pending;
                    }
                    catch (...)
                    {
                    }
                }
            }
            if (pending > 0)
                std::this_thread::sleep_for(std::chrono::milliseconds(40));
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
                        handle.save_resume_data();
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
                if (session->removed_ids.count(id) == 0 && saved->handle.is_valid())
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
            else if (auto* mapped = lt::alert_cast<lt::portmap_alert>(alert))
            {
                std::string transport = mapped->map_transport == lt::portmap_transport::upnp
                                            ? "UPnP"
                                            : "NAT-PMP";
                if (mapped->map_protocol == lt::portmap_protocol::tcp)
                {
                    session->tcp_mapped = true;
                    session->tcp_external_port = mapped->external_port;
                    session->tcp_map_transport = transport;
                }
                else if (mapped->map_protocol == lt::portmap_protocol::udp)
                {
                    session->udp_mapped = true;
                    session->udp_external_port = mapped->external_port;
                    session->udp_map_transport = transport;
                }
                session->portmap_error.clear();
            }
            else if (auto* map_error = lt::alert_cast<lt::portmap_error_alert>(alert))
            {
                session->portmap_error = map_error->error.message();
            }
            else if (auto* added = lt::alert_cast<lt::add_torrent_alert>(alert))
            {
                if (added->error)
                    session->last_error = added->error.message();
            }
            else if (auto* error = lt::alert_cast<lt::torrent_error_alert>(alert))
            {
                session->last_error = error->error.message();
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

        std::int64_t download_rate = 0;
        std::int64_t upload_rate = 0;
        std::int64_t total_download = 0;
        std::int64_t total_upload = 0;
        int active = 0;
        int paused = 0;

        out << "{\"torrents\":[";
        bool first = true;
        for (auto const& handle : session->session->get_torrents())
        {
            try
            {
                auto status = handle.status();
                download_rate += status.download_payload_rate;
                upload_rate += status.upload_payload_rate;
                total_download += status.all_time_download;
                total_upload += status.all_time_upload;
                bool is_paused = has_flag(status.flags, lt::torrent_flags::paused);
                if (is_paused)
                    ++paused;
                else
                    ++active;

                if (!first)
                    out << ",";
                first = false;
                append_torrent_json(out, handle);
            }
            catch (...)
            {
            }
        }
        out << "],";
        out << "\"download_rate\":" << download_rate << ",";
        out << "\"upload_rate\":" << upload_rate << ",";
        out << "\"total_download\":" << total_download << ",";
        out << "\"total_upload\":" << total_upload << ",";
        out << "\"active\":" << active << ",";
        out << "\"paused_count\":" << paused << ",";
        out << "\"dht_nodes\":" << session->dht_nodes << ",";

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
        out << "\"portmap\":{";
        out << "\"tcp\":{\"mapped\":" << (session->tcp_mapped ? "true" : "false")
            << ",\"external_port\":" << session->tcp_external_port
            << ",\"transport\":\"" << json_escape(session->tcp_map_transport) << "\"},";
        out << "\"udp\":{\"mapped\":" << (session->udp_mapped ? "true" : "false")
            << ",\"external_port\":" << session->udp_external_port
            << ",\"transport\":\"" << json_escape(session->udp_map_transport) << "\"},";
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
        if (handle.is_valid())
        {
            auto info = handle.torrent_file();
            if (info)
            {
                auto progress = handle.file_progress();
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
            bool first = true;
            for (auto const& tracker : trackers)
            {
                std::string message;
                int fails = 0;
                int peers = -1;
                int seeds = -1;
                if (!tracker.endpoints.empty())
                {
                    auto const& infohash = tracker.endpoints.front().info_hashes[lt::protocol_version::V1];
                    message = infohash.message;
                    fails = infohash.fails;
                    peers = infohash.scrape_incomplete;
                    seeds = infohash.scrape_complete;
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

        out << "],\"metadata\":" << (handle.is_valid() && handle.status().has_metadata ? "true" : "false");
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
        auto uri = lt::make_magnet_uri(handle.get_resume_data());
        return ::strdup(uri.c_str());
    }
    catch (...)
    {
        return ::strdup("");
    }
}

int vt_add_magnet(vt_session* session,
                  const char* uri,
                  const char* save_path,
                  int paused,
                  int sequential)
{
    if (!session || !uri)
        return -1;

    try
    {
        lt::error_code ec;
        auto params = lt::parse_magnet_uri(lt::string_view(uri), ec);
        if (ec)
        {
            session->last_error = ec.message();
            return -1;
        }

        params.save_path = prepared_save_path(
            save_path && *save_path ? save_path : session->default_save_path,
            session->default_save_path);
        params.flags |= lt::torrent_flags::duplicate_is_error;
        params.flags &= ~lt::torrent_flags::auto_managed;
        if (paused)
            params.flags |= lt::torrent_flags::paused;
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
        session->removed_ids.erase(added_id);
        return 0;
    }
    catch (std::exception const& e)
    {
        session->last_error = e.what();
        return -1;
    }
    catch (...)
    {
        session->last_error = "Errore sconosciuto";
        return -1;
    }
}

int vt_add_torrent_file(vt_session* session,
                        const char* path,
                        const char* save_path,
                        int paused,
                        int sequential)
{
    if (!session || !path)
        return -1;

    try
    {
        lt::error_code ec;
        auto params = lt::load_torrent_file(path, ec, lt::load_torrent_limits{});
        if (ec)
        {
            session->last_error = ec.message();
            return -1;
        }

        params.save_path = prepared_save_path(
            save_path && *save_path ? save_path : session->default_save_path,
            session->default_save_path);
        params.flags |= lt::torrent_flags::duplicate_is_error;
        params.flags &= ~lt::torrent_flags::auto_managed;
        if (paused)
            params.flags |= lt::torrent_flags::paused;
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
        session->removed_ids.erase(added_id);
        return 0;
    }
    catch (std::exception const& e)
    {
        session->last_error = e.what();
        return -1;
    }
    catch (...)
    {
        session->last_error = "Errore sconosciuto";
        return -1;
    }
}

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

        std::string command(action);
        if (command == "pause")
        {
            handle.pause();
        }
        else if (command == "resume")
        {
            // A torrent stopped by an error stays stopped until the error is cleared.
            if (handle.status().errc)
                handle.clear_error();
            handle.resume();
        }
        else if (command == "reannounce")
        {
            handle.force_reannounce();
        }
        else if (command == "sequential_on")
        {
            handle.set_flags(lt::torrent_flags::sequential_download);
        }
        else if (command == "sequential_off")
        {
            handle.unset_flags(lt::torrent_flags::sequential_download);
        }
        else if (command == "remove")
        {
            session->removed_ids.insert(std::string(torrent_id_value));
            session->session->remove_torrent(handle);
            if (!session->resume_dir.empty())
            {
                std::error_code ec;
                fs::remove(fs::path(session->resume_dir) / (std::string(torrent_id_value) + ".resume"),
                           ec);
            }
        }
        else if (command == "remove_files")
        {
            session->removed_ids.insert(std::string(torrent_id_value));
            session->session->remove_torrent(handle, lt::session::delete_files);
            if (!session->resume_dir.empty())
            {
                std::error_code ec;
                fs::remove(fs::path(session->resume_dir) / (std::string(torrent_id_value) + ".resume"),
                           ec);
            }
        }
        else
        {
            session->last_error = "Comando non supportato";
            return -1;
        }

        return 0;
    }
    catch (std::exception const& e)
    {
        session->last_error = e.what();
        return -1;
    }
    catch (...)
    {
        session->last_error = "Errore sconosciuto";
        return -1;
    }
}

int vt_set_file_priority(vt_session* session, const char* torrent_id_value, int file_index, int priority)
{
    if (!session || !torrent_id_value)
        return -1;

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
    catch (std::exception const& e)
    {
        session->last_error = e.what();
        return -1;
    }
    catch (...)
    {
        return -1;
    }
}

int vt_apply_settings(vt_session* session,
                      int listen_port,
                      int download_limit_bytes,
                      int upload_limit_bytes,
                      int enable_dht,
                      int enable_upnp)
{
    if (!session || !session->session)
        return -1;

    try
    {
        lt::settings_pack settings;
        if (listen_port > 0 && listen_port != session->listen_port)
        {
            session->listen_port = listen_port;
            session->tcp_mapped = false;
            session->tcp_external_port = 0;
            session->tcp_map_transport.clear();
            session->udp_mapped = false;
            session->udp_external_port = 0;
            session->udp_map_transport.clear();
            session->portmap_error.clear();
            settings.set_str(lt::settings_pack::listen_interfaces,
                             "0.0.0.0:" + std::to_string(listen_port) +
                                 ",[::]:" + std::to_string(listen_port));
        }
        if ((enable_upnp != 0) != session->upnp_enabled)
        {
            session->upnp_enabled = enable_upnp != 0;
            session->tcp_mapped = false;
            session->tcp_external_port = 0;
            session->tcp_map_transport.clear();
            session->udp_mapped = false;
            session->udp_external_port = 0;
            session->udp_map_transport.clear();
            session->portmap_error.clear();
        }
        settings.set_int(lt::settings_pack::download_rate_limit, (std::max)(0, download_limit_bytes));
        settings.set_int(lt::settings_pack::upload_rate_limit, (std::max)(0, upload_limit_bytes));
        settings.set_bool(lt::settings_pack::enable_dht, enable_dht != 0);
        settings.set_bool(lt::settings_pack::enable_upnp, enable_upnp != 0);
        settings.set_bool(lt::settings_pack::enable_natpmp, enable_upnp != 0);
        session->session->apply_settings(settings);
        return 0;
    }
    catch (...)
    {
        return -1;
    }
}

void vt_free_string(char* value)
{
    std::free(value);
}

} // extern "C"
