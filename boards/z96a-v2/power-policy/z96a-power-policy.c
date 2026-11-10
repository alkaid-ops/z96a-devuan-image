/*
 * z96a-power-policy - AC/battery policy for the Z96A Devuan X11 session.
 *
 * The daemon intentionally keeps policy decisions in one process.  Slimlock
 * only renders the status file and performs authentication.
 */
#include <glib.h>
#include <glib/gstdio.h>
#include <gio/gio.h>
#include <X11/Xlib.h>
#include <X11/extensions/scrnsaver.h>
#include <X11/extensions/dpms.h>
#include <limits.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define APP_NAME "z96a-power-policy"
#define CONFIG_PATH "/etc/z96a/power-policy.conf"
#define LOCK_COMMAND "/usr/local/bin/z96a-lock"
#define CRITICAL_DIALOG "/usr/local/libexec/z96a-battery-critical-dialog"
#define LOGIN1_NAME "org.freedesktop.login1"
#define LOGIN1_PATH "/org/freedesktop/login1"
#define LOGIN1_IFACE "org.freedesktop.login1.Manager"
#define SESSION_IFACE "org.freedesktop.login1.Session"

typedef enum {
    AUTO_NONE,
    AUTO_SUSPEND,
    AUTO_POWEROFF
} AutoAction;

typedef struct {
    int ac_dim;
    int ac_lock;
    int ac_suspend;
    int battery_dim;
    int battery_lock;
    int battery_suspend;
    int ac_screen_off;
    int battery_screen_off;
    int ac_poweroff;
    int battery_poweroff;
    int dim_percent;
    int warning_percent;
    int critical_percent;
    int critical_grace_seconds;
    gboolean critical_shutdown_enabled;
    int profile_grace_seconds;
    gboolean lock_input_resets_idle;
    gboolean unknown_is_ac;
    AutoAction auto_action;
} Config;

typedef struct {
    char power_source[16];
    char profile[16];
    int battery_percent;
    int battery_present;
    char battery_status[32];
    gboolean locked;
    gboolean was_locked;
    gint64 locked_idle_base_ms;
    gint64 locked_start_us;
    int suspend_remaining;
    int poweroff_remaining;
    int critical_remaining;
    gboolean critical_override;
    char policy_state[32];
    gint64 updated_ms;
    gint64 idle_ms;
    gint64 critical_deadline_us;
    int warning_level;
    gboolean dimmed;
    int saved_brightness;
    gint64 profile_grace_until_us;
    gint64 last_lock_attempt_us;
    gint64 last_suspend_attempt_us;
    gint64 last_poweroff_attempt_us;
    gint64 previous_idle_ms;
    gboolean screen_off;
} Runtime;

typedef struct {
    GMainLoop *loop;
    Display *dpy;
    Window root;
    int xss_event_base;
    int xss_error_base;
    gboolean xss_available;
    Config cfg;
    Config system_cfg;
    Runtime rt;
    char *config_path;
    char *user_config_path;
    char *user_config_contents;
    gboolean user_config_seen;
    char *power_supply_dir;
    char *runtime_dir;
    char *status_path;
    char *lock_ready_path;
    char *lock_tmp_path;
    char *critical_override_path;
    GDBusProxy *login1;
    GDBusProxy *session;
    int inhibit_fd;
    int daemon_lock_fd;
    gboolean actions_enabled;
    gboolean once;
    gboolean check_only;
    gboolean stopping;
    GPid locker_pid;
    guint child_watch_id;
    GPid critical_dialog_pid;
    guint critical_dialog_watch_id;
    gboolean critical_dialog_cancel_pending;
    gboolean critical_dialog_attempted;
    guint tick_id;
    guint inhibitor_retry_id;
    int old_screen_timeout, old_screen_interval, old_blanking, old_exposures;
    CARD16 old_dpms_standby, old_dpms_suspend, old_dpms_off;
    BOOL old_dpms_enabled;
    gboolean have_display_settings;
} App;

static App *g_app;
static void request_poweroff(App *app, gboolean critical);

