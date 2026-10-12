#include <glib-unix.h>
#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <webkit/webkit.h>
#include <jsc/jsc.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/XKBlib.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/scrnsaver.h>
#include <X11/extensions/XInput2.h>
#include <X11/extensions/shape.h>
#include <sys/inotify.h>
#include <sys/eventfd.h>

/* g_signal_connect is a macro; Swift sees only functions. */
static inline unsigned long perch_connect(void *instance, const char *signal, GCallback handler, void *data) {
    return g_signal_connect_data(instance, signal, handler, data, NULL, (GConnectFlags)0);
}
