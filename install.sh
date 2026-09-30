#!/usr/bin/env bash
# MobaXterm 風格的 SSH 關鍵字上色：安裝 ChromaTerm、加上額外規則、把 ssh 換成 `ct ssh`。
# 可重複執行；已經做過的步驟會跳過。
#
# 用法：
#   bash install.sh
#   CHROMATERM_WHEEL=/path/to/chromaterm-x.y.z-py3-none-any.whl bash install.sh   # 連不到 PyPI 時
set -euo pipefail

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

command -v python3 >/dev/null || die "python3 not found"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

# 1. 相依套件：psutil / PyYAML 走發行版套件庫（Debian/Ubuntu），比 pip 編譯穩定
if ! python3 -c 'import psutil, yaml' 2>/dev/null; then
    if command -v apt-get >/dev/null; then
        info "installing python3-psutil python3-yaml python3-pip via apt"
        $SUDO apt-get install -y -q python3-psutil python3-yaml python3-pip >/dev/null
    else
        warn "apt-get not found; pip will try to install psutil/PyYAML itself"
    fi
fi

# 2. ChromaTerm 本體
pip_install() {
    # Ubuntu 23.04+ / Debian 12+ 的系統 Python 受 PEP 668 保護，需要 --break-system-packages
    local user_flag=""
    [ "$(id -u)" -ne 0 ] && user_flag="--user"
    local err rc
    err=$(mktemp)
    python3 -m pip install $user_flag "$@" 2>"$err" && { rm -f "$err"; return 0; }
    if grep -q "externally-managed-environment" "$err"; then
        # 重試的錯誤直接印在畫面上，不要再印第一次的 PEP 668 訊息誤導
        rm -f "$err"
        python3 -m pip install $user_flag --break-system-packages "$@"
        return $?
    fi
    cat "$err" >&2; rm -f "$err"
    return 1
}

# 用 pip 的安裝紀錄判斷，不用 import：解除安裝後若目錄裡還留著 pip 不認得的檔案（例如修補的 .orig），
# import 仍會成功，但 ct 指令已經不在了
if python3 -m pip show chromaterm >/dev/null 2>&1; then
    info "chromaterm already installed"
elif [ -n "${CHROMATERM_WHEEL:-}" ]; then
    [ -f "$CHROMATERM_WHEEL" ] || die "CHROMATERM_WHEEL not found: $CHROMATERM_WHEEL"
    info "installing chromaterm from $CHROMATERM_WHEEL"
    pip_install --no-index "$CHROMATERM_WHEEL"
else
    info "installing chromaterm from PyPI"
    pip_install chromaterm || die "pip install failed. Behind a TLS-intercepting proxy? Download the wheel elsewhere (pip download chromaterm --no-deps) and rerun with CHROMATERM_WHEEL=<file>"
fi

CT_BIN=$(command -v ct || true)
[ -z "$CT_BIN" ] && [ -x "$HOME/.local/bin/ct" ] && CT_BIN="$HOME/.local/bin/ct"
[ -n "$CT_BIN" ] || die "ct not found after install (is ~/.local/bin in PATH?)"
info "ct: $CT_BIN"

# 3. 修補 ChromaTerm <= 0.10.7 在 Python 3.14 互動模式的 crash：
#    TIOCGWINSZ 只給 4 bytes 的 buffer，struct winsize 實際是 8 bytes，3.14 會丟 SystemError: buffer overflow
UNIX_PY=$(python3 -c 'import chromaterm.platform.unix as m; print(m.__file__)' 2>/dev/null || true)
if [ -n "$UNIX_PY" ] && grep -q "TIOCGWINSZ, '0000')" "$UNIX_PY"; then
    info "patching window-size buffer in $UNIX_PY"
    W=""; [ -w "$UNIX_PY" ] || W="$SUDO"
    $W cp "$UNIX_PY" "$UNIX_PY.orig"
    $W sed -i "s/TIOCGWINSZ, '0000')/TIOCGWINSZ, bytes(8))/" "$UNIX_PY"
