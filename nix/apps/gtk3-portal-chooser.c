/* gtk3-portal-chooser: GTK 3 apps that build their own GtkFileChooserDialog
 * (LibreOffice) get the desktop's file dialog (the FileChooser portal:
 * grove's, on hearth) instead, with their extra controls in it.
 *
 * GTK 3 only sends GtkFileChooserNative to the portal (GTK_USE_PORTAL=1);
 * an app that makes a GtkFileChooserDialog and runs it with gtk_dialog_run
 * always got GTK's own dialog. Preloaded (LD_PRELOAD), this takes over
 * gtk_dialog_run for file chooser dialogs: it makes a GtkFileChooserNative
 * with the dialog's title, action, folder, name, filters and current
 * filter, and the dialog's extra widget's visible, sensitive check boxes
 * and combo boxes as portal "choices"; runs it; then puts the chosen filter
 * and choices back into the dialog and answers the app's
 * gtk_file_chooser_get_{uri,uris,file,files,filename,filenames,
 * current_folder*} for that dialog with what was chosen.
 *
 * It links to nothing: GTK is looked up when a dialog runs, so the
 * library is harmless in an app's non-GTK helper processes, which inherit
 * LD_PRELOAD. HEARTH_GTK3_CHOOSER=0 turns it off.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <gtk/gtk.h>

#define SYM(ret, name, args) \
    static ret(*p_##name) args; \
    if (!p_##name) p_##name = (ret(*) args)dlsym(RTLD_DEFAULT, #name)
#define NEXT(ret, name, args) \
    static ret(*n_##name) args; \
    if (!n_##name) n_##name = (ret(*) args)dlsym(RTLD_NEXT, #name)

static const char *KEY = "hearth-portal-chooser";

typedef struct {
    GSList *files; /* GFile*, owned */
    GFile *folder;
} Chosen;

static void chosen_free(gpointer p)
{
    Chosen *c = p;
    g_slist_free_full(c->files, g_object_unref);
    if (c->folder) g_object_unref(c->folder);
    g_free(c);
}

static int debug(void)
{
    static int d = -1;
    if (d < 0) d = getenv("HEARTH_GTK3_CHOOSER_DEBUG") != NULL;
    return d;
}
#define DBG(...) do { if (debug()) g_printerr("gtk3-portal-chooser: " __VA_ARGS__); } while (0)

static int enabled(void)
{
    const char *e = getenv("HEARTH_GTK3_CHOOSER");
    return !(e && strcmp(e, "0") == 0);
}

/* (type checks by name: GTK's own *_get_type symbols are looked up.) */
static gboolean is_a(gpointer obj, const char *type_getter)
{
    GType (*get)(void) = (GType(*)(void))dlsym(RTLD_DEFAULT, type_getter);
    return obj && get && g_type_check_instance_is_a((GTypeInstance *)obj, get());
}

typedef struct {
    GPtrArray *widgets; /* GtkWidget* in choice order */
} Walk;

static void walk(GtkWidget *w, Walk *acc);

static void walk_child(GtkWidget *w, gpointer data) { walk(w, data); }

static void walk(GtkWidget *w, Walk *acc)
{
    SYM(gboolean, gtk_widget_get_visible, (GtkWidget *));
    SYM(gboolean, gtk_widget_is_sensitive, (GtkWidget *));
    SYM(void, gtk_container_foreach, (GtkContainer *, GtkCallback, gpointer));
    if (!w) return;
    DBG("walk %s visible=%d sensitive=%d\n", G_OBJECT_TYPE_NAME(w), p_gtk_widget_get_visible(w), p_gtk_widget_is_sensitive(w));
    if (!p_gtk_widget_get_visible(w)) return;
    /* (Greyed-out ones too: LibreOffice enables Save with password and
     * Edit filter settings by the file type, which is picked in the
     * portal's dialog.) */
    if (is_a(w, "gtk_check_button_get_type") || is_a(w, "gtk_combo_box_get_type")) {
        g_ptr_array_add(acc->widgets, w);
        return;
    }
    if (is_a(w, "gtk_container_get_type"))
        p_gtk_container_foreach((GtkContainer *)w, walk_child, acc);
}

