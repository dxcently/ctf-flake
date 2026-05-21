#!/usr/bin/env bash
# Generates a .env with cryptographically random secrets. Run once at setup.
set -euo pipefail
if [ -f .env ]; then
  echo "Refusing to overwrite existing .env (delete it first if you really mean to)." >&2
  exit 1
fi
rand() { head -c "$1" /dev/urandom | base64 | tr -d '/+=' | head -c "$1"; }
cat > .env <<EOL
CTFD_SECRET_KEY=$(head -c 64 /dev/urandom | base64 | tr -d '\n')
MYSQL_ROOT_PASSWORD=$(rand 32)
MYSQL_PASSWORD=$(rand 32)
EOL
chmod 600 .env
echo "PWN_FLAG=CTF{sm4sh_the_stack_f0r_fun_and_pr0fit}" >> .env
echo "WEB_FLAG=CTF{p4th_tr4versal_unl0cks_the_v4ult}" >> .env
echo "Wrote .env with fresh secrets (mode 600)."