static void log_msg(const char *level, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    g_printerr("%s: %s: ", APP_NAME, level);
    g_vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

static gboolean read_text_file(const char *path, char *buf, size_t buflen)
{
    gchar *contents = NULL;
    gsize len = 0;
    if (!g_file_get_contents(path, &contents, &len, NULL))
        return FALSE;
    g_strchomp(contents);
    g_strlcpy(buf, contents, buflen);
    g_free(contents);
    return TRUE;
}

static int battery_ntc_presence(void)
{
    const char *override = g_getenv("Z96A_BATTERY_PRESENT");
    if (override && *override) {
        if (strcmp(override, "0") == 0)
            return 0;
        if (strcmp(override, "1") == 0)
            return 1;
    }

    GDir *dir = g_dir_open("/sys/bus/iio/devices", 0, NULL);
    const char *name;
    int result = -1;
    if (!dir)
        return -1;
    while ((name = g_dir_read_name(dir))) {
        char path[PATH_MAX];
        char devname[128] = "";
        char rawbuf[64] = "";
        char *end = NULL;
        long raw;
        g_snprintf(path, sizeof(path), "/sys/bus/iio/devices/%s/name", name);
        if (!read_text_file(path, devname, sizeof(devname)) ||
            !strstr(devname, "saradc"))
            continue;
        g_snprintf(path, sizeof(path), "/sys/bus/iio/devices/%s/in_voltage4_raw", name);
        if (!read_text_file(path, rawbuf, sizeof(rawbuf)))
            continue;
        errno = 0;
        raw = strtol(rawbuf, &end, 10);
        if (errno || end == rawbuf)
            continue;
        /* The battery NTC is a 10k/10k divider. Open circuit reads the rail. */
        if (raw >= 980 || raw <= 10)
            result = 0;
        else
            result = 1;
        break;
    }
    g_dir_close(dir);
    return result;
}

static gboolean apply_config(GKeyFile *kf, Config *cfg, gboolean system, GError **error)
{
    GError *local = NULL;
    gchar *action = NULL;
#define GET_INT(key, member) do { \
    if (g_key_file_has_key(kf, "Policy", key, NULL)) { \
        cfg->member = g_key_file_get_integer(kf, "Policy", key, &local); \
        if (local) goto invalid; \
    } \
} while (0)
#define GET_BOOL(key, member) do { \
    if (g_key_file_has_key(kf, "Policy", key, NULL)) { \
        cfg->member = g_key_file_get_boolean(kf, "Policy", key, &local); \
        if (local) goto invalid; \
    } \
} while (0)
    if (system) {
        GET_INT("ACDimTimeout", ac_dim);
        GET_INT("ACLockTimeout", ac_lock);
        GET_INT("BatteryDimTimeout", battery_dim);
        GET_INT("BatteryLockTimeout", battery_lock);
        GET_INT("DimBrightnessPercent", dim_percent);
        GET_INT("BatteryWarningPercent", warning_percent);
        GET_INT("BatteryCriticalPercent", critical_percent);
        GET_INT("CriticalShutdownGraceSeconds", critical_grace_seconds);
        GET_INT("ProfileSwitchGraceSeconds", profile_grace_seconds);
        GET_BOOL("LockInputResetsIdle", lock_input_resets_idle);
        GET_BOOL("UnknownUsesACProfile", unknown_is_ac);
    }
    GET_BOOL("CriticalShutdownEnabled", critical_shutdown_enabled);
    GET_INT("ACSuspendTimeout", ac_suspend);
    GET_INT("BatterySuspendTimeout", battery_suspend);
    GET_INT("ACScreenOffTimeout", ac_screen_off);
    GET_INT("BatteryScreenOffTimeout", battery_screen_off);
    GET_INT("ACPoweroffTimeout", ac_poweroff);
    GET_INT("BatteryPoweroffTimeout", battery_poweroff);
    if (g_key_file_has_key(kf, "Policy", "AutoAction", NULL)) {
        action = g_key_file_get_string(kf, "Policy", "AutoAction", &local);
        if (local) goto invalid;
        if (g_strcmp0(action, "none") == 0) cfg->auto_action = AUTO_NONE;
        else if (g_strcmp0(action, "suspend") == 0) cfg->auto_action = AUTO_SUSPEND;
        else if (g_strcmp0(action, "poweroff") == 0) cfg->auto_action = AUTO_POWEROFF;
        else {
            g_set_error(&local, G_KEY_FILE_ERROR, G_KEY_FILE_ERROR_INVALID_VALUE,
                        "AutoAction 必须是 none、suspend 或 poweroff");
            goto invalid;
        }
    } else if (system && g_key_file_has_key(kf, "Policy", "AutoSuspendEnabled", NULL)) {
        gboolean enabled = g_key_file_get_boolean(kf, "Policy", "AutoSuspendEnabled", &local);
        if (local) goto invalid;
        cfg->auto_action = enabled ? AUTO_SUSPEND : AUTO_NONE;
    }
    if (cfg->ac_dim <= 0 || cfg->ac_lock <= 0 || cfg->ac_suspend <= 0 ||
        cfg->battery_dim <= 0 || cfg->battery_lock <= 0 || cfg->battery_suspend <= 0 ||
        cfg->ac_screen_off < 0 || cfg->battery_screen_off < 0 ||
        cfg->ac_poweroff <= 0 || cfg->battery_poweroff <= 0 ||
        cfg->ac_screen_off > 86400 || cfg->battery_screen_off > 86400 ||
        cfg->ac_suspend > 86400 || cfg->battery_suspend > 86400 ||
        cfg->ac_poweroff > 86400 || cfg->battery_poweroff > 86400 ||
        cfg->dim_percent < 1 || cfg->dim_percent > 100 ||
        cfg->warning_percent <= cfg->critical_percent ||
        cfg->critical_percent < 1 || cfg->critical_percent > 50 ||
        cfg->critical_grace_seconds < 0 || cfg->profile_grace_seconds < 0) {
        g_set_error(&local, G_KEY_FILE_ERROR, G_KEY_FILE_ERROR_INVALID_VALUE,
                    "电源策略配置值超出有效范围");
        goto invalid;
    }
    g_free(action);
#undef GET_INT
#undef GET_BOOL
    return TRUE;
invalid:
    g_free(action);
    g_propagate_error(error, local);
    return FALSE;
}

static gboolean load_config(const char *path, Config *cfg, GError **error)
{
    GKeyFile *kf = g_key_file_new();
    gboolean ok;
    *cfg = (Config){ .ac_dim = 300, .ac_lock = 600, .ac_suspend = 1800,
        .battery_dim = 120, .battery_lock = 300, .battery_suspend = 900,
        .ac_screen_off = 600, .battery_screen_off = 300,
        .ac_poweroff = 3600, .battery_poweroff = 1800,
        .dim_percent = 20, .warning_percent = 30, .critical_percent = 20,
        .critical_grace_seconds = 60, .critical_shutdown_enabled = TRUE,
        .profile_grace_seconds = 30,
        .lock_input_resets_idle = TRUE, .unknown_is_ac = TRUE, .auto_action = AUTO_NONE };
    ok = g_key_file_load_from_file(kf, path, G_KEY_FILE_NONE, error) &&
         apply_config(kf, cfg, TRUE, error);
    g_key_file_free(kf);
    return ok;
}

static gboolean apply_user_config(const char *contents, Config *cfg, GError **error)
{
    GKeyFile *kf = g_key_file_new();
    gboolean ok = g_key_file_load_from_data(kf, contents, -1, G_KEY_FILE_NONE, error) &&
                  apply_config(kf, cfg, FALSE, error);
    g_key_file_free(kf);
    return ok;
}

static void reload_user_config(App *app, gboolean initial)
{
    gchar *contents = NULL;
    Config candidate = app->system_cfg;
    GError *error = NULL;
    gboolean exists = g_file_get_contents(app->user_config_path, &contents, NULL, &error);
    if (!exists && !g_error_matches(error, G_FILE_ERROR, G_FILE_ERROR_NOENT)) {
        log_msg("error", "无法读取用户配置，保留现有策略: %s",
                error ? error->message : "unknown");
        g_clear_error(&error);
        return;
    }
    g_clear_error(&error);
    if (app->user_config_seen && g_strcmp0(contents, app->user_config_contents) == 0)
        return;
    app->user_config_seen = TRUE;
    g_free(app->user_config_contents);
    app->user_config_contents = g_strdup(contents);
    if (exists && !apply_user_config(contents, &candidate, &error)) {
        log_msg("error", "用户配置无效，保留现有策略: %s", error->message);
        g_clear_error(&error);
    } else {
        app->cfg = candidate;
        if (!initial)
            app->rt.profile_grace_until_us = g_get_monotonic_time() +
                (gint64)app->cfg.profile_grace_seconds * G_USEC_PER_SEC;
    }
    g_free(contents);
}

static gboolean acquire_daemon_lock(App *app)
{
    char *lock_path = g_build_filename(app->runtime_dir, "daemon.lock", NULL);
    char pidbuf[32];
    int fd = open(lock_path, O_CREAT | O_RDWR, 0600);
    if (fd < 0) {
        log_msg("error", "无法打开守护进程锁 %s: %s", lock_path, g_strerror(errno));
        g_free(lock_path);
        return FALSE;
    }
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        log_msg("info", "已有 z96a-power-policy 实例运行");
        close(fd);
        g_free(lock_path);
        return FALSE;
    }
    snprintf(pidbuf, sizeof(pidbuf), "%u\n", (unsigned)getpid());
    if (ftruncate(fd, 0) != 0 || write(fd, pidbuf, strlen(pidbuf)) < 0)
        log_msg("warning", "无法写入守护进程锁 PID");
    app->daemon_lock_fd = fd;
    g_free(lock_path);
    return TRUE;
}

