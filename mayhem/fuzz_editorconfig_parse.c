/*
 * In-process libFuzzer harness for editorconfig_parse().
 * Input: <1 byte: version selector>\n<relative file name>\n<.editorconfig contents>.
 * The contents are written to a private scratch dir under $TMPDIR and parsed for <dir>/<file name>.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <editorconfig/editorconfig.h>

static char scratch[4096];
static char conf_path[4200];

static int init_scratch(void)
{
    const char *tmp = getenv("TMPDIR");
    if (tmp == NULL || *tmp == '\0')
        tmp = "/tmp";
    if (snprintf(scratch, sizeof(scratch), "%s/ecfuzzXXXXXX", tmp) >= (int)sizeof(scratch))
        return -1;
    if (mkdtemp(scratch) == NULL)
        return -1;
    snprintf(conf_path, sizeof(conf_path), "%s/.editorconfig", scratch);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    static int ready = 0;
    if (!ready) {
        if (init_scratch() != 0)
            abort();
        ready = 1;
    }

    if (size < 3 || data[1] != '\n')
        return -1;
    const uint8_t *name = data + 2;
    const uint8_t *nl = memchr(name, '\n', size - 2);
    if (nl == NULL)
        return -1;
    size_t name_len = (size_t)(nl - name);
    const uint8_t *conf = nl + 1;
    size_t conf_len = size - (size_t)(conf - data);

    FILE *f = fopen(conf_path, "wb");
    if (f == NULL)
        abort();
    if (conf_len > 0 && fwrite(conf, 1, conf_len, f) != conf_len)
        abort();
    fclose(f);

    char *full = malloc(strlen(scratch) + 1 + name_len + 1);
    if (full == NULL)
        return 0;
    sprintf(full, "%s/", scratch);
    memcpy(full + strlen(scratch) + 1, name, name_len);
    full[strlen(scratch) + 1 + name_len] = '\0';

    editorconfig_handle h = editorconfig_handle_init();
    if (h != NULL) {
        if (data[0] != 0)
            editorconfig_handle_set_version(h, 0, data[0] % 14, 0);
        if (editorconfig_parse(full, h) == 0) {
            int n = editorconfig_handle_get_name_value_count(h);
            for (int i = 0; i < n; i++) {
                const char *k, *v;
                editorconfig_handle_get_name_value(h, i, &k, &v);
                if (k == NULL || v == NULL)
                    abort();
                (void)(strlen(k) + strlen(v));
            }
        }
        editorconfig_handle_destroy(h);
    }
    free(full);
    return 0;
}
