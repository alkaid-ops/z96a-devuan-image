#ifndef Z96A_LOCK_CONTROLS_H
#define Z96A_LOCK_CONTROLS_H

#include <X11/Xlib.h>
#include <X11/Xft/Xft.h>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <sys/wait.h>

/* The lock window owns the pointer grab; all commands use fixed arguments. */
class Z96ALockControls {
    int pending_ = 0;
    std::string message_;

    static std::string short_output(const std::string &text) {
        std::string clean;
        clean.reserve(std::min<size_t>(text.size(), 120));
        bool space = false;
        for (unsigned char ch : text) {
            if (clean.size() >= 120) break;
            if (ch == '\n' || ch == '\r' || ch == '\t' || ch == ' ') {
                space = true;
                continue;
            }
            if (ch < 0x20 || ch == 0x7f) continue;
            if (space && !clean.empty()) clean.push_back(' ');
            space = false;
            clean.push_back(static_cast<char>(ch));
        }
        return clean;
    }

    static int run(const char *command, std::string &output) {
        FILE *pipe = popen(command, "r");
        if (!pipe) {
            output = "无法启动命令";
            return -1;
        }
        char buf[256];
        while (fgets(buf, sizeof(buf), pipe)) {
            if (output.size() < 512)
                output += buf;
        }
        int status = pclose(pipe);
        return status != -1 && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    }

    static int button_width(unsigned int width) {
        return std::max(55, std::min(120, (static_cast<int>(width) - 48) / 4));
    }

    static void button(Display *dpy, Window win, GC gc, XftDraw *draw,
                       XftFont *font, XftColor *color, int x, int y, int w,
                       const char *label) {
        XSetForeground(dpy, gc, BlackPixel(dpy, DefaultScreen(dpy)));
        XFillRectangle(dpy, win, gc, x, y, w, 32);
        XSetForeground(dpy, gc, WhitePixel(dpy, DefaultScreen(dpy)));
        XDrawRectangle(dpy, win, gc, x, y, w, 32);
        XGlyphInfo extents;
        XftTextExtentsUtf8(dpy, font, reinterpret_cast<const FcChar8 *>(label),
                           static_cast<int>(std::string(label).size()), &extents);
        XftDrawStringUtf8(draw, color, font, x + (w - extents.xOff) / 2,
                          y + 22, reinterpret_cast<const FcChar8 *>(label),
                          static_cast<int>(std::string(label).size()));
    }

public:
    void draw(Display *dpy, Window win, XftFont *font, XftColor *color,
              int vx, int vy, unsigned int width, unsigned int height) {
        if (!font || height < 220 || width < 280)
            return;
        const int bw = button_width(width), gap = 8;
        const int x = vx + (static_cast<int>(width) - (4 * bw + 3 * gap)) / 2;
        const int y = vy + static_cast<int>(height) - 160;
        GC gc = XCreateGC(dpy, win, 0, nullptr);
        XftDraw *draw = XftDrawCreate(dpy, win, DefaultVisual(dpy, DefaultScreen(dpy)),
                                     DefaultColormap(dpy, DefaultScreen(dpy)));
        if (!gc || !draw) {
            if (gc) XFreeGC(dpy, gc);
            if (draw) XftDrawDestroy(draw);
            return;
        }
        XSetForeground(dpy, gc, BlackPixel(dpy, DefaultScreen(dpy)));
        XFillRectangle(dpy, win, gc, x - 4, y - 30, 4 * bw + 3 * gap + 8, 120);
        if (pending_) {
            const char *question = pending_ == 1 ? "确认关机？" : pending_ == 2 ?
                "确认睡眠？可能无法唤醒" : "确认重启？";
            XftDrawStringUtf8(draw, color, font, x, y - 7,
                              reinterpret_cast<const FcChar8 *>(question),
                              static_cast<int>(std::string(question).size()));
            button(dpy, win, gc, draw, font, color, x, y, bw, "取消");
            button(dpy, win, gc, draw, font, color, x + bw + gap, y, bw, "确认");
        } else {
            static const char *labels[] = {"音量 -", "音量 +", "亮度 -", "亮度 +"};
            for (int i = 0; i < 4; ++i)
                button(dpy, win, gc, draw, font, color, x + i * (bw + gap), y, bw, labels[i]);
            static const char *actions[] = {"关机", "睡眠", "重启"};
            for (int i = 0; i < 3; ++i)
                button(dpy, win, gc, draw, font, color, x + i * (bw + gap), y + 42, bw, actions[i]);
            if (!message_.empty())
                XftDrawStringUtf8(draw, color, font, x, y - 7,
                                  reinterpret_cast<const FcChar8 *>(message_.c_str()),
                                  static_cast<int>(message_.size()));
        }
        XftDrawDestroy(draw);
        XFreeGC(dpy, gc);
        XFlush(dpy);
    }

    bool click(int px, int py, int vx, int vy, unsigned int width, unsigned int height) {
        if (height < 220 || width < 280) return false;
        const int bw = button_width(width), gap = 8;
        const int x = vx + (static_cast<int>(width) - (4 * bw + 3 * gap)) / 2;
        const int y = vy + static_cast<int>(height) - 160;
        const int rel = px - x;
        if (rel < 0) return false;
        const int index = rel / (bw + gap);
        if (index > 3 || rel % (bw + gap) > bw) return false;
        if (pending_) {
            if (py < y || py > y + 32 || index > 1) return false;
            int action = pending_;
            pending_ = 0;
            if (index == 0) {
                message_.clear();
                return true;
            }
            const char *test_log = getenv("Z96A_LOCK_ACTION_LOG");
            if (test_log && *test_log) {
                FILE *f = fopen(test_log, "a");
                if (f) {
                    fprintf(f, "%s\n", action == 1 ? "poweroff" : action == 2 ? "suspend" : "reboot");
                    fclose(f);
                }
                message_ = "测试动作已记录";
                return true;
            }
            const char *command = action == 1 ?
                "/usr/bin/timeout 5 /usr/bin/loginctl --no-ask-password poweroff 2>&1" : action == 2 ?
                "/usr/bin/timeout 5 /usr/bin/loginctl --no-ask-password suspend 2>&1" :
                "/usr/bin/timeout 5 /usr/bin/loginctl --no-ask-password reboot 2>&1";
            std::string output;
            if (run(command, output) != 0) {
                output = short_output(output);
                message_ = "电源操作失败：" + (output.empty() ? std::string("授权或服务不可用") : output);
            }
            else
                message_.clear();
            return true;
        }
        if (py >= y && py <= y + 32) {
            static const char *commands[] = {
                "/usr/local/bin/z96a-hotkey volume-down 2>&1",
                "/usr/local/bin/z96a-hotkey volume-up 2>&1",
                "/usr/local/bin/z96a-hotkey brightness-down 2>&1",
                "/usr/local/bin/z96a-hotkey brightness-up 2>&1"};
            std::string output;
            if (run(commands[index], output) != 0)
                message_ = "调节失败：" + short_output(output);
            else
                message_.clear();
            return true;
        }
        if (py >= y + 42 && py <= y + 74 && index < 3) {
            pending_ = index + 1;
            message_.clear();
            return true;
        }
        return false;
    }
};
#endif
