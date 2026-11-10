# configure/50-lock.sh — slimlock policy and IME environment
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.


	cat > /etc/slimlock.conf <<'SLIMLOCKEOF'
# Z96A: the power-policy daemon owns screen-off timing for both desktop and lock.
dpms_standby_timeout 0
dpms_off_timeout 0
wrong_passwd_timeout 0
passwd_feedback_msg "Authentication failed"
passwd_feedback_capslock "Authentication failed (CapsLock is on)"
show_username 1
show_welcome_msg 0
tty_lock 1
bell 1
SLIMLOCKEOF