else
    info "window-size patch not needed"
fi

# 4. 規則：先讓 ChromaTerm 產生它的預設規則檔，再把額外規則插在最前面（比對時優先）
CFG="$HOME/.chromaterm.yml"
[ -f "$CFG" ] || echo | "$CT_BIN" >/dev/null
[ -f "$CFG" ] || die "$CFG was not created"

MARK_BEGIN="# >>> ssh-keyword-highlight >>>"
MARK_END="# <<< ssh-keyword-highlight <<<"
if grep -qF "$MARK_BEGIN" "$CFG"; then
    info "extra rules already present in $CFG, replacing them"
    sed -i "/$MARK_BEGIN/,/$MARK_END/d" "$CFG"
else
    cp "$CFG" "$CFG.orig"
fi

EXTRA_RULES=$(cat <<'YAML'
# >>> ssh-keyword-highlight >>>
- description: Extra - HTTP 5xx
  regex: \bHTTP(/\d(\.\d)?)?\s+5\d\d\b
  color: f.status-1 bold
  exclusive: true

- description: Extra - HTTP 4xx
  regex: \bHTTP(/\d(\.\d)?)?\s+4\d\d\b
  color: f.status-4
  exclusive: true

- description: Extra - HTTP 2xx
  regex: \bHTTP(/\d(\.\d)?)?\s+2\d\d\b
  color: f.status-7
  exclusive: true

- description: Extra - IPv4 (magenta, like MobaXterm)
  regex: (?<![\w.])((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)(/\d{1,2})?(?![\w.])
  color: f.type-3
  exclusive: true

- description: Extra - Bad
  regex: (?i)\b(exceptions?|fatal|refused|unhealthy|killed|panic|critical|traceback|crash(ed|es)?|abort(ed)?|missing|oom)\b
  color: f.status-1
  exclusive: true

- description: Extra - Warn
  regex: (?i)\b(warn|deprecated|restarting|retry(ing)?|skip(ped|ping)?)\b
  color: f.status-4
  exclusive: true

- description: Extra - Good
  regex: (?i)\b(healthy|acknowledged|green|done|completed)\b
  color: f.status-7
  exclusive: true

- description: Extra - Info (cyan, like MobaXterm)
  regex: (?i)\b(info(rmation)?|notice|debug|last login)\b
  color: f.type-2
  exclusive: true

- description: Extra - Long options like --upgradable
  regex: (?<=\s)--[A-Za-z][\w-]*
  color: f.type-2
  exclusive: true
# <<< ssh-keyword-highlight <<<
YAML
)
EXTRA_RULES="$EXTRA_RULES" python3 - "$CFG" <<'PY'
import os, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if "\nrules:\n" not in "\n" + text:
    sys.exit("no 'rules:' section in " + path)
text = text.replace("rules:\n", "rules:\n" + os.environ["EXTRA_RULES"] + "\n\n", 1)
open(path, "w", encoding="utf-8").write(text)
PY
python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$CFG" || die "$CFG is not valid YAML"
info "rules installed in $CFG (original: $CFG.orig)"

# 5. 互動 shell 打 ssh 時自動套 ct；要原始 ssh 用 \ssh
ALIAS_LINE="alias ssh='ct ssh'  # ssh-keyword-highlight"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    if grep -qF "# ssh-keyword-highlight" "$rc"; then
        info "alias already in $rc"
    else
        echo "$ALIAS_LINE" >> "$rc"
        info "alias added to $rc"
    fi
done

# 6. 自我檢查
SAMPLE='ERROR failed WARN ok done healthy unhealthy HTTP/1.1 500 HTTP 200 192.168.1.10'
if echo "$SAMPLE" | "$CT_BIN" | grep -q $'\033\\['; then
    echo "$SAMPLE" | "$CT_BIN"
    info "done. Open a new shell (or: source ~/.bashrc), then use ssh as usual."
else
    die "ct produced no colors; check $CFG"
fi
