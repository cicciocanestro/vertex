#ifndef VERTEX_TORRENT_H
#define VERTEX_TORRENT_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vt_session vt_session;

/* Creates the session. PEX is a session-level plugin in libtorrent, so changing
   it requires recreating the session. LSD and UPnP/NAT-PMP are normal session
   settings and can also be changed at runtime with vt_apply_settings_ex. This
   is the only session entry point: the legacy create variants were removed.

   bind_address optionally pins the session to one local address (typically a
   VPN tunnel address such as the WireGuard interface). It sets both
   listen_interfaces and outgoing_interfaces, so the listening socket and every
   outgoing connection use that address only; libtorrent rejects incoming
   traffic on any other local interface. NULL or "" listens on every interface,
   which is the default. It accepts a literal IPv4 or IPv6 address, not a device
   name. */
vt_session* vt_session_create_full(const char* download_dir,
                                   const char* resume_dir,
                                   int listen_port,
                                   int download_limit_bytes,
                                   int upload_limit_bytes,
                                   int enable_dht,
                                   int enable_pex,
                                   int enable_lsd,
                                   int enable_upnp,
                                   const char* bind_address);

/* Saves resume data and destroys the session. It can wait up to ~3 seconds:
   callers must invoke it off the main/UI thread. */
void vt_session_destroy(vt_session* session);
void vt_session_poll(vt_session* session);

char* vt_snapshot_json(vt_session* session);
char* vt_detail_json(vt_session* session, const char* torrent_id);
char* vt_last_error(vt_session* session);
char* vt_magnet_uri(vt_session* session, const char* torrent_id);

int vt_add_magnet(vt_session* session,
                  const char* uri,
                  const char* save_path,
                  int paused,
                  int sequential);

int vt_add_torrent_file(vt_session* session,
                        const char* path,
                        const char* save_path,
                        int paused,
                        int sequential);

/* Connect an already-added torrent to an explicit peer. This is used by the
   deterministic loopback integration tests and can also be useful for
   diagnostics; it does not enable any external discovery service. */
int vt_add_peer(vt_session* session,
                const char* torrent_id,
                const char* host,
                int port);

int vt_control(vt_session* session, const char* torrent_id, const char* action);
int vt_set_file_priority(vt_session* session, const char* torrent_id, int file_index, int priority);
/* Runtime settings update. Returns 0 on success. bind_address follows the same
   rules as vt_session_create_full: NULL or "" restores listening on every
   interface. Changing it rebinds the sockets and resets the UPnP/NAT-PMP state,
   because a mapping belongs to the address that requested it. */
int vt_apply_settings_ex(vt_session* session,
                         int listen_port,
                         int download_limit_bytes,
                         int upload_limit_bytes,
                         int enable_dht,
                         int enable_upnp,
                         int enable_lsd,
                         const char* bind_address);

/* Updates the fallback folder used when a torrent is added without an explicit
   save path. The folder is created if needed. Returns 0 on success. */
int vt_set_default_save_path(vt_session* session, const char* path);

void vt_free_string(char* value);

#ifdef __cplusplus
}
#endif

#endif