static void ensure_runtime_paths(App *app)
{
    const char *xdg = g_getenv("XDG_RUNTIME_DIR");
    const char *override = g_getenv("Z96A_STATUS_DIR");
    if (override && *override)
        app->runtime_dir = g_strdup(override);
    else if (xdg && *xdg)
        app->runtime_dir = g_build_filename(xdg, "z96a-power", NULL);
    else
        app->runtime_dir = g_strdup_printf("/run/user/%u/z96a-power", (unsigned)getuid());
    g_mkdir_with_parents(app->runtime_dir, 0700);
    app->status_path = g_build_filename(app->runtime_dir, "status", NULL);
    app->lock_ready_path = g_build_filename(app->runtime_dir, "lock-ready", NULL);
    app->lock_tmp_path = g_build_filename(app->runtime_dir, "lock-ready.tmp", NULL);
    app->critical_override_path = g_build_filename(app->runtime_dir, "critical-override", NULL);
}

static int brightnessctl_get(void)
{
    gchar *out = NULL;
    gchar *err = NULL;
    gint status = 0;
    if (!g_spawn_command_line_sync("brightnessctl get", &out, &err, &status, NULL) ||
        !g_spawn_check_wait_status(status, NULL))
        goto fail;
    g_strstrip(out);
    int value = atoi(out);
    g_free(out);
    g_free(err);
    return value;
fail:
    g_free(out);
    g_free(err);
    return -1;
}

static void brightnessctl_set(int value)
{
    gchar *cmd;
    gchar *out = NULL;
    gchar *err = NULL;
    gint status = 0;
    if (value < 0)
        return;
    cmd = g_strdup_printf("brightnessctl set %d", value);
    if (!g_spawn_command_line_sync(cmd, &out, &err, &status, NULL) ||
        !g_spawn_check_wait_status(status, NULL))
        log_msg("warning", "brightnessctl 失败: %s", err ? err : "unknown error");
    g_free(cmd);
    g_free(out);
    g_free(err);
}

static void dim_screen(App *app)
{
    if (app->rt.dimmed)
        return;
    app->rt.saved_brightness = brightnessctl_get();
    if (app->rt.saved_brightness < 0)
        return;
    int dim = (app->rt.saved_brightness * app->cfg.dim_percent) / 100;
    if (dim < 1)
        dim = 1;
    if (dim > app->rt.saved_brightness)
        dim = app->rt.saved_brightness;
    brightnessctl_set(dim);
    app->rt.dimmed = TRUE;
}

static void restore_screen(App *app)
{
    if (!app->rt.dimmed)
        return;
    brightnessctl_set(app->rt.saved_brightness);
    app->rt.dimmed = FALSE;
}

static void refresh_power(App *app)
{
    const char *dirpath = app->power_supply_dir ? app->power_supply_dir : "/sys/class/power_supply";
    GDir *dir = g_dir_open(dirpath, 0, NULL);
    const char *name;
    gboolean external = FALSE;
    gboolean have_battery = FALSE;
    gboolean have_input = FALSE;
    gboolean unknown_input = FALSE;
    gboolean input_charging = FALSE;
    int capacity = -1;
    char status[32] = "Unknown";
    char old_profile[16];
    g_strlcpy(old_profile, app->rt.profile[0] ? app->rt.profile : "AC", sizeof(old_profile));

    if (dir) {
        while ((name = g_dir_read_name(dir))) {
            char path[PATH_MAX];
            char type[32] = "";
            char online[32] = "";
            char present[32] = "";
            char temp[64];
            g_snprintf(path, sizeof(path), "%s/%s/type", dirpath, name);
            if (!read_text_file(path, type, sizeof(type)) || !type[0]) {
                unknown_input = TRUE;
                continue;
            }
            g_snprintf(path, sizeof(path), "%s/%s/online", dirpath, name);
            read_text_file(path, online, sizeof(online));
            g_snprintf(path, sizeof(path), "%s/%s/present", dirpath, name);
            read_text_file(path, present, sizeof(present));
            if (strcmp(type, "Battery") != 0) {
                have_input = TRUE;
                if (strcmp(online, "1") == 0)
                    external = TRUE;
                else if (strcmp(online, "0") != 0)
                    unknown_input = TRUE;
                g_snprintf(path, sizeof(path), "%s/%s/status", dirpath, name);
                if (read_text_file(path, temp, sizeof(temp)) && strcmp(temp, "Charging") == 0)
                    input_charging = TRUE;
            }
            if (strcmp(type, "Battery") == 0 && (present[0] == '\0' || strcmp(present, "0") != 0)) {
                have_battery = TRUE;
                g_snprintf(path, sizeof(path), "%s/%s/capacity", dirpath, name);
                if (read_text_file(path, temp, sizeof(temp))) {
                    char *end = NULL;
                    long value = strtol(temp, &end, 10);
                    if (end != temp && *end == '\0' && value >= 0 && value <= 100)
                        capacity = (int)value;
                }
                g_snprintf(path, sizeof(path), "%s/%s/status", dirpath, name);
                if (read_text_file(path, temp, sizeof(temp)))
                    g_strlcpy(status, temp, sizeof(status));
            }
        }
        g_dir_close(dir);
    }

    if (capacity >= 0)
        app->rt.battery_percent = capacity;
    app->rt.battery_present = battery_ntc_presence();
    if (app->rt.battery_present != 1) {
        capacity = -1;
        have_battery = FALSE;
        g_strlcpy(status, app->rt.battery_present == 0 ? "Absent" : "Unknown", sizeof(status));
    }
    app->rt.battery_percent = capacity;
    g_strlcpy(app->rt.battery_status, status, sizeof(app->rt.battery_status));
    if (external) {
        g_strlcpy(app->rt.power_source, "AC", sizeof(app->rt.power_source));
        g_strlcpy(app->rt.profile, "AC", sizeof(app->rt.profile));
    } else if (have_battery && capacity >= 0 && have_input && !unknown_input &&
               !input_charging && strcmp(status, "Discharging") == 0) {
        g_strlcpy(app->rt.power_source, "BATTERY", sizeof(app->rt.power_source));
        g_strlcpy(app->rt.profile, "BATTERY", sizeof(app->rt.profile));
    } else {
        g_strlcpy(app->rt.power_source, "UNKNOWN", sizeof(app->rt.power_source));
        g_strlcpy(app->rt.profile, app->cfg.unknown_is_ac ? "AC" : "FALLBACK", sizeof(app->rt.profile));
    }

    if (strcmp(old_profile, app->rt.profile) != 0) {
        app->rt.profile_grace_until_us = g_get_monotonic_time() + ((gint64)app->cfg.profile_grace_seconds * G_USEC_PER_SEC);
        log_msg("info", "电源策略切换: %s -> %s, source=%s", old_profile, app->rt.profile, app->rt.power_source);
    }
}