/* A combo box's rows as text (column 0 of a string model), or NULL. */
static GPtrArray *combo_rows(GtkWidget *combo)
{
    SYM(GtkTreeModel *, gtk_combo_box_get_model, (GtkComboBox *));
    SYM(gboolean, gtk_tree_model_get_iter_first, (GtkTreeModel *, GtkTreeIter *));
    SYM(gboolean, gtk_tree_model_iter_next, (GtkTreeModel *, GtkTreeIter *));
    SYM(GType, gtk_tree_model_get_column_type, (GtkTreeModel *, gint));
    SYM(gint, gtk_tree_model_get_n_columns, (GtkTreeModel *));
    SYM(void, gtk_tree_model_get, (GtkTreeModel *, GtkTreeIter *, ...));
    GtkTreeModel *m = p_gtk_combo_box_get_model((GtkComboBox *)combo);
    if (!m || p_gtk_tree_model_get_n_columns(m) < 1 || p_gtk_tree_model_get_column_type(m, 0) != G_TYPE_STRING)
        return NULL;
    GPtrArray *rows = g_ptr_array_new_with_free_func(g_free);
    GtkTreeIter it;
    if (p_gtk_tree_model_get_iter_first(m, &it)) {
        do {
            gchar *s = NULL;
            p_gtk_tree_model_get(m, &it, 0, &s, -1);
            g_ptr_array_add(rows, s ? s : g_strdup(""));
        } while (p_gtk_tree_model_iter_next(m, &it));
    }
    return rows;
}

/* A label without GTK's mnemonic marks ("_Read-only": "_" before the
 * access key, "__" for a real one). */
static char *plain_label(const char *l)
{
    GString *out = g_string_new(NULL);
    for (const char *c = l ? l : ""; *c; c++) {
        if (*c == '_') {
            if (c[1] == '_') { g_string_append_c(out, '_'); c++; }
            continue;
        }
        g_string_append_c(out, *c);
    }
    return g_string_free(out, FALSE);
}

/* The label a check box shows. */
static char *check_label(GtkWidget *w)
{
    SYM(const gchar *, gtk_button_get_label, (GtkButton *));
    SYM(gboolean, gtk_button_get_use_underline, (GtkButton *));
    const char *l = p_gtk_button_get_label((GtkButton *)w);
    return p_gtk_button_get_use_underline((GtkButton *)w) ? plain_label(l) : g_strdup(l ? l : "");
}

/* A combo box's label: the GtkLabel just before it in its box, if any. */
static char *combo_label(GtkWidget *combo)
{
    SYM(GtkWidget *, gtk_widget_get_parent, (GtkWidget *));
    SYM(GList *, gtk_container_get_children, (GtkContainer *));
    SYM(const gchar *, gtk_label_get_text, (GtkLabel *));
    SYM(GtkWidget *, gtk_label_get_mnemonic_widget, (GtkLabel *));
    GtkWidget *parent = p_gtk_widget_get_parent(combo);
    if (!parent || !is_a(parent, "gtk_container_get_type")) return g_strdup("");
    GList *kids = p_gtk_container_get_children((GtkContainer *)parent);
    char *out = NULL;
    GtkWidget *prev = NULL;
    for (GList *l = kids; l; l = l->next) {
        GtkWidget *k = l->data;
        if (is_a(k, "gtk_label_get_type") && p_gtk_label_get_mnemonic_widget((GtkLabel *)k) == combo)
            out = plain_label(p_gtk_label_get_text((GtkLabel *)k));
        if (k == combo && !out && prev && is_a(prev, "gtk_label_get_type"))
            out = plain_label(p_gtk_label_get_text((GtkLabel *)prev));
        prev = k;
    }
    g_list_free(kids);
    if (out) {
        size_t n = strlen(out);
        if (n && out[n - 1] == ':') out[n - 1] = 0;
    }
    return out ? out : g_strdup("");
}

/* Every simple "*.ext" glob in the MIME database (mime/globs2), with its
 * type: LibreOffice's filters match with a custom function, which the
 * portal can't carry, so each filter is tried on these to find patterns. */
typedef struct { char *glob; char *mime; } Glob;
static GArray *globs;

