/* In-process libFuzzer harness for ec_glob(): input is "<glob pattern>\n<path string>". */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "ec_glob.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    const uint8_t *nl = memchr(data, '\n', size);
    if (nl == NULL)
        return -1;

    size_t plen = (size_t)(nl - data);
    size_t slen = size - plen - 1;

    char *pattern = malloc(plen + 1);
    char *string = malloc(slen + 1);
    if (pattern == NULL || string == NULL) {
        free(pattern);
        free(string);
        return 0;
    }
    memcpy(pattern, data, plen);
    pattern[plen] = '\0';
    memcpy(string, nl + 1, slen);
    string[slen] = '\0';

    (void)ec_glob(pattern, string);

    free(pattern);
    free(string);
    return 0;
}
