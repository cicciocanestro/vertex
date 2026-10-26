#ifndef VERTEX_TORRENT_H
#define VERTEX_TORRENT_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vt_session vt_session;

vt_session* vt_session_create(const char* download_dir,
                             const char* resume_dir,
                             int listen_port,
                             int download_limit_bytes,
                             int upload_limit_bytes,
                             int enable_dht);

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
int vt_apply_settings(vt_session* session,
                      int listen_port,
                      int download_limit_bytes,
                      int upload_limit_bytes,
                      int enable_dht,
                      int enable_upnp);

void vt_free_string(char* value);

#ifdef __cplusplus
}
#endif

#endif
