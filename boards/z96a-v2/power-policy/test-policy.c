/* Unit tests use only temporary power supplies and the action-log backend. */
#define main z96a_policy_program_main
#include "z96a-power-policy.c"
#undef main

static gchar *dir;

static void put(const char *relative, const char *contents)
{
    gchar *path = g_build_filename(dir, relative, NULL);
    gchar *parent = g_path_get_dirname(path);
    g_assert_cmpint(g_mkdir_with_parents(parent, 0700), ==, 0);
    g_assert_true(g_file_set_contents(path, contents, -1, NULL));
    g_free(parent);
    g_free(path);
}

static void init_app(App *app)
{
    memset(app, 0, sizeof(*app));
    app->actions_enabled = TRUE;
    app->rt.previous_idle_ms = -1;
    app->rt.battery_percent = -1;
    app->rt.critical_remaining = -1;
    app->cfg = (Config){ .ac_dim=300, .ac_lock=600, .ac_suspend=1800,
        .battery_dim=120, .battery_lock=300, .battery_suspend=900,
        .ac_screen_off=600, .battery_screen_off=300, .ac_poweroff=3600,
        .battery_poweroff=1800, .dim_percent=20, .warning_percent=30,
        .critical_percent=20, .critical_grace_seconds=60,
        .critical_shutdown_enabled=TRUE,
        .profile_grace_seconds=30, .unknown_is_ac=TRUE,
        .lock_input_resets_idle=TRUE, .auto_action=AUTO_NONE };
    app->system_cfg = app->cfg;
    app->power_supply_dir = g_build_filename(dir, "power", NULL);
    app->critical_override_path = g_build_filename(dir, "override", NULL);
    app->user_config_path = g_build_filename(dir, "user.conf", NULL);
    app->lock_ready_path = g_build_filename(dir, "lock-ready", NULL);
    g_strlcpy(app->rt.profile, "AC", sizeof(app->rt.profile));
    put("power/bat/type", "Battery\n");
    put("power/bat/present", "1\n");
    put("power/bat/capacity", "20\n");
    put("power/bat/status", "Discharging\n");
    put("power/charger/type", "USB\n");
    put("power/charger/online", "0\n");
    put("power/charger/status", "Not charging\n");
}

static void finish_app(App *app)
{
    g_free(app->power_supply_dir);
    g_free(app->critical_override_path);
    g_free(app->user_config_path);
    g_free(app->user_config_contents);
    g_free(app->lock_ready_path);
}

static void test_config(void)
{
    App app;
    Config cfg;
    GError *error = NULL;
    gchar *path = g_build_filename(dir, "system.conf", NULL);
    init_app(&app);
    put("system.conf", "[Policy]\nAutoSuspendEnabled=true\n");
    g_assert_true(load_config(path, &cfg, &error));
    g_assert_cmpint(cfg.auto_action, ==, AUTO_SUSPEND);
    put("system.conf", "[Policy]\nAutoSuspendEnabled=true\nAutoAction=none\n");
    g_assert_true(load_config(path, &cfg, &error));
    g_assert_cmpint(cfg.auto_action, ==, AUTO_NONE);
    put("user.conf", "[Policy]\nAutoAction=poweroff\nACScreenOffTimeout=120\nCriticalShutdownEnabled=false\n");
    reload_user_config(&app, TRUE);
    g_assert_cmpint(app.cfg.auto_action, ==, AUTO_POWEROFF);
    g_assert_cmpint(app.cfg.ac_screen_off, ==, 120);
    g_assert_false(app.cfg.critical_shutdown_enabled);
    put("user.conf", "[Policy]\nAutoAction=invalid\nACScreenOffTimeout=1\n");
    reload_user_config(&app, FALSE);
    g_assert_cmpint(app.cfg.auto_action, ==, AUTO_POWEROFF);
    g_assert_cmpint(app.cfg.ac_screen_off, ==, 120);
    g_assert_false(app.cfg.critical_shutdown_enabled);
    g_assert_cmpint(g_unlink(app.user_config_path), ==, 0);
    reload_user_config(&app, FALSE);
    g_assert_cmpint(app.cfg.auto_action, ==, AUTO_NONE);
    g_assert_true(app.cfg.critical_shutdown_enabled);
    g_free(path);
    finish_app(&app);
}

