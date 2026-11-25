#include "gl_context_fix.h"

#include <epoxy/egl.h>
#include <gtk/gtk.h>

// The engine's widget that renders a view with OpenGL on X11. Wayland and the
// software renderer use other types, which are left alone.
static const char *const kRendererTypeName = "FlViewRendererOpenGL";

static void (*engine_realize)(GtkWidget *widget) = nullptr;
static void (*engine_finalize)(GObject *object) = nullptr;

// Releases the EGL context the engine left current on this thread, if any.
static void release_egl_context()
{
  if (eglGetCurrentContext() != EGL_NO_CONTEXT)
  {
    eglMakeCurrent(eglGetCurrentDisplay(), EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
  }
}

// Realizing creates the view's compositor.
static void realize_with_released_contexts(GtkWidget *widget)
{
  gdk_gl_context_clear_current();
  engine_realize(widget);
  release_egl_context();
}

// Finalizing releases it.
static void finalize_with_released_contexts(GObject *object)
{
  gdk_gl_context_clear_current();
  engine_finalize(object);
  release_egl_context();
}

void gl_context_fix_install()
{
  static gboolean installed = FALSE;
  const GType type = g_type_from_name(kRendererTypeName);
  if (installed || type == 0)
  {
    return;
  }
  installed = TRUE;

  // The class is deliberately never unreferenced, so the overrides stay.
  gpointer klass = g_type_class_ref(type);
  GtkWidgetClass *widget_class = GTK_WIDGET_CLASS(klass);
  engine_realize = widget_class->realize;
  widget_class->realize = realize_with_released_contexts;
  GObjectClass *object_class = G_OBJECT_CLASS(klass);
  engine_finalize = object_class->finalize;
  object_class->finalize = finalize_with_released_contexts;
}