static void write_status(App *app)
{
    gchar *body;
    gchar *tmp = g_strdup_printf("%s.tmp.%u", app->status_path, (unsigned)getpid());
    app->rt.updated_ms = g_get_monotonic_time() / 1000;
    body = g_strdup_printf(
        "POWER_SOURCE=%s\n"
        "PROFILE=%s\n"
        "BATTERY_PRESENT=%d\n"
        "BATTERY_PERCENT=%d\n"
        "BATTERY_STATUS=%s\n"
        "LOCKED=%d\n"
        "SUSPEND_REMAINING=%d\n"
        "POWEROFF_REMAINING=%d\n"
        "AUTO_ACTION=%s\n"
        "CRITICAL_SHUTDOWN_ENABLED=%d\n"
        "CRITICAL_REMAINING=%d\n"
        "CRITICAL_OVERRIDE=%d\n"
        "POLICY_STATE=%s\n"
        "UPDATED_MONOTONIC_MS=%" G_GINT64_FORMAT "\n",
        app->rt.power_source, app->rt.profile, app->rt.battery_present,
        app->rt.battery_percent, app->rt.battery_status, app->rt.locked ? 1 : 0,
        app->rt.suspend_remaining, app->rt.poweroff_remaining,
        app->cfg.auto_action == AUTO_SUSPEND ? "suspend" :
            app->cfg.auto_action == AUTO_POWEROFF ? "poweroff" : "none",
        app->cfg.critical_shutdown_enabled ? 1 : 0,
        app->rt.critical_remaining,
        app->rt.critical_override ? 1 : 0, app->rt.policy_state, app->rt.updated_ms);
    if (!g_file_set_contents(tmp, body, -1, NULL) || g_rename(tmp, app->status_path) != 0)
        log_msg("warning", "无法写入状态文件 %s", app->status_path);
    g_free(body);
    g_free(tmp);
}

static void notify_user(App *app, const char *urgency, const char *summary, const char *body)
{
    gchar *argv[8];
    GError *error = NULL;
    if (!app->actions_enabled || g_getenv("Z96A_NO_NOTIFY"))
        return;
    argv[0] = (gchar *)"notify-send";
    argv[1] = (gchar *)"-a";
    argv[2] = (gchar *)"Z96A 电源策略";
    argv[3] = (gchar *)"-u";
    argv[4] = (gchar *)urgency;
    argv[5] = (gchar *)summary;
    argv[6] = (gchar *)body;
    argv[7] = NULL;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH,
                       NULL, NULL, NULL, &error)) {
        log_msg("warning", "通知发送失败: %s", error ? error->message : "unknown");
        if (error)
            g_error_free(error);
    }
}

static gboolean lock_ready_pid(App *app, pid_t *out_pid)
{
    char buf[64];
    char *end = NULL;
    long pid;
    struct stat st;
    if (g_stat(app->lock_ready_path, &st) != 0)
        return FALSE;
    if (!read_text_file(app->lock_ready_path, buf, sizeof(buf)))
        return FALSE;
    pid = strtol(buf, &end, 10);
    if (end == buf || pid <= 0)
        return FALSE;
    if (kill((pid_t)pid, 0) != 0 && errno != EPERM)
        return FALSE;
    if (out_pid)
        *out_pid = (pid_t)pid;
    return TRUE;
}

static void session_set_locked_hint(App *app, gboolean locked)
{
    if (!app->session)
        return;
    g_dbus_proxy_call(app->session, "SetLockedHint", g_variant_new("(b)", locked),
                      G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL, NULL);
}

static void on_locker_exit(GPid pid, gint status, gpointer user_data)
{
    App *app = user_data;
    GError *error = NULL;
    if (!g_spawn_check_wait_status(status, &error)) {
        log_msg("warning", "slimlock 异常退出: %s", error ? error->message : "unknown");
        if (error)
            g_error_free(error);
    }
    if (app->locker_pid == pid)
        app->locker_pid = 0;
    app->child_watch_id = 0;
    g_spawn_close_pid(pid);
}

static gboolean spawn_locker(App *app)
{
    GError *error = NULL;
    gchar *argv[] = { (gchar *)LOCK_COMMAND, NULL };
    if (!app->actions_enabled)
        return FALSE;
    if (lock_ready_pid(app, NULL))
        return TRUE;
    if (g_get_monotonic_time() - app->rt.last_lock_attempt_us < 10 * G_USEC_PER_SEC)
        return FALSE;
    app->rt.last_lock_attempt_us = g_get_monotonic_time();
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_DO_NOT_REAP_CHILD,
                       NULL, NULL, &app->locker_pid, &error)) {
        log_msg("error", "启动 Slimlock 失败: %s", error ? error->message : "unknown");
        if (error)
            g_error_free(error);
        app->locker_pid = 0;
        return FALSE;
    }
    app->child_watch_id = g_child_watch_add(app->locker_pid, on_locker_exit, app);
    log_msg("info", "已请求锁屏，pid=%d", (int)app->locker_pid);
    return TRUE;
}

static gboolean wait_for_lock(App *app, int timeout_ms)
{
    gint64 deadline = g_get_monotonic_time() + ((gint64)timeout_ms * 1000);
    while (g_get_monotonic_time() < deadline) {
        if (lock_ready_pid(app, NULL))
            return TRUE;
        g_usleep(100000);
    }
    return FALSE;
}

static gboolean close_inhibit_fd(App *app)
{
    if (app->inhibit_fd >= 0) {
        close(app->inhibit_fd);
        app->inhibit_fd = -1;
        return TRUE;
    }
    return FALSE;
}

static void take_sleep_inhibitor(App *app)
{
    GError *error = NULL;
    GVariant *res = NULL;
    GUnixFDList *fds = NULL;
    gint index = -1;
    if (!app->login1 || app->inhibit_fd >= 0)
        return;
    res = g_dbus_proxy_call_with_unix_fd_list_sync(
        app->login1, "Inhibit",
        g_variant_new("(ssss)", "sleep", APP_NAME, "Lock before suspend", "delay"),
        G_DBUS_CALL_FLAGS_NONE, -1, NULL, &fds, NULL, &error);
    if (!res) {
        log_msg("warning", "获取 sleep inhibitor 失败: %s", error ? error->message : "unknown");
        if (error)
            g_error_free(error);
        return;
    }
    g_variant_get(res, "(h)", &index);
    app->inhibit_fd = g_unix_fd_list_get(fds, index, &error);
    if (app->inhibit_fd < 0)
        log_msg("warning", "取得 sleep inhibitor fd 失败: %s", error ? error->message : "unknown");
    if (error)
        g_error_free(error);
    g_variant_unref(res);
    if (fds)
        g_object_unref(fds);
}