static void load_globs(void)
{
    if (globs) return;
    globs = g_array_new(FALSE, FALSE, sizeof(Glob));
    GHashTable *seen = g_hash_table_new(g_str_hash, g_str_equal);
    const char *dirs = getenv("XDG_DATA_DIRS");
    gchar **list = g_strsplit(dirs && *dirs ? dirs : "/usr/local/share:/usr/share", ":", -1);
    for (gchar **d = list; *d; d++) {
        gchar *path = g_build_filename(*d, "mime", "globs2", NULL);
        gchar *text = NULL;
        if (g_file_get_contents(path, &text, NULL, NULL)) {
            gchar **lines = g_strsplit(text, "\n", -1);
            for (gchar **l = lines; *l; l++) {
                if (**l == '#' || !**l) continue;
                gchar **f = g_strsplit(*l, ":", 4); /* weight:type:glob[:flags] */
                if (g_strv_length(f) >= 3 && g_str_has_prefix(f[2], "*.") && !strpbrk(f[2] + 2, "*?[")
                    && !g_hash_table_contains(seen, f[2])) {
                    Glob g = { g_strdup(f[2]), g_strdup(f[1]) };
                    g_array_append_val(globs, g);
                    g_hash_table_add(seen, g.glob);
                }
                g_strfreev(f);
            }
            g_strfreev(lines);
            g_free(text);
        }
        g_free(path);
    }
    g_strfreev(list);
    g_hash_table_unref(seen);
}

/* A copy of a filter the portal can carry: its own patterns and MIME types,
 * or, when it has none (a custom function), the globs it lets through. */
static GtkFileFilter *portable_filter(GtkFileFilter *orig)
{
    SYM(GVariant *, gtk_file_filter_to_gvariant, (GtkFileFilter *));
    SYM(GtkFileFilter *, gtk_file_filter_new_from_gvariant, (GVariant *));
    SYM(GtkFileFilter *, gtk_file_filter_new, (void));
    SYM(void, gtk_file_filter_set_name, (GtkFileFilter *, const gchar *));
    SYM(const gchar *, gtk_file_filter_get_name, (GtkFileFilter *));
    SYM(void, gtk_file_filter_add_pattern, (GtkFileFilter *, const gchar *));
    SYM(gboolean, gtk_file_filter_filter, (GtkFileFilter *, const GtkFileFilterInfo *));
    GVariant *v = p_gtk_file_filter_to_gvariant(orig);
    GVariant *rules = g_variant_get_child_value(v, 1);
    gboolean has_rules = g_variant_n_children(rules) > 0;
    g_variant_unref(rules);
    if (has_rules) {
        GtkFileFilter *c = p_gtk_file_filter_new_from_gvariant(v);
        g_variant_unref(v);
        return c;
    }
    g_variant_unref(v);
    GtkFileFilter *c = p_gtk_file_filter_new();
    p_gtk_file_filter_set_name(c, p_gtk_file_filter_get_name(orig));
    load_globs();
    guint n = 0;
    for (guint i = 0; i < globs->len; i++) {
        Glob *g = &g_array_index(globs, Glob, i);
        gchar *name = g_strconcat("x", g->glob + 1, NULL);
        gchar *file = g_strconcat("/tmp/", name, NULL);
        gchar *uri = g_strconcat("file:///tmp/", name, NULL);
        GtkFileFilterInfo info = {
            .contains = GTK_FILE_FILTER_FILENAME | GTK_FILE_FILTER_URI | GTK_FILE_FILTER_DISPLAY_NAME | GTK_FILE_FILTER_MIME_TYPE,
            .filename = file, .uri = uri, .display_name = name, .mime_type = g->mime,
        };
        if (p_gtk_file_filter_filter(orig, &info)) {
            p_gtk_file_filter_add_pattern(c, g->glob);
            n++;
        }
        g_free(name);
        g_free(file);
        g_free(uri);
    }
    if (!n) p_gtk_file_filter_add_pattern(c, "*");
    return c;
}

static __thread int running;