static void test_power_safety(void)
{
    App app;
    gchar *log = g_build_filename(dir, "actions", NULL);
    init_app(&app);
    g_setenv("Z96A_ACTION_LOG", log, TRUE);
    g_setenv("Z96A_BATTERY_PRESENT", "1", TRUE);
    refresh_power(&app);
    g_assert_cmpstr(app.rt.power_source, ==, "BATTERY");
    request_poweroff(&app, TRUE);
    g_assert_true(g_file_test(log, G_FILE_TEST_EXISTS));
    g_unlink(log);
    app.rt.last_poweroff_attempt_us = 0;
    put("power/charger/online", "1\n");
    request_poweroff(&app, TRUE);
    g_assert_cmpstr(app.rt.power_source, ==, "AC");
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    put("power/charger/online", "unknown\n");
    request_poweroff(&app, TRUE);
    g_assert_cmpstr(app.rt.power_source, ==, "UNKNOWN");
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    put("power/charger/online", "0\n");
    put("power/bat/status", "Unknown\n");
    request_poweroff(&app, TRUE);
    g_assert_cmpstr(app.rt.power_source, ==, "UNKNOWN");
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    put("power/bat/status", "Discharging\n");
    put("power/charger/status", "Charging\n");
    request_poweroff(&app, TRUE);
    g_assert_cmpstr(app.rt.power_source, ==, "UNKNOWN");
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    g_setenv("Z96A_BATTERY_PRESENT", "0", TRUE);
    put("power/charger/status", "Not charging\n");
    request_poweroff(&app, TRUE);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    g_free(log);
    finish_app(&app);
}

static void test_critical_cancel(void)
{
    App app;
    init_app(&app);
    g_setenv("Z96A_BATTERY_PRESENT", "1", TRUE);
    refresh_power(&app);
    app.critical_dialog_pid = G_MAXINT; /* No real process is signalled. */
    app.critical_dialog_attempted = TRUE;
    app.rt.critical_deadline_us = g_get_monotonic_time() + 1000000;
    put("power/charger/online", "1\n");
    refresh_power(&app);
    process_battery_thresholds(&app);
    g_assert_cmpint(app.rt.critical_deadline_us, ==, 0);
    g_assert_true(app.critical_dialog_cancel_pending);
    put("power/charger/online", "0\n");
    refresh_power(&app);
    process_battery_thresholds(&app);
    g_assert_cmpint(app.rt.critical_deadline_us, ==, 0);
    critical_dialog_exit_cb(G_MAXINT, SIGTERM, &app);
    g_assert_cmpint(app.critical_dialog_pid, ==, 0);
    finish_app(&app);
}

static void test_critical_choices(void)
{
    App app;
    gchar *log = g_build_filename(dir, "critical-actions", NULL);
    init_app(&app);
    g_setenv("Z96A_ACTION_LOG", log, TRUE);
    g_setenv("Z96A_BATTERY_PRESENT", "1", TRUE);
    refresh_power(&app);
    app.actions_enabled = FALSE; /* Do not launch the real dialog. */
    process_battery_thresholds(&app);
    g_assert_cmpint(app.rt.critical_remaining, ==, 60);
    app.actions_enabled = TRUE;
    critical_dialog_exit_cb(G_MAXINT, 2 << 8, &app);
    g_assert_true(app.rt.critical_override);
    g_assert_cmpint(app.rt.critical_deadline_us, ==, 0);
    process_battery_thresholds(&app);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    put("power/charger/online", "1\n");
    refresh_power(&app);
    process_battery_thresholds(&app);
    g_assert_false(app.rt.critical_override);
    g_assert_false(g_file_test(app.critical_override_path, G_FILE_TEST_EXISTS));
    put("power/charger/online", "0\n");
    refresh_power(&app);
    app.actions_enabled = FALSE;
    process_battery_thresholds(&app);
    app.actions_enabled = TRUE;
    app.rt.critical_deadline_us = g_get_monotonic_time() - 1;
    process_battery_thresholds(&app);
    g_assert_true(g_file_test(log, G_FILE_TEST_EXISTS));
    g_unlink(log);
    app.rt.last_poweroff_attempt_us = 0;
    put("power/charger/online", "1\n");
    critical_dialog_exit_cb(G_MAXINT, 0, &app);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    g_free(log);
    finish_app(&app);
}

