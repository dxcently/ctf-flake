/* Beginner stack overflow. gets() overruns buf; overwrite return address to
 * call win(). Teaches: stack layout, return-address control, why gets() is
 * banned. Compiled with protections off so the lesson is the bug, not the
 * mitigations. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void win() {
    char flag[64];
    FILE *f = fopen("flag.txt", "r");
    if (!f) { puts("flag file missing; tell an admin"); return; }
    fgets(flag, sizeof(flag), f);
    printf("You win! %s\n", flag);
    fflush(stdout);
}

void vuln() {
    char buf[64];
    puts("Tell me about yourself:");
    fflush(stdout);
    gets(buf);          /* the bug */
    printf("Nice to meet you, %s\n", buf);
    fflush(stdout);
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    vuln();
    return 0;
}
