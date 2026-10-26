/* Known-answer probe for ec_glob(): prints "<n> <expected> <got> <pattern> <string>" per case. */
#include <stdio.h>

#include "ec_glob.h"

static const struct {
    const char *pattern;
    const char *string;
    int expect;
} cases[] = {
    {"*.c", "foo.c", 0},
    {"*.c", "foo.h", EC_GLOB_NOMATCH},
    {"*.c", "a/foo.c", EC_GLOB_NOMATCH},
    {"**.c", "a/b/foo.c", 0},
    {"a/**/b", "a/x/y/b", 0},
    {"a/**/b", "a/x/y/c", EC_GLOB_NOMATCH},
    {"{a,b}.txt", "b.txt", 0},
    {"{a,b}.txt", "c.txt", EC_GLOB_NOMATCH},
    {"{1..5}", "3", 0},
    {"{1..5}", "7", EC_GLOB_NOMATCH},
    {"[abc].x", "b.x", 0},
    {"[!abc].x", "b.x", EC_GLOB_NOMATCH},
    {"[!abc].x", "d.x", 0},
    {"[a-c]x", "bx", 0},
    {"?.x", "a.x", 0},
    {"?.x", "ab.x", EC_GLOB_NOMATCH},
    {"\\*x", "*x", 0},
    {"\\*x", "ax", EC_GLOB_NOMATCH},
    {"{a,b", "{a,b", 0},
};

int main(void)
{
    int bad = 0;
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int got = ec_glob(cases[i].pattern, cases[i].string);
        printf("%u %d %d %s %s\n", i, cases[i].expect, got, cases[i].pattern, cases[i].string);
        if (got != cases[i].expect)
            bad++;
    }
    printf("ec_glob kat mismatches=%d\n", bad);
    return bad != 0;
}