static void request_sleep_delay_release(App *app)
{
    if (!lock_ready_pid(app, NULL)) {
        spawn_locker(app);
        if (!wait_for_lock(app, 4000)) {
            log_msg("error", "睡前无法确认 Slimlock 已锁定，继续释放 inhibitor");
            notify_user(app, "critical", "锁屏失败", "系统即将睡眠，但未能确认 Slimlock 已锁定");
        }
    }
    close_inhibit_fd(app);
}

static void power_action_done(GObject *source, GAsyncResult *result, gpointer data)
{
    App *app = data;
    GError *error = NULL;
    GVariant *reply = g_dbus_proxy_call_finish(G_DBUS_PROXY(source), result, &error);
    if (!reply) {
        log_msg("error", "电源操作失败: %s", error ? error->message : "unknown");
        notify_user(app, "critical", "电源操作失败", error ? error->message : "未知错误");
        g_clear_error(&error);
    } else {
        g_variant_unref(reply);
    }
}

static void request_suspend(App *app)
{
    if (!app->actions_enabled || app->cfg.auto_action != AUTO_SUSPEND || !app->login1)
        return;
    if (g_get_monotonic_time() - app->rt.last_suspend_attempt_us < 15 * G_USEC_PER_SEC)
        return;
    if (!lock_ready_pid(app, NULL)) {
        if (!spawn_locker(app) || !wait_for_lock(app, 4000)) {
            log_msg("error", "自动挂起取消: 无法确认 Slimlock 已锁定");
            g_strlcpy(app->rt.policy_state, "ERROR", sizeof(app->rt.policy_state));
            notify_user(app, "critical", "挂起已取消", "Slimlock 未能建立锁屏");
            return;
        }
    }
    app->rt.last_suspend_attempt_us = g_get_monotonic_time();
    g_strlcpy(app->rt.policy_state, "SUSPEND", sizeof(app->rt.policy_state));
    const char *action_log = g_getenv("Z96A_ACTION_LOG");
    if (action_log && *action_log) {
        g_file_set_contents(action_log, "SUSPEND\n", -1, NULL);
        return;
    }
    g_dbus_proxy_call(app->login1, "Suspend", g_variant_new("(b)", FALSE),
                      G_DBUS_CALL_FLAGS_NONE, -1, NULL, power_action_done, app);
    log_msg("info", "已请求 suspend");
}

static void cancel_critical_dialog(App *app)
{
    app->rt.critical_deadline_us = 0;
    app->rt.critical_remaining = -1;
    app->critical_dialog_attempted = FALSE;
    if (app->critical_dialog_pid > 0) {
        app->critical_dialog_cancel_pending = TRUE;
        kill(app->critical_dialog_pid, SIGTERM);
    }
}

static void clear_critical_override(App *app)
{
    app->rt.critical_override = FALSE;
    if (app->critical_override_path)
        g_unlink(app->critical_override_path);
}

static void critical_dialog_exit_cb(GPid pid, gint status, gpointer user_data)
{
    App *app = user_data;
    gboolean cancelled = app->critical_dialog_cancel_pending;
    app->critical_dialog_cancel_pending = FALSE;
    app->critical_dialog_pid = 0;
    app->critical_dialog_watch_id = 0;
    g_spawn_close_pid(pid);
    if (cancelled)
        return;
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        app->rt.critical_deadline_us = 0;
        app->rt.critical_remaining = 0;
        request_poweroff(app, TRUE);
    } else if (WIFEXITED(status) && WEXITSTATUS(status) == 2) {
        app->rt.critical_override = TRUE;
        app->rt.critical_deadline_us = 0;
        app->rt.critical_remaining = -1;
        g_file_set_contents(app->critical_override_path, "1\n", -1, NULL);
        notify_user(app, "normal", "已选择继续使用", "本次放电周期不再自动关机，请尽快连接电源");
    } else {
        log_msg("warning", "低电量对话框异常退出，保留 60 秒自动关机倒计时");
    }
}

static void spawn_critical_dialog(App *app)
{
    GError *error = NULL;
    gchar *percent = g_strdup_printf("%d", app->rt.battery_percent);
    gchar *timeout = g_strdup_printf("%d", app->cfg.critical_grace_seconds);
    gchar *argv[] = { (gchar *)CRITICAL_DIALOG, (gchar *)"--percent", percent,
                      (gchar *)"--timeout", timeout, NULL };
    if (!app->actions_enabled)
        goto out;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD,
                       NULL, NULL, &app->critical_dialog_pid, &error)) {
        log_msg("warning", "启动低电量对话框失败: %s", error ? error->message : "unknown");
        if (error)
            g_error_free(error);
        app->critical_dialog_pid = 0;
        goto out;
    }
    app->critical_dialog_watch_id = g_child_watch_add(app->critical_dialog_pid,
                                                       critical_dialog_exit_cb, app);
    log_msg("info", "已启动 20%% 低电量对话框，pid=%d", (int)app->critical_dialog_pid);
out:
    g_free(percent);
    g_free(timeout);
}

static void request_poweroff(App *app, gboolean critical)
{
    if (!app->actions_enabled)
        return;
    if (critical) {
        refresh_power(app);
        if (strcmp(app->rt.power_source, "BATTERY") != 0 || app->rt.battery_present != 1 ||
            app->rt.battery_percent < 0 ||
            app->rt.battery_percent > app->cfg.critical_percent + 2 ||
            app->rt.critical_override) {
            log_msg("warning", "低电量关机已取消：外部供电或电池状态不满足条件");
            cancel_critical_dialog(app);
            return;
        }
    } else if (app->cfg.auto_action != AUTO_POWEROFF) {
        return;
    }
    if (g_get_monotonic_time() - app->rt.last_poweroff_attempt_us < 15 * G_USEC_PER_SEC)
        return;
    app->rt.last_poweroff_attempt_us = g_get_monotonic_time();
    g_strlcpy(app->rt.policy_state, "POWEROFF", sizeof(app->rt.policy_state));
    const char *action_log = g_getenv("Z96A_ACTION_LOG");
    if (action_log && *action_log) {
        g_file_set_contents(action_log, "POWEROFF\n", -1, NULL);
        return;
    }
    if (!app->login1) {
        log_msg("error", "关机请求失败：elogind 不可用");
        notify_user(app, "critical", "关机失败", "elogind 不可用");
        return;
    }
    g_dbus_proxy_call(app->login1, "PowerOff", g_variant_new("(b)", FALSE),
                      G_DBUS_CALL_FLAGS_NONE, -1, NULL, power_action_done, app);
    log_msg("warning", "%s，已请求有序关机", critical ? "电池电量严重不足" : "空闲时间已到");
}