gint gtk_dialog_run(GtkDialog *dialog)
{
    NEXT(gint, gtk_dialog_run, (GtkDialog *));
    if (running || !enabled() || !is_a(dialog, "gtk_file_chooser_dialog_get_type"))
        return n_gtk_dialog_run(dialog);

    SYM(GtkFileChooserNative *, gtk_file_chooser_native_new, (const gchar *, GtkWindow *, GtkFileChooserAction, const gchar *, const gchar *));
    SYM(gint, gtk_native_dialog_run, (GtkNativeDialog *));
    SYM(void, gtk_native_dialog_set_modal, (GtkNativeDialog *, gboolean));
    SYM(const gchar *, gtk_window_get_title, (GtkWindow *));
    SYM(GtkWindow *, gtk_window_get_transient_for, (GtkWindow *));
    SYM(GtkFileChooserAction, gtk_file_chooser_get_action, (GtkFileChooser *));
    SYM(gboolean, gtk_file_chooser_get_select_multiple, (GtkFileChooser *));
    SYM(void, gtk_file_chooser_set_select_multiple, (GtkFileChooser *, gboolean));
    SYM(gboolean, gtk_file_chooser_get_do_overwrite_confirmation, (GtkFileChooser *));
    SYM(void, gtk_file_chooser_set_do_overwrite_confirmation, (GtkFileChooser *, gboolean));
    SYM(GFile *, gtk_file_chooser_get_current_folder_file, (GtkFileChooser *));
    SYM(gboolean, gtk_file_chooser_set_current_folder_file, (GtkFileChooser *, GFile *, GError **));
    SYM(gchar *, gtk_file_chooser_get_current_name, (GtkFileChooser *));
    SYM(void, gtk_file_chooser_set_current_name, (GtkFileChooser *, const gchar *));
    SYM(GSList *, gtk_file_chooser_list_filters, (GtkFileChooser *));
    SYM(void, gtk_file_chooser_add_filter, (GtkFileChooser *, GtkFileFilter *));
    SYM(GtkFileFilter *, gtk_file_chooser_get_filter, (GtkFileChooser *));
    SYM(void, gtk_file_chooser_set_filter, (GtkFileChooser *, GtkFileFilter *));
    SYM(GtkWidget *, gtk_file_chooser_get_extra_widget, (GtkFileChooser *));
    SYM(void, gtk_file_chooser_add_choice, (GtkFileChooser *, const char *, const char *, const char **, const char **));
    SYM(void, gtk_file_chooser_set_choice, (GtkFileChooser *, const char *, const char *));
    SYM(const char *, gtk_file_chooser_get_choice, (GtkFileChooser *, const char *));
    SYM(GSList *, gtk_file_chooser_get_files, (GtkFileChooser *));
    SYM(gboolean, gtk_toggle_button_get_active, (GtkToggleButton *));
    SYM(void, gtk_toggle_button_set_active, (GtkToggleButton *, gboolean));
    SYM(gint, gtk_combo_box_get_active, (GtkComboBox *));
    SYM(void, gtk_combo_box_set_active, (GtkComboBox *, gint));
    if (!p_gtk_file_chooser_native_new || !p_gtk_native_dialog_run || !p_gtk_file_chooser_add_choice)
        return n_gtk_dialog_run(dialog); /* (GTK older than 3.22) */

    GtkFileChooser *dc = (GtkFileChooser *)dialog;
    GtkFileChooserAction action = p_gtk_file_chooser_get_action(dc);
    GtkFileChooserNative *nat = p_gtk_file_chooser_native_new(
        p_gtk_window_get_title((GtkWindow *)dialog), p_gtk_window_get_transient_for((GtkWindow *)dialog), action, NULL, NULL);
    GtkFileChooser *nc = (GtkFileChooser *)nat;
    p_gtk_native_dialog_set_modal((GtkNativeDialog *)nat, TRUE);
    p_gtk_file_chooser_set_select_multiple(nc, p_gtk_file_chooser_get_select_multiple(dc));
    p_gtk_file_chooser_set_do_overwrite_confirmation(nc, p_gtk_file_chooser_get_do_overwrite_confirmation(dc));
    GFile *folder = p_gtk_file_chooser_get_current_folder_file(dc);
    if (folder) {
        p_gtk_file_chooser_set_current_folder_file(nc, folder, NULL);
        g_object_unref(folder);
    }
    if (action == GTK_FILE_CHOOSER_ACTION_SAVE) {
        gchar *name = p_gtk_file_chooser_get_current_name(dc);
        if (name && *name) p_gtk_file_chooser_set_current_name(nc, name);
        g_free(name);
    }
    /* (Copies the portal can carry; the chosen one maps back by position.) */
    GPtrArray *origs = g_ptr_array_new(), *copies = g_ptr_array_new_with_free_func(g_object_unref);
    GSList *filters = p_gtk_file_chooser_list_filters(dc);
    GtkFileFilter *cur = p_gtk_file_chooser_get_filter(dc);
    for (GSList *l = filters; l; l = l->next) {
        GtkFileFilter *c = portable_filter(l->data);
        g_object_ref_sink(c);
        g_ptr_array_add(origs, l->data);
        g_ptr_array_add(copies, c);
        p_gtk_file_chooser_add_filter(nc, c);
        if (l->data == cur) p_gtk_file_chooser_set_filter(nc, c);
    }
    g_slist_free(filters);

    Walk acc = { g_ptr_array_new() };
    walk(p_gtk_file_chooser_get_extra_widget(dc), &acc);
    for (guint i = 0; i < acc.widgets->len; i++) {
        GtkWidget *w = acc.widgets->pdata[i];
        char id[16];
        g_snprintf(id, sizeof id, "c%u", i);
        if (is_a(w, "gtk_check_button_get_type")) {
            char *label = check_label(w);
            p_gtk_file_chooser_add_choice(nc, id, label, NULL, NULL);
            g_free(label);
            p_gtk_file_chooser_set_choice(nc, id, p_gtk_toggle_button_get_active((GtkToggleButton *)w) ? "true" : "false");
        } else {
            GPtrArray *rows = combo_rows(w);
            if (!rows || rows->len == 0) {
                if (rows) g_ptr_array_unref(rows);
                continue;
            }
            const char **ids = g_new0(const char *, rows->len + 1);
            const char **labels = g_new0(const char *, rows->len + 1);
            for (guint r = 0; r < rows->len; r++) {
                ids[r] = g_strdup_printf("%u", r);
                labels[r] = rows->pdata[r];
            }
            char *label = combo_label(w);
            p_gtk_file_chooser_add_choice(nc, id, label, ids, labels);
            gint active = p_gtk_combo_box_get_active((GtkComboBox *)w);
            if (active >= 0 && (guint)active < rows->len) p_gtk_file_chooser_set_choice(nc, id, ids[active]);
            g_free(label);
            for (guint r = 0; r < rows->len; r++) g_free((char *)ids[r]);
            g_free(ids);
            g_free(labels);
            g_ptr_array_unref(rows);
        }
    }

    g_object_set_data((GObject *)dialog, KEY, NULL);
    running = 1;
    gint resp = p_gtk_native_dialog_run((GtkNativeDialog *)nat);
    running = 0;
    DBG("portal answered %d\n", resp);

    if (resp == GTK_RESPONSE_ACCEPT) {
        /* The filter first: the app may react to it (LibreOffice changes
         * the name's extension and its check boxes). */
        GtkFileFilter *f = p_gtk_file_chooser_get_filter(nc);
        guint at;
        if (f && g_ptr_array_find(copies, f, &at)) p_gtk_file_chooser_set_filter(dc, origs->pdata[at]);
        for (guint i = 0; i < acc.widgets->len; i++) {
            GtkWidget *w = acc.widgets->pdata[i];
            char id[16];
            g_snprintf(id, sizeof id, "c%u", i);
            const char *v = p_gtk_file_chooser_get_choice(nc, id);
            if (!v) continue;
            if (is_a(w, "gtk_check_button_get_type"))
                p_gtk_toggle_button_set_active((GtkToggleButton *)w, strcmp(v, "true") == 0);
            else
                p_gtk_combo_box_set_active((GtkComboBox *)w, atoi(v));
        }
        Chosen *c = g_new0(Chosen, 1);
        c->files = p_gtk_file_chooser_get_files(nc);
        if (c->files) {
            GFile *first = c->files->data;
            c->folder = (action == GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER) ? g_object_ref(first) : g_file_get_parent(first);
        }
        g_object_set_data_full((GObject *)dialog, KEY, c, chosen_free);
    }
    g_ptr_array_free(acc.widgets, TRUE);
    g_ptr_array_free(origs, TRUE);
    g_ptr_array_unref(copies);
    g_object_unref(nat);
    /* (GtkFileChooserNative answers ACCEPT or CANCEL; the app's dialog has
     * its own accept id, usually ACCEPT or OK: give the one it has.) */
    if (resp == GTK_RESPONSE_ACCEPT) {
        SYM(GtkWidget *, gtk_dialog_get_widget_for_response, (GtkDialog *, gint));
        if (p_gtk_dialog_get_widget_for_response && !p_gtk_dialog_get_widget_for_response(dialog, GTK_RESPONSE_ACCEPT)) {
            static const gint others[] = { GTK_RESPONSE_OK, GTK_RESPONSE_YES, GTK_RESPONSE_APPLY };
            for (unsigned i = 0; i < G_N_ELEMENTS(others); i++)
                if (p_gtk_dialog_get_widget_for_response(dialog, others[i])) return others[i];
        }
        return GTK_RESPONSE_ACCEPT;
    }
    return GTK_RESPONSE_CANCEL;
}

