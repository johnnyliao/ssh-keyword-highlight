# ssh-keyword-highlight

讓 Linux / WSL 終端機的 SSH 輸出像 MobaXterm 一樣自動替關鍵字上色：`ERROR`、`failed` 顯示紅色，`WARN` 顯示黃色，`OK`、`healthy` 顯示綠色，IP 位址也會另外上色。

底層使用 [ChromaTerm](https://github.com/hSaria/ChromaTerm)（`ct`）。這個 repo 只提供一支一鍵安裝腳本，負責：

1. 安裝 ChromaTerm 和它的相依套件
2. 修補 ChromaTerm 0.10.7 在 Python 3.14 上的 crash（見下方說明）
3. 在 ChromaTerm 內建規則之前，加上一組常用的額外規則
4. 在 `~/.bashrc`（有 `~/.zshrc` 的話也會加）加上 `alias ssh='ct ssh'`

## 安裝

需求：Debian / Ubuntu 系的 Linux 或 WSL，並且已安裝 `python3`。

```bash
git clone https://github.com/johnnyliao/ssh-keyword-highlight.git
cd ssh-keyword-highlight
bash install.sh
```

裝完後開一個新的 shell，或執行 `source ~/.bashrc`，就可以開始使用。

腳本可以重複執行，已經完成的步驟會自動跳過。一般使用者和 root 都能裝：一般使用者會裝在 `~/.local`（需要 `sudo` 才能用 apt 安裝相依套件），root 會裝在系統目錄。

### 連不到 PyPI 的情況（公司有 TLS 攔截的 proxy）

如果 `pip` 出現 `CERTIFICATE_VERIFY_FAILED`，可以改在連得到外網的機器上下載套件檔（例如 Windows）：

```bash
pip download chromaterm --no-deps -d .
```

把下載到的 `chromaterm-x.y.z-py3-none-any.whl` 複製過來，指定給安裝腳本：

```bash
CHROMATERM_WHEEL=./chromaterm-0.10.7-py3-none-any.whl bash install.sh
```

相依套件 `psutil`、`PyYAML` 會透過 apt 安裝。Ubuntu 預設的套件來源走 http，不會受到 TLS 攔截影響。

## 使用

照常使用 `ssh` 就會自動上色：

```bash
ssh user@host
```

| 情況 | 用法 |
|---|---|
| 不想上色，使用原本的 ssh | `\ssh user@host` |
| 其他指令也要上色 | 在指令前面加 `ct`，例如 `ct journalctl -f` |
| 對管線（pipe）上色 | `tail -f app.log \| ct` |

上色只會套用在連線之後的新輸出。`vim`、`top` 這類全螢幕程式如果畫面上剛好出現關鍵字，也會被上色。

## 上色規則

ChromaTerm 內建的規則會替 IP、MAC、URL、日期、時間、數字，以及常見的好字眼、壞字眼上色。安裝腳本會在這些規則之前，加上以下額外規則：

| 顏色 | 關鍵字 |
|---|---|
| 紅色 | `exception`、`fatal`、`refused`、`unhealthy`、`killed`、`panic`、`critical`、`traceback`、`crash`、`abort`、`missing`、`oom`、`HTTP 5xx`（粗體） |
| 黃色 | `warn`、`deprecated`、`restarting`、`retry`、`skip`、`HTTP 4xx` |
| 綠色 | `healthy`、`acknowledged`、`green`、`done`、`completed`、`HTTP 2xx` |
| 紫色 | IPv4 位址（含 `/24` 這類網段），跟 MobaXterm 一樣 |
| 青色 | `info`、`information`、`notice`、`debug`、`Last login`，以及前面有空白的 `--長參數`（例如 `--upgradable`） |

`--長參數` 只比對雙減號，所以 `ls -l` 輸出裡的 `-rw-r--r--` 這類權限字串不會被誤判。

規則檔位於 `~/.chromaterm.yml`，存檔後就會生效。安裝腳本加的規則放在 `# >>> ssh-keyword-highlight >>>` 和 `# <<< ssh-keyword-highlight <<<` 之間，重跑腳本時只會更新這一段，其他自訂的規則不受影響。

安裝前的原始規則檔會備份成 `~/.chromaterm.yml.orig`。

## Python 3.14 的修補

ChromaTerm 0.10.7（截至撰寫時的最新版）在 Python 3.14 上一執行互動式程式（例如 `ct ssh`）就會 crash：

```
SystemError: buffer overflow
```

原因是它用 `ioctl(TIOCGWINSZ)` 讀取終端機大小時只給了 4 bytes 的 buffer，但 `struct winsize` 實際是 8 bytes。舊版 Python 不會檢查這件事，3.14 改成會直接報錯。

安裝腳本會把 `chromaterm/platform/unix.py` 裡的 `'0000'` 改成 `bytes(8)`，原檔備份成 `unix.py.orig`。ChromaTerm 修正這個問題之後，腳本會偵測到不需要修補，自動跳過。

**注意：** 重新安裝或升級 ChromaTerm 會蓋掉這個修補，屆時再執行一次 `bash install.sh` 即可。

## 解除安裝

```bash
sed -i '/# ssh-keyword-highlight/d' ~/.bashrc ~/.zshrc 2>/dev/null
mv ~/.chromaterm.yml.orig ~/.chromaterm.yml    # 或直接刪除 ~/.chromaterm.yml
python3 -m pip uninstall chromaterm            # 系統受 PEP 668 保護時加上 --break-system-packages
```