static void process_battery_thresholds(App *app)
{
    gint64 now = g_get_monotonic_time();
    int p = app->rt.battery_percent;

    if (strcmp(app->rt.power_source, "AC") == 0) {
        cancel_critical_dialog(app);
        clear_critical_override(app);
        app->rt.warning_level = 0;
        return;
    }
    if (app->rt.battery_present != 1 || strcmp(app->rt.power_source, "BATTERY") != 0 || p < 0) {
        cancel_critical_dialog(app);
        app->rt.warning_level = 0;
        return;
    }

    if (p > app->cfg.warning_percent + 2) {
        cancel_critical_dialog(app);
        app->rt.warning_level = 0;
        return;
    }

    if (p > app->cfg.critical_percent + 2 && app->rt.critical_deadline_us > 0)
        cancel_critical_dialog(app);

    if (!app->cfg.critical_shutdown_enabled) {
        if (app->rt.critical_deadline_us > 0 || app->critical_dialog_pid > 0)
            cancel_critical_dialog(app);
        app->rt.critical_remaining = -1;
        if (p <= app->cfg.critical_percent && app->rt.warning_level < 2) {
            app->rt.warning_level = 2;
            gchar *body = g_strdup_printf("电量 %d%%，自动关机已禁用，请立即连接电源", p);
            notify_user(app, "critical", "严重低电量", body);
            g_free(body);
        }
        if (p <= 10 && app->rt.warning_level < 3) {
            app->rt.warning_level = 3;
            notify_user(app, "critical", "电量极低", "设备可能因电池耗尽而断电，请立即连接电源");
        }
        return;
    }

    if (app->rt.critical_override) {
        app->rt.critical_remaining = -1;
        if (p <= 10 && app->rt.warning_level < 3) {
            app->rt.warning_level = 3;
            gchar *body = g_strdup_printf("已选择继续使用，电量 %d%%，请立即连接电源", p);
            notify_user(app, "normal", "低电量提醒", body);
            g_free(body);
        }
        return;
    }

    if (p <= app->cfg.critical_percent) {
        if (app->rt.critical_deadline_us == 0 && !app->critical_dialog_attempted &&
            app->critical_dialog_pid == 0) {
            app->rt.warning_level = 2;
            app->rt.critical_deadline_us = now +
                ((gint64)app->cfg.critical_grace_seconds * G_USEC_PER_SEC);
            app->rt.critical_remaining = app->cfg.critical_grace_seconds;
            app->critical_dialog_attempted = TRUE;
            gchar *body = g_strdup_printf("电量 %d%%，请在对话框中确认是否关机", p);
            notify_user(app, "critical", "严重低电量", body);
            g_free(body);
            spawn_critical_dialog(app);
        }
        if (app->rt.critical_deadline_us > 0) {
            gint64 remaining_us = app->rt.critical_deadline_us - now;
            app->rt.critical_remaining = remaining_us > 0 ?
                (int)((remaining_us + G_USEC_PER_SEC - 1) / G_USEC_PER_SEC) : 0;
            if (now >= app->rt.critical_deadline_us) {
                app->rt.critical_deadline_us = 0;
                request_poweroff(app, TRUE);
            }
        }
    } else if (p <= app->cfg.warning_percent && app->rt.warning_level < 1) {
        app->rt.warning_level = 1;
        gchar *body = g_strdup_printf("电量 %d%%，请尽快连接电源", p);
        notify_user(app, "normal", "低电量", body);
        g_free(body);
    }
}

static int profile_dim(const App *app)
{
    return strcmp(app->rt.profile, "BATTERY") == 0 ? app->cfg.battery_dim : app->cfg.ac_dim;
}
static int profile_lock(const App *app)
{
    return strcmp(app->rt.profile, "BATTERY") == 0 ? app->cfg.battery_lock : app->cfg.ac_lock;
}
static int profile_suspend(const App *app)
{
    return strcmp(app->rt.profile, "BATTERY") == 0 ? app->cfg.battery_suspend : app->cfg.ac_suspend;
}
static int profile_screen_off(const App *app)
{
    return strcmp(app->rt.profile, "BATTERY") == 0 ? app->cfg.battery_screen_off : app->cfg.ac_screen_off;
}
static int profile_poweroff(const App *app)
{
    return strcmp(app->rt.profile, "BATTERY") == 0 ? app->cfg.battery_poweroff : app->cfg.ac_poweroff;
}

static void update_idle_policy(App *app, gint64 idle_ms, gboolean locked, gint64 now)
{
    gboolean activity = app->rt.previous_idle_ms >= 0 && idle_ms < app->rt.previous_idle_ms;
    app->rt.previous_idle_ms = idle_ms;
    app->rt.idle_ms = idle_ms;

    if (locked != app->rt.locked) {
        app->rt.locked = locked;
        session_set_locked_hint(app, locked);
        if (locked) {
            app->rt.locked_idle_base_ms = idle_ms;
            app->rt.locked_start_us = now;
        } else {
            app->rt.locked_idle_base_ms = 0;
            app->rt.locked_start_us = 0;
        }
    }
    gint64 effective_idle_ms = idle_ms;
    if (locked && !app->cfg.lock_input_resets_idle && app->rt.locked_start_us > 0)
        effective_idle_ms = app->rt.locked_idle_base_ms + ((now - app->rt.locked_start_us) / 1000);

    if (activity || idle_ms < 1000)
        restore_screen(app);
    else if (!locked && idle_ms >= (gint64)profile_dim(app) * 1000)
        dim_screen(app);

    if (app->dpy && app->have_display_settings) {
        int timeout = profile_screen_off(app);
        if (app->rt.screen_off && (activity || timeout == 0 || idle_ms < (gint64)timeout * 1000)) {
            DPMSForceLevel(app->dpy, DPMSModeOn);
            XFlush(app->dpy);
            app->rt.screen_off = FALSE;
        } else if (!app->rt.screen_off && timeout > 0 && idle_ms >= (gint64)timeout * 1000) {
            DPMSForceLevel(app->dpy, DPMSModeOff);
            XFlush(app->dpy);
            app->rt.screen_off = TRUE;
        }
    }

    app->rt.suspend_remaining = -1;
    app->rt.poweroff_remaining = -1;
    if (app->rt.profile_grace_until_us > now) {
        g_strlcpy(app->rt.policy_state, "GRACE", sizeof(app->rt.policy_state));
    } else {
        if (!locked && idle_ms >= (gint64)profile_lock(app) * 1000)
            spawn_locker(app);
        gboolean low_battery = strcmp(app->rt.power_source, "AC") != 0 &&
            app->rt.battery_present == 1 && app->rt.battery_percent >= 0 &&
            app->rt.battery_percent <= app->cfg.warning_percent;
        if (app->cfg.auto_action == AUTO_SUSPEND && !low_battery) {
            int remain = profile_suspend(app) - (int)(effective_idle_ms / 1000);
            if (remain < 0)
                remain = 0;
            app->rt.suspend_remaining = remain;
            if (remain == 0)
                request_suspend(app);
            g_strlcpy(app->rt.policy_state, locked ? "LOCKED" : "ACTIVE", sizeof(app->rt.policy_state));
        } else if (app->cfg.auto_action == AUTO_SUSPEND && low_battery) {
            g_strlcpy(app->rt.policy_state, "LOW_BATTERY", sizeof(app->rt.policy_state));
        } else if (app->cfg.auto_action == AUTO_POWEROFF) {
            int remain = profile_poweroff(app) - (int)(effective_idle_ms / 1000);
            app->rt.poweroff_remaining = remain > 0 ? remain : 0;
            if (remain <= 0)
                request_poweroff(app, FALSE);
            g_strlcpy(app->rt.policy_state, locked ? "LOCKED" : "ACTIVE", sizeof(app->rt.policy_state));
        } else {
            g_strlcpy(app->rt.policy_state, locked ? "LOCKED" : app->rt.dimmed ? "DIM" : "ACTIVE",
                      sizeof(app->rt.policy_state));
        }
    }
    if (app->rt.critical_deadline_us > 0)
        g_strlcpy(app->rt.policy_state, "CRITICAL", sizeof(app->rt.policy_state));
    else if (app->rt.critical_override)
        g_strlcpy(app->rt.policy_state, "OVERRIDE", sizeof(app->rt.policy_state));
    else
        app->rt.critical_remaining = -1;
}

