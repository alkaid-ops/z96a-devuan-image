# install/20-multimedia.sh — mpv config, default video mime types, glib schemas
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.



	install -d -m 0755 /home/user/.config/mpv
	cat > /home/user/.config/mpv/mpv.conf <<'MPVEOF'
hwdec=v4l2request
vo=gpu
gpu-context=x11egl
gpu-dumb-mode=yes
dither=no
MPVEOF
	chown -R user:user /home/user/.config/mpv
	# Use upstream mpv for zero-copy v4l2request; Celluloid's distro libmpv
	# does not expose the V4L2 Request hardware decoder, so keep it only as a fallback.
	for mime in \
		video/mp4 video/x-matroska video/webm video/x-msvideo \
		video/quicktime video/x-m4v video/mp2t video/x-flv \
		video/mpeg video/x-theora+ogg; do
		runuser -u user -- env HOME=/home/user xdg-mime default mpv.desktop "$mime" || true
	done