static Chosen *chosen(GtkFileChooser *fc)
{
    return fc ? g_object_get_data((GObject *)fc, KEY) : NULL;
}

GSList *gtk_file_chooser_get_files(GtkFileChooser *fc)
{
    NEXT(GSList *, gtk_file_chooser_get_files, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_files", c ? "chosen" : "own");
    if (!c) return n_gtk_file_chooser_get_files(fc);
    return g_slist_copy_deep(c->files, (GCopyFunc)g_object_ref, NULL);
}
GFile *gtk_file_chooser_get_file(GtkFileChooser *fc)
{
    NEXT(GFile *, gtk_file_chooser_get_file, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_file", c ? "chosen" : "own");
    if (!c) return n_gtk_file_chooser_get_file(fc);
    return c->files ? g_object_ref(c->files->data) : NULL;
}
GSList *gtk_file_chooser_get_uris(GtkFileChooser *fc)
{
    NEXT(GSList *, gtk_file_chooser_get_uris, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_uris", c ? "chosen" : "own");
    if (!c) return n_gtk_file_chooser_get_uris(fc);
    GSList *out = NULL;
    for (GSList *l = c->files; l; l = l->next) out = g_slist_prepend(out, g_file_get_uri(l->data));
    return g_slist_reverse(out);
}
gchar *gtk_file_chooser_get_uri(GtkFileChooser *fc)
{
    NEXT(gchar *, gtk_file_chooser_get_uri, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_uri", c ? "chosen" : "own");
    if (!c) return n_gtk_file_chooser_get_uri(fc);
    return c->files ? g_file_get_uri(c->files->data) : NULL;
}
GSList *gtk_file_chooser_get_filenames(GtkFileChooser *fc)
{
    NEXT(GSList *, gtk_file_chooser_get_filenames, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_filenames", c ? "chosen" : "own");
    if (!c) return n_gtk_file_chooser_get_filenames(fc);
    GSList *out = NULL;
    for (GSList *l = c->files; l; l = l->next) {
        gchar *p = g_file_get_path(l->data);
        if (p) out = g_slist_prepend(out, p);
    }
    return g_slist_reverse(out);
}
gchar *gtk_file_chooser_get_filename(GtkFileChooser *fc)
{
    NEXT(gchar *, gtk_file_chooser_get_filename, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_filename", c ? "chosen" : "own");
    if (!c) return n_gtk_file_chooser_get_filename(fc);
    return c->files ? g_file_get_path(c->files->data) : NULL;
}
GFile *gtk_file_chooser_get_current_folder_file(GtkFileChooser *fc)
{
    NEXT(GFile *, gtk_file_chooser_get_current_folder_file, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_current_folder_file", c ? "chosen" : "own");
    if (!c || !c->folder) return n_gtk_file_chooser_get_current_folder_file(fc);
    return g_object_ref(c->folder);
}
gchar *gtk_file_chooser_get_current_folder(GtkFileChooser *fc)
{
    NEXT(gchar *, gtk_file_chooser_get_current_folder, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_current_folder", c ? "chosen" : "own");
    if (!c || !c->folder) return n_gtk_file_chooser_get_current_folder(fc);
    return g_file_get_path(c->folder);
}
gchar *gtk_file_chooser_get_current_folder_uri(GtkFileChooser *fc)
{
    NEXT(gchar *, gtk_file_chooser_get_current_folder_uri, (GtkFileChooser *));
    Chosen *c = chosen(fc);
    DBG("%s: %s\n", "gtk_file_chooser_get_current_folder_uri", c ? "chosen" : "own");
    if (!c || !c->folder) return n_gtk_file_chooser_get_current_folder_uri(fc);
    return g_file_get_uri(c->folder);
}