static gboolean on_tick(gpointer data)
{
    App *app = data;
    XScreenSaverInfo *xsi = NULL;
    gint64 idle_ms = 0;

    reload_user_config(app, FALSE);
    refresh_power(app);
    process_battery_thresholds(app);

    if (app->dpy && app->xss_available) {
        xsi = XScreenSaverAllocInfo();
        if (xsi && XScreenSaverQueryInfo(app->dpy, app->root, xsi))
            idle_ms = (gint64)xsi->idle;
        if (xsi)
            XFree(xsi);
    }
    update_idle_policy(app, idle_ms, lock_ready_pid(app, NULL), g_get_monotonic_time());
    write_status(app);
    return G_SOURCE_CONTINUE;
}

static void login1_signal_cb(GDBusProxy *proxy, gchar *sender_name, gchar *signal_name,
                             GVariant *parameters, gpointer user_data)
{
    App *app = user_data;
    (void)proxy;
    (void)sender_name;
    if (g_strcmp0(signal_name, "PrepareForSleep") != 0)
        return;
    gboolean active = FALSE;
    g_variant_get(parameters, "(b)", &active);
    if (active) {
        log_msg("info", "收到 PrepareForSleep(true)");
        request_sleep_delay_release(app);
    } else {
        log_msg("info", "收到 PrepareForSleep(false)");
        app->rt.previous_idle_ms = -1;
        app->rt.profile_grace_until_us = g_get_monotonic_time() +
            (gint64)app->cfg.profile_grace_seconds * G_USEC_PER_SEC;
        take_sleep_inhibitor(app);
    }
}