static void test_critical_shutdown_disabled(void);

static void test_idle(void)
{
    App app;
    gchar *log = g_build_filename(dir, "idle-actions", NULL);
    gint64 now = g_get_monotonic_time();
    init_app(&app);
    g_setenv("Z96A_ACTION_LOG", log, TRUE);
    app.rt.locked = TRUE;
    app.cfg.auto_action = AUTO_NONE;
    update_idle_policy(&app, 4000000, TRUE, now);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    app.cfg.auto_action = AUTO_POWEROFF;
    app.rt.profile_grace_until_us = now + G_USEC_PER_SEC;
    update_idle_policy(&app, 4000000, TRUE, now);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    app.rt.profile_grace_until_us = 0;
    update_idle_policy(&app, 3599000, TRUE, now);
    g_assert_cmpint(app.rt.poweroff_remaining, ==, 1);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    update_idle_policy(&app, 3600000, TRUE, now);
    g_assert_true(g_file_test(log, G_FILE_TEST_EXISTS));
    update_idle_policy(&app, 1000, TRUE, now);
    g_assert_cmpint(app.rt.poweroff_remaining, ==, 3599);
    g_free(log);
    finish_app(&app);
}

int main(int argc, char **argv)
{
    g_test_init(&argc, &argv, NULL);
    dir = g_dir_make_tmp("z96a-policy-test-XXXXXX", NULL);
    g_assert_nonnull(dir);
    g_setenv("Z96A_NO_NOTIFY", "1", TRUE);
    g_test_add_func("/policy/config", test_config);
    g_test_add_func("/policy/power-safety", test_power_safety);
    g_test_add_func("/policy/critical-cancel", test_critical_cancel);
    g_test_add_func("/policy/critical-choices", test_critical_choices);
    g_test_add_func("/policy/critical-shutdown-disabled", test_critical_shutdown_disabled);
    g_test_add_func("/policy/idle", test_idle);
    int status = g_test_run();
    g_print("test files: %s\n", dir);
    g_free(dir);
    return status;
}
static void test_critical_shutdown_disabled(void)
{
    App app;
    gchar *log = g_build_filename(dir, "disabled-critical-actions", NULL);
    init_app(&app);
    g_setenv("Z96A_ACTION_LOG", log, TRUE);
    g_setenv("Z96A_BATTERY_PRESENT", "1", TRUE);
    app.cfg.critical_shutdown_enabled = FALSE;
    refresh_power(&app);
    process_battery_thresholds(&app);
    g_assert_cmpint(app.rt.warning_level, ==, 2);
    g_assert_cmpint(app.rt.critical_remaining, ==, -1);
    g_assert_cmpint(app.rt.critical_deadline_us, ==, 0);
    g_assert_cmpint(app.critical_dialog_pid, ==, 0);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));

    put("power/bat/capacity", "10\n");
    refresh_power(&app);
    process_battery_thresholds(&app);
    g_assert_cmpint(app.rt.warning_level, ==, 3);
    g_assert_cmpint(app.rt.critical_remaining, ==, -1);
    g_assert_cmpint(app.rt.critical_deadline_us, ==, 0);
    g_assert_cmpint(app.critical_dialog_pid, ==, 0);
    g_assert_false(g_file_test(log, G_FILE_TEST_EXISTS));
    g_free(log);
    finish_app(&app);
}

