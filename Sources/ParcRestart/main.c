// Copyright 2026 Parc contributors.
// Wait for the original application process, then ask Launch Services to reopen
// its bundle. No Chromium, shell interpolation, Apple Events or polling process.
#include <sys/event.h>
#include <sys/time.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double monotonic_seconds(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0;
  return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}

int main(int argc, char **argv) {
  if (argc != 3 && argc != 5) return 64;
  char *end = NULL;
  errno = 0;
  const long owner = strtol(argv[1], &end, 10);
  if (errno || !end || *end || owner <= 1 || owner > INT_MAX ||
      (pid_t)owner != getppid() || argv[2][0] != '/' ||
      (argc == 5 && (strcmp(argv[3], "--parc-profile") || argv[4][0] != '/')))
    return 64;

  const int queue = kqueue();
  if (queue < 0) return 71;
  struct kevent changes[2];
  EV_SET(&changes[0], (uintptr_t)owner, EVFILT_PROC, EV_ADD | EV_ENABLE,
         NOTE_EXIT, 0, NULL);
  EV_SET(&changes[1], STDIN_FILENO, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
  if (kevent(queue, changes, 2, NULL, 0, NULL) < 0) return 71;
  if (write(STDOUT_FILENO, "READY\n", 6) != 6) return 74;
  close(STDOUT_FILENO);

  const double deadline = monotonic_seconds() + 300;
  char command[16] = {0};
  size_t used = 0;
  bool armed = false;
  bool exited = false;
  for (;;) {
    const double remaining = deadline - monotonic_seconds();
    if (remaining <= 0) return 75;
    struct timespec timeout = {(time_t)remaining,
        (long)((remaining - (time_t)remaining) * 1000000000)};
    struct kevent events[2];
    const int count = kevent(queue, NULL, 0, events, 2, &timeout);
    if (count < 0) { if (errno == EINTR) continue; return 71; }
    if (count == 0) return 75;
    // Consume commands before acting on NOTE_EXIT when both arrive together.
    for (int index = 0; index < count; ++index) {
      if (events[index].flags & EV_ERROR) return 71;
      if (events[index].filter == EVFILT_PROC) exited = true;
      if (events[index].filter != EVFILT_READ) continue;
      char input[32];
      const ssize_t size = read(STDIN_FILENO, input, sizeof(input));
      if (size < 0) { if (errno == EINTR) continue; return 74; }
      if (size == 0) {
        struct kevent remove;
        EV_SET(&remove, STDIN_FILENO, EVFILT_READ, EV_DELETE, 0, 0, NULL);
        (void)kevent(queue, &remove, 1, NULL, 0, NULL);
        if (!armed || used) return 0;
        continue;
      }
      for (ssize_t byte = 0; byte < size; ++byte) {
        if (input[byte] == '\n') {
          command[used] = 0;
          if (!strcmp(command, "CANCEL")) return 0;
          if (strcmp(command, "RESTART") || armed) return 64;
          armed = true; used = 0;
        } else {
          if (used == sizeof(command) - 1) return 64;
          command[used++] = input[byte];
        }
      }
    }
    if (exited) {
      // A parent that vanished before authorizing restart must never relaunch.
      if (!armed) return 0;
      close(queue);
      if (argc == 5)
        execl("/usr/bin/open", "open", "-n", "-a", argv[2], "--args",
              argv[3], argv[4], (char *)NULL);
      else
        execl("/usr/bin/open", "open", "-n", "-a", argv[2], (char *)NULL);
      return 71;
    }
  }
}