static void setup_session_proxy(App *app)
{
    GError *error = NULL;
    GVariant *res;
    const char *session_id = g_getenv("XDG_SESSION_ID");
    char *path = NULL;
    if (!app->login1)
        return;
    if (session_id && *session_id) {
        res = g_dbus_proxy_call_sync(app->login1, "GetSession",
                                     g_variant_new("(s)", session_id),
                                     G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
    } else {
        res = g_dbus_proxy_call_sync(app->login1, "GetSessionByPID",
                                     g_variant_new("(u)", (guint)getpid()),
                                     G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
    }
    if (res) {
        g_variant_get(res, "(o)", &path);
        app->session = g_dbus_proxy_new_for_bus_sync(
            G_BUS_TYPE_SYSTEM, G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES,
            NULL, LOGIN1_NAME, path, SESSION_IFACE, NULL, &error);
        g_variant_unref(res);
        g_free(path);
    }
    if (!app->session)
        log_msg("warning", "无法连接 elogind session: %s", error ? error->message : "unknown");
    if (error)
        g_error_free(error);
}

static gboolean setup_login1(App *app)
{
    GError *error = NULL;
    app->login1 = g_dbus_proxy_new_for_bus_sync(
        G_BUS_TYPE_SYSTEM, G_DBUS_PROXY_FLAGS_NONE, NULL,
        LOGIN1_NAME, LOGIN1_PATH, LOGIN1_IFACE, NULL, &error);
    if (!app->login1) {
        log_msg("error", "连接 elogind 失败: %s", error ? error->message : "unknown");
        if (error)
            g_error_free(error);
        return FALSE;
    }
    g_signal_connect(app->login1, "g-signal", G_CALLBACK(login1_signal_cb), app);
    setup_session_proxy(app);
    take_sleep_inhibitor(app);
    return TRUE;
}

static void restore_and_quit(App *app)
{
    if (app->stopping)
        return;
    app->stopping = TRUE;
    restore_screen(app);
    if (app->dpy) {
        if (app->have_display_settings) {
            DPMSForceLevel(app->dpy, DPMSModeOn);
            DPMSSetTimeouts(app->dpy, app->old_dpms_standby, app->old_dpms_suspend, app->old_dpms_off);
            if (!app->old_dpms_enabled)
                DPMSDisable(app->dpy);
        }
        XSetScreenSaver(app->dpy, app->old_screen_timeout, app->old_screen_interval,
                        app->old_blanking, app->old_exposures);
        XFlush(app->dpy);
    }
    close_inhibit_fd(app);
    if (app->tick_id)
        g_source_remove(app->tick_id);
    if (app->inhibitor_retry_id)
        g_source_remove(app->inhibitor_retry_id);
    /* A daemon restart must never terminate an active screen lock. */
    if (app->critical_dialog_pid > 0) {
        app->critical_dialog_cancel_pending = TRUE;
        kill(app->critical_dialog_pid, SIGTERM);
        app->critical_dialog_pid = 0;
    }
    if (app->loop)
        g_main_loop_quit(app->loop);
}

static void signal_cb(int sig)
{
    if (g_app)
        restore_and_quit(g_app);
}

static gboolean on_inhibitor_retry(gpointer data)
{
    App *app = data;
    if (app->inhibit_fd < 0)
        take_sleep_inhibitor(app);
    return G_SOURCE_CONTINUE;
}

static gboolean init_x11(App *app)
{
    int event_base, error_base;
    app->dpy = XOpenDisplay(NULL);
    if (!app->dpy) {
        log_msg("error", "无法打开 X11 DISPLAY");
        return FALSE;
    }
    app->root = DefaultRootWindow(app->dpy);
    app->xss_available = XScreenSaverQueryExtension(app->dpy, &event_base, &error_base);
    if (!app->xss_available) {
        log_msg("error", "X11 缺少 MIT-SCREEN-SAVER 扩展");
        return FALSE;
    }
    app->xss_event_base = event_base;
    app->xss_error_base = error_base;
    XGetScreenSaver(app->dpy, &app->old_screen_timeout, &app->old_screen_interval,
                    &app->old_blanking, &app->old_exposures);
    if (DPMSCapable(app->dpy)) {
        CARD16 level;
        DPMSGetTimeouts(app->dpy, &app->old_dpms_standby, &app->old_dpms_suspend, &app->old_dpms_off);
        DPMSInfo(app->dpy, &level, &app->old_dpms_enabled);
        DPMSSetTimeouts(app->dpy, 0, 0, 0);
        DPMSEnable(app->dpy);
        app->have_display_settings = TRUE;
    } else {
        log_msg("warning", "X11 不支持 DPMS，自动关屏不可用");
    }
    XSetScreenSaver(app->dpy, 0, 0, app->old_blanking, app->old_exposures);
    XSync(app->dpy, False);
    return TRUE;
}

static void usage(const char *prog)
{
    g_printerr("用法: %s [--daemon|--once|--check-config] [--config PATH] [--user-config PATH] [--test-mode]\n", prog);
}

int main(int argc, char **argv)
{
    App app;
    GError *error = NULL;
    const char *config_path = CONFIG_PATH;
    const char *user_config_path = g_getenv("Z96A_USER_CONFIG");
    gboolean explicit_user_config = FALSE;
    int i;
    gboolean daemon_mode = TRUE;
    memset(&app, 0, sizeof(app));
    app.inhibit_fd = -1;
    app.daemon_lock_fd = -1;
    app.actions_enabled = TRUE;
    app.rt.battery_percent = -1;
    app.rt.battery_present = -1;
    app.rt.critical_remaining = -1;
    app.rt.suspend_remaining = -1;
    app.rt.poweroff_remaining = -1;
    app.rt.previous_idle_ms = -1;
    g_strlcpy(app.rt.power_source, "UNKNOWN", sizeof(app.rt.power_source));
    g_strlcpy(app.rt.profile, "AC", sizeof(app.rt.profile));
    g_strlcpy(app.rt.battery_status, "Unknown", sizeof(app.rt.battery_status));
    g_strlcpy(app.rt.policy_state, "STARTING", sizeof(app.rt.policy_state));

    for (i = 1; i < argc; i++) {
        if (g_strcmp0(argv[i], "--daemon") == 0) {
            daemon_mode = TRUE;
        } else if (g_strcmp0(argv[i], "--once") == 0) {
            app.once = TRUE;
            daemon_mode = FALSE;
        } else if (g_strcmp0(argv[i], "--check-config") == 0) {
            app.check_only = TRUE;
            daemon_mode = FALSE;
        } else if (g_strcmp0(argv[i], "--test-mode") == 0) {
            app.actions_enabled = FALSE;
        } else if (g_strcmp0(argv[i], "--config") == 0 && i + 1 < argc) {
            config_path = argv[++i];
        } else if (g_strcmp0(argv[i], "--user-config") == 0 && i + 1 < argc) {
            user_config_path = argv[++i];
            explicit_user_config = TRUE;
        } else {
            usage(argv[0]);
            return 2;
        }
    }
    app.config_path = g_strdup(config_path);
    app.user_config_path = user_config_path && *user_config_path ? g_strdup(user_config_path) :
        g_build_filename(g_get_user_config_dir(), "z96a", "power-policy.conf", NULL);
    app.power_supply_dir = g_strdup(g_getenv("Z96A_POWER_SUPPLY_DIR"));
    if (!load_config(app.config_path, &app.system_cfg, &error)) {
        log_msg("error", "配置无效 %s: %s", app.config_path, error ? error->message : "unknown");
        if (error)
            g_error_free(error);
        return 1;
    }
    app.cfg = app.system_cfg;
    if (app.check_only) {
        if (explicit_user_config) {
            gchar *contents = NULL;
            if (!g_file_get_contents(app.user_config_path, &contents, NULL, &error) ||
                !apply_user_config(contents, &app.cfg, &error)) {
                log_msg("error", "用户配置无效: %s", error ? error->message : "unknown");
                g_clear_error(&error);
                g_free(contents);
                return 1;
            }
            g_free(contents);
        }
        g_print("OK: %s\n", app.config_path);
        return 0;
    }
    reload_user_config(&app, TRUE);
    ensure_runtime_paths(&app);
    if (!app.once && !acquire_daemon_lock(&app))
        return 0;
    if (app.critical_override_path && g_file_test(app.critical_override_path, G_FILE_TEST_EXISTS))
        app.rt.critical_override = TRUE;

    refresh_power(&app);
    if (app.once) {
        const char *display = g_getenv("DISPLAY");
        if (display && *display) {
            app.dpy = XOpenDisplay(NULL);
            if (app.dpy) {
                app.root = DefaultRootWindow(app.dpy);
                XScreenSaverInfo *xsi = XScreenSaverAllocInfo();
                if (xsi && XScreenSaverQueryInfo(app.dpy, app.root, xsi))
                    app.rt.idle_ms = (gint64)xsi->idle;
                if (xsi)
                    XFree(xsi);
                XCloseDisplay(app.dpy);
                app.dpy = NULL;
            }
        }
        g_strlcpy(app.rt.policy_state, "ONCE", sizeof(app.rt.policy_state));
        write_status(&app);
        g_print("source=%s profile=%s battery=%d%% status=%s idle=%" G_GINT64_FORMAT "ms\n",
                app.rt.power_source, app.rt.profile, app.rt.battery_percent,
                app.rt.battery_status, app.rt.idle_ms);
        return 0;
    }
    if (!daemon_mode)
        return 0;

    g_app = &app;
    signal(SIGTERM, signal_cb);
    signal(SIGINT, signal_cb);
    signal(SIGHUP, signal_cb);
    if (!init_x11(&app))
        return 1;
    if (!setup_login1(&app))
        log_msg("warning", "elogind 不可用，自动 suspend/poweroff 将禁用");
    app.loop = g_main_loop_new(NULL, FALSE);
    app.tick_id = g_timeout_add_seconds(1, on_tick, &app);
    app.inhibitor_retry_id = g_timeout_add_seconds(15, on_inhibitor_retry, &app);
    on_tick(&app);
    g_main_loop_run(app.loop);

    if (app.session)
        g_object_unref(app.session);
    if (app.login1)
        g_object_unref(app.login1);
    if (app.dpy)
        XCloseDisplay(app.dpy);
    g_main_loop_unref(app.loop);
    g_free(app.config_path);
    g_free(app.user_config_path);
    g_free(app.user_config_contents);
    g_free(app.power_supply_dir);
    if (app.daemon_lock_fd >= 0)
        close(app.daemon_lock_fd);
    g_free(app.runtime_dir);
    g_free(app.status_path);
    g_free(app.lock_ready_path);
    g_free(app.lock_tmp_path);
    g_free(app.critical_override_path);
    g_app = NULL;
    return 0;
}
