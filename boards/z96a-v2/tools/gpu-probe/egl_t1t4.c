/* T1-T4 EGL/GLES/X11 test on RK3568 (malig52 / panfrost).
 * T1 context creation, T2 shader execution, T3 FBO readback, T4 window present.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <X11/Xlib.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

typedef unsigned int GLuint, GLenum, GLbitfield;
typedef int GLint, GLsizei;
typedef unsigned char GLubyte;
typedef void GLvoid;

extern GLuint glCreateShader(GLenum);
extern void glShaderSource(GLuint, GLsizei, const char *const *, const GLint *);
extern void glCompileShader(GLuint);
extern void glGetShaderiv(GLuint, GLenum, GLint *);
extern void glGetShaderInfoLog(GLuint, GLsizei, GLsizei *, char *);
extern GLuint glCreateProgram(void);
extern void glAttachShader(GLuint, GLuint);
extern void glLinkProgram(GLuint);
extern void glGetProgramiv(GLuint, GLenum, GLint *);
extern void glGetProgramInfoLog(GLuint, GLsizei, GLsizei *, char *);
extern void glUseProgram(GLuint);
extern void glGenVertexArrays(GLsizei, GLuint *);
extern void glBindVertexArray(GLuint);
extern void glGenFramebuffers(GLsizei, GLuint *);
extern void glBindFramebuffer(GLenum, GLuint);
extern void glGenRenderbuffers(GLsizei, GLuint *);
extern void glBindRenderbuffer(GLenum, GLuint);
extern void glRenderbufferStorage(GLenum, GLenum, GLsizei, GLsizei);
extern void glFramebufferRenderbuffer(GLenum, GLenum, GLenum, GLuint);
extern GLenum glCheckFramebufferStatus(GLenum);
extern void glViewport(GLint, GLint, GLsizei, GLsizei);
extern void glClearColor(float, float, float, float);
extern void glClear(GLbitfield);
extern void glDrawArrays(GLenum, GLint, GLsizei);
extern void glReadPixels(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);
extern void glFinish(void);
extern const GLubyte *glGetString(GLenum);
extern const GLubyte *glGetStringi(GLenum, GLuint);
extern void glGetIntegerv(GLenum, GLint *);
extern GLenum glGetError(void);

#define GL_VERSION 0x1F02
#define GL_RENDERER 0x1F01
#define GL_VENDOR 0x1F00
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#define GL_NUM_EXTENSIONS 0x821D
#define GL_FRAMEBUFFER 0x8D40
#define GL_RENDERBUFFER 0x8D41
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_RGBA8 0x8058
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_TRIANGLES 0x0004
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
#define GL_VERTEX_SHADER 0x8B31
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_TRUE 1

static const char *VS =
    "#version 300 es\n"
    "void main() {\n"
    "  vec2 p[3] = vec2[3](vec2(-1.0,-1.0), vec2(3.0,-1.0), vec2(-1.0,3.0));\n"
    "  gl_Position = vec4(p[gl_VertexID], 0.0, 1.0);\n"
    "}\n";

static const char *FS =
    "#version 300 es\n"
    "precision mediump float;\n"
    "out vec4 o;\n"
    "void main() { o = vec4(1.0, 0.5, 0.0, 1.0); }\n";

static GLuint mkprog(const char *vs, const char *fs, int *ok)
{
    GLuint v = glCreateShader(GL_VERTEX_SHADER);
    GLuint f = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(v, 1, &vs, NULL);
    glShaderSource(f, 1, &fs, NULL);
    glCompileShader(v);
    glCompileShader(f);
    GLint s = 0;
    char log[512] = {0};
    glGetShaderiv(v, GL_COMPILE_STATUS, &s);
    if (!s) { glGetShaderInfoLog(v, sizeof(log) - 1, NULL, log); printf("  VS compile FAIL: %s\n", log); *ok = 0; }
    s = 0;
    glGetShaderiv(f, GL_COMPILE_STATUS, &s);
    if (!s) { glGetShaderInfoLog(f, sizeof(log) - 1, NULL, log); printf("  FS compile FAIL: %s\n", log); *ok = 0; }
    GLuint p = glCreateProgram();
    glAttachShader(p, v);
    glAttachShader(p, f);
    glLinkProgram(p);
    s = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &s);
    if (!s) { glGetProgramInfoLog(p, sizeof(log) - 1, NULL, log); printf("  link FAIL: %s\n", log); *ok = 0; }
    return p;
}

int main(int argc, char **argv)
{
    int seconds = argc > 1 ? atoi(argv[1]) : 6;
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { printf("RESULT: T1=FAIL (no X display)\n"); return 1; }
    Window win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 40, 40, 640, 480, 0, 0, 0);
    XStoreName(dpy, win, "egl-t1t4");
    XMapWindow(dpy, win);
    XSync(dpy, False);

    EGLDisplay ed = eglGetDisplay((EGLNativeDisplayType)dpy);
    if (ed == EGL_NO_DISPLAY) { printf("RESULT: T1=FAIL (eglGetDisplay)\n"); return 1; }
    if (!eglInitialize(ed, NULL, NULL)) { printf("RESULT: T1=FAIL (eglInitialize)\n"); return 1; }
    eglBindAPI(EGL_OPENGL_ES_API);

    const EGLint cfg_attr[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLConfig cfg; EGLint n = 0;
    if (!eglChooseConfig(ed, cfg_attr, &cfg, 1, &n) || n < 1) {
        printf("RESULT: T1=FAIL (no config)\n"); return 1;
    }
    EGLNativeWindowType nw; memset(&nw, 0, sizeof(nw));
    *(Window *)&nw = win;
    EGLSurface surf = eglCreateWindowSurface(ed, cfg, nw, NULL);
    if (surf == EGL_NO_SURFACE) { printf("RESULT: T1=FAIL (window surface 0x%x)\n", eglGetError()); return 1; }

    const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext ctx = eglCreateContext(ed, cfg, EGL_NO_CONTEXT, ctx_attr);
    if (ctx == EGL_NO_CONTEXT) { printf("RESULT: T1=FAIL (context 0x%x)\n", eglGetError()); return 1; }
    if (!eglMakeCurrent(ed, surf, surf, ctx)) { printf("RESULT: T1=FAIL (makeCurrent)\n"); return 1; }

    printf("DIAG: EGL_VERSION=%s\n", eglQueryString(ed, EGL_VERSION));
    printf("DIAG: EGL_VENDOR=%s\n", eglQueryString(ed, EGL_VENDOR));
    printf("DIAG: GL_VERSION=%s\n", (const char *)glGetString(GL_VERSION));
    printf("DIAG: GL_RENDERER=%s\n", (const char *)glGetString(GL_RENDERER));
    printf("DIAG: GL_VENDOR=%s\n", (const char *)glGetString(GL_VENDOR));
    printf("DIAG: GLSL_VERSION=%s\n", (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION));
    GLint next = 0;
    glGetIntegerv(GL_NUM_EXTENSIONS, &next);
    printf("DIAG: GL_EXTENSIONS_COUNT=%d\n", next);
    const char *probe[] = {"GL_EXT_texture_storage", "GL_OES_texture_storage_multisample_2d_array",
                           "GL_EXT_texture_format_BGRA8888", "GL_EXT_sRGB", "GL_OES_rgb8_rgba8",
                           "GL_EXT_disjoint_timer_query", "GL_EXT_buffer_storage"};
    for (int i = 0; i < (int)(sizeof(probe) / sizeof(probe[0])); i++) {
        int found = 0;
        for (int k = 0; k < next && !found; k++) {
            const char *e = (const char *)glGetStringi(0x1F03 /* GL_EXTENSIONS */, k);
            if (e && !strcmp(e, probe[i])) found = 1;
        }
        printf("DIAG: ext %-46s %s\n", probe[i], found ? "yes" : "NO");
    }
    printf("RESULT: T1=OK (context created, non-robust)\n");

    int ok = 1;
    GLuint prog = mkprog(VS, FS, &ok);
    if (!ok) { printf("RESULT: T2=FAIL (shader/pipeline)\n"); return 1; }
    glUseProgram(prog);
    glGenVertexArrays(1, (GLuint[]){0});
    GLuint vao = 0;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    /* T2/T3: offscreen FBO 64x64, RGBA8, read back */
    GLuint fbo = 0, rbo = 0;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenRenderbuffers(1, &rbo);
    glBindRenderbuffer(GL_RENDERBUFFER, rbo);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, 64, 64);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rbo);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        printf("RESULT: T3=FAIL (fbo incomplete 0x%x)\n", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        return 1;
    }
    glViewport(0, 0, 64, 64);
    glClearColor(0, 0, 1, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glFinish();
    unsigned char px[64 * 64 * 4] = {0};
    glReadPixels(0, 0, 64, 64, GL_RGBA, GL_UNSIGNED_BYTE, px);
    unsigned long long sum = 0;
    for (int i = 0; i < 64 * 64 * 4; i++) sum += px[i];
    int cx = (32 * 64 + 32) * 4;
    printf("DIAG: fbo center rgba=%u,%u,%u,%u checksum=%llu\n",
           px[cx], px[cx + 1], px[cx + 2], px[cx + 3], sum);
    int t3ok = (px[cx] > 200 && px[cx + 1] > 100 && px[cx + 1] < 160 && px[cx + 2] < 40);
    printf("RESULT: T2=%s (shader executed)\n", t3ok ? "OK" : "FAIL");
    printf("RESULT: T3=%s (fbo readback)\n", t3ok ? "OK" : "FAIL");

    /* T4: render to window and present for N seconds */
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, 640, 480);
    int frames = 0, egl_err = 0;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    do {
        glClearColor(0.1f, 0.2f, 0.35f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        if (!eglSwapBuffers(ed, surf)) { egl_err = eglGetError(); break; }
        frames++;
        clock_gettime(CLOCK_MONOTONIC, &t1);
    } while ((t1.tv_sec - t0.tv_sec) < seconds);
    double el = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("DIAG: presented=%d frames in %.2fs (%.1f fps) eglErr=0x%x glErr=0x%x\n",
           frames, el, frames / el, egl_err, glGetError());
    printf("RESULT: T4=%s (window present)\n", (frames > 0 && egl_err == 0) ? "OK" : "FAIL");

    eglMakeCurrent(ed, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(ed, ctx);
    eglDestroySurface(ed, surf);
    eglTerminate(ed);
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    return 0;
}
