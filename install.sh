#!/usr/bin/env bash
set -Eeuo pipefail

TOOLKIT_RELEASE='3.0'

# Termux Smartphone Toolkit
# Eseguire nel Termux principale, NON dentro Debian:
#   chmod +x install.sh
#   ./install.sh

if [[ -f /etc/debian_version ]]; then
  printf 'Errore: sei dentro Debian. Esegui prima "exit" e rilancia lo script da Termux.\n' >&2
  exit 1
fi

if [[ -z ${PREFIX:-} || ! -x ${PREFIX:-}/bin/pkg ]]; then
  printf 'Errore: questo installer deve essere eseguito nel Termux principale.\n' >&2
  exit 1
fi

TERMUX_HOME=${HOME:?}
BIN_DIR="$TERMUX_HOME/.local/bin"
CONFIG_DIR="$TERMUX_HOME/.config"
TOOLKIT_DIR="$CONFIG_DIR/termux-toolkit"
STAMP=$(date +%Y%m%d-%H%M%S)

printf '\nTermux Smartphone Toolkit v%s\n' "$TOOLKIT_RELEASE"
printf '\n[1/7] Aggiorno l’elenco dei pacchetti...\n'
pkg update -y

packages=(
  zsh starship zoxide fzf eza bat fastfetch
  zsh-autosuggestions zsh-syntax-highlighting
  jq curl python ffmpeg imagemagick qrencode
  nmap iproute2 procps openssh rsync termux-api proot-distro
)

available=()
missing=()
for package in "${packages[@]}"; do
  if apt-cache show "$package" >/dev/null 2>&1; then
    available+=("$package")
  else
    missing+=("$package")
  fi
done

printf '\n[2/7] Installo gli strumenti disponibili...\n'
if ((${#available[@]})); then
  pkg install -y "${available[@]}"
fi

if ((${#missing[@]})); then
  printf 'Pacchetti non disponibili nel tuo repository: %s\n' "${missing[*]}"
fi

# La build Google Play può non distribuire qrencode: usa il generatore Python.
if ! command -v qrencode >/dev/null 2>&1 && command -v python >/dev/null 2>&1; then
  printf 'Installo il supporto QR alternativo compatibile con Termux Google Play...\n'
  python -m pip install --upgrade 'qrcode[png]' || \
    printf 'Avviso: installazione del supporto QR Python non riuscita.\n' >&2
fi

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$TOOLKIT_DIR"

for file in "$TERMUX_HOME/.zshrc" "$CONFIG_DIR/starship.toml"; do
  if [[ -f "$file" ]]; then
    cp -a -- "$file" "$file.backup-$STAMP"
    printf 'Backup creato: %s\n' "$file.backup-$STAMP"
  fi
done

printf '\n[3/7] Creo il centro di controllo...\n'
cat >"$BIN_DIR/termux-hub" <<'HUB'
#!/usr/bin/env bash
set -uo pipefail

TOOLKIT_RELEASE='3.0'

export PATH="$HOME/.local/bin:$PATH"
STATE_DIR="$HOME/.cache/termux-toolkit"
CONFIG_DIR="$HOME/.config/termux-toolkit"
mkdir -p "$STATE_DIR" "$CONFIG_DIR"

GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
BLUE=$'\033[1;34m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
DIM=$'\033[2m'
RESET=$'\033[0m'

have() {
  command -v "$1" >/dev/null 2>&1
}

pause_hub() {
  printf '\n%sPremi Invio per continuare...%s' "$DIM" "$RESET"
  read -r _
}

expand_path() {
  local value=${1:-}
  if [[ $value == '~' ]]; then
    printf '%s\n' "$HOME"
  elif [[ $value == '~/'* ]]; then
    printf '%s/%s\n' "$HOME" "${value#\~/}"
  else
    printf '%s\n' "$value"
  fi
}

local_ip() {
  local value=''
  if have ip; then
    value=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
  fi
  if [[ -z $value ]] && have python; then
    value=$(python -c 'import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(("1.1.1.1",80));print(s.getsockname()[0]);s.close()' 2>/dev/null || true)
  fi
  printf '%s\n' "${value:-N/D}"
}

battery_values() {
  local data=''
  if have termux-battery-status && have jq; then
    data=$(timeout 5 termux-battery-status 2>/dev/null || true)
  fi
  if [[ -n $data ]] && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$data"; then
    printf '%s|%s|%s\n' \
      "$(jq -r '.percentage // "N/D"' <<<"$data")" \
      "$(jq -r '.status // "N/D"' <<<"$data")" \
      "$(jq -r '.temperature // "N/D"' <<<"$data")"
  else
    printf 'N/D|API non disponibile|N/D\n'
  fi
}

brief_status() {
  local battery percentage battery_status temperature free_space ip model android
  battery=$(battery_values)
  IFS='|' read -r percentage battery_status temperature <<<"$battery"
  free_space=$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
  ip=$(local_ip)
  model=$(getprop ro.product.model 2>/dev/null || true)
  android=$(getprop ro.build.version.release 2>/dev/null || true)

  printf '%s╭────────────────────────────────────────╮%s\n' "$GREEN" "$RESET"
  printf '%s│%s  %sTERMUX SMARTPHONE HUB v3%s              %s│%s\n' "$GREEN" "$RESET" "$CYAN" "$RESET" "$GREEN" "$RESET"
  printf '%s├────────────────────────────────────────┤%s\n' "$GREEN" "$RESET"
  printf '%s│%s Batteria: %-4s%%  %-12s  %4s°C %s│%s\n' "$GREEN" "$RESET" "$percentage" "$battery_status" "$temperature" "$GREEN" "$RESET"
  printf '%s│%s Rete:     %-15s Spazio: %-5s %s│%s\n' "$GREEN" "$RESET" "$ip" "${free_space:-N/D}" "$GREEN" "$RESET"
  printf '%s│%s %-20s Android %-8s %s│%s\n' "$GREEN" "$RESET" "${model:-Android}" "${android:-N/D}" "$GREEN" "$RESET"
  printf '%s╰────────────────────────────────────────╯%s\n' "$GREEN" "$RESET"
}

full_status() {
  clear
  brief_status
  printf '\n%sSistema%s\n' "$CYAN" "$RESET"
  printf '  Data:       %s\n' "$(date '+%d/%m/%Y %H:%M:%S')"
  printf '  Kernel:     %s\n' "$(uname -r)"
  printf '  Architett.: %s\n' "$(uname -m)"
  printf '  Termux:     %s\n' "${TERMUX_VERSION:-N/D}"
  printf '  Home:       %s\n' "$HOME"
  printf '  Shell:      %s\n' "${SHELL:-N/D}"
  printf '\n%sMemoria e archiviazione%s\n' "$CYAN" "$RESET"
  df -h "$HOME" 2>/dev/null | awk 'NR==1 || NR==2'
  if [[ -d $HOME/storage/shared ]]; then
    df -h "$HOME/storage/shared" 2>/dev/null | awk 'NR==2'
  fi
  if have fastfetch; then
    printf '\n%sFastfetch%s\n' "$CYAN" "$RESET"
    fastfetch
  fi
}

share_folder() {
  if ! have python; then
    printf '%sPython non è installato.%s\n' "$RED" "$RESET"
    return 1
  fi

  local default_dir="$PWD" selected port ip
  [[ -d $HOME/storage/downloads ]] && default_dir="$HOME/storage/downloads"
  printf 'Cartella da condividere [%s]: ' "$default_dir"
  read -r selected
  selected=$(expand_path "${selected:-$default_dir}")
  if [[ ! -d $selected ]]; then
    printf '%sCartella inesistente: %s%s\n' "$RED" "$selected" "$RESET"
    return 1
  fi
  printf 'Porta [8080]: '
  read -r port
  port=${port:-8080}
  if [[ ! $port =~ ^[0-9]+$ ]] || ((port < 1024 || port > 65535)); then
    printf '%sPorta non valida.%s\n' "$RED" "$RESET"
    return 1
  fi
  ip=$(local_ip)
  printf '\n%sCondivisione attiva:%s http://%s:%s\n' "$GREEN" "$RESET" "$ip" "$port"
  printf 'Cartella: %s\n' "$selected"
  printf '%sUsala solo su una rete fidata. Ctrl-C per terminare.%s\n\n' "$YELLOW" "$RESET"
  python -m http.server "$port" --bind 0.0.0.0 --directory "$selected"
}

network_check() {
  local ip gateway dns public_ip
  ip=$(local_ip)
  gateway=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
  dns=$(getprop net.dns1 2>/dev/null || true)
  printf '%sControllo rete%s\n\n' "$CYAN" "$RESET"
  printf 'IP locale:   %s\n' "$ip"
  printf 'Gateway:     %s\n' "${gateway:-N/D}"
  printf 'DNS Android: %s\n' "${dns:-N/D}"

  if have ping; then
    printf '\nConnettività Internet: '
    if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
      printf '%sOK%s\n' "$GREEN" "$RESET"
    else
      printf '%sNON RAGGIUNGIBILE%s\n' "$RED" "$RESET"
    fi
  fi

  if have curl; then
    public_ip=$(curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)
    printf 'IP pubblico: %s\n' "${public_ip:-N/D}"
    printf 'HTTPS:       '
    if curl -fsSI --max-time 6 https://example.com >/dev/null 2>&1; then
      printf '%sOK%s\n' "$GREEN" "$RESET"
    else
      printf '%sERRORE%s\n' "$RED" "$RESET"
    fi
  fi
}

lan_scan() {
  if ! have nmap; then
    printf '%snmap non è installato.%s\n' "$RED" "$RESET"
    return 1
  fi
  local ip subnet answer
  ip=$(local_ip)
  if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%sImpossibile determinare la rete locale.%s\n' "$RED" "$RESET"
    return 1
  fi
  subnet="${ip%.*}.0/24"
  printf '%sScansione dispositivi della rete %s%s\n' "$CYAN" "$subnet" "$RESET"
  printf 'Confermi che è una rete tua o autorizzata? [s/N]: '
  read -r answer
  [[ $answer == [sS] ]] || return 0
  nmap -sn "$subnet"
}

compress_video() {
  if ! have ffmpeg; then
    printf '%sffmpeg non è installato.%s\n' "$RED" "$RESET"
    return 1
  fi
  local input=${1:-} directory filename stem output
  if [[ -z $input ]]; then
    printf 'Percorso del video: '
    read -r input
  fi
  input=$(expand_path "$input")
  input=${input#\"}
  input=${input%\"}
  # Validazione sicurezza: previene path traversal
  input=$(realpath -e "$input" 2>/dev/null) || {
    printf '%sPercorso non valido o inesistente: %s%s\n' "$RED" "${1:-}" "$RESET"
    return 1
  }
  if [[ ! -f $input ]]; then
    printf '%sFile inesistente: %s%s\n' "$RED" "$input" "$RESET"
    return 1
  fi
  directory=$(dirname -- "$input")
  filename=$(basename -- "$input")
  stem=${filename%.*}
  output="$directory/${stem}_compresso.mp4"
  if [[ -e $output ]]; then
    output="$directory/${stem}_compresso-$(date +%H%M%S).mp4"
  fi
  printf '%sCompressione in corso...%s\n' "$CYAN" "$RESET"
  if ffmpeg -hide_banner -i "$input" -map 0:v:0 -map '0:a?' \
      -c:v libx264 -preset veryfast -crf 28 \
      -c:a aac -b:a 128k -movflags +faststart "$output"; then
    printf '\n%sCreato:%s %s\n' "$GREEN" "$RESET" "$output"
    have termux-notification && termux-notification --id 281 --title 'Video pronto' --content "$output" >/dev/null 2>&1 || true
  else
    printf '%sCompressione non riuscita.%s\n' "$RED" "$RESET"
    return 1
  fi
}

qr_from_clipboard() {
  if ! have qrencode && ! have qr; then
    printf '%sGeneratore QR non installato.%s\n' "$RED" "$RESET"
    return 1
  fi
  if ! have termux-clipboard-get; then
    printf '%sComando appunti non disponibile.%s\n' "$RED" "$RESET"
    return 1
  fi
  local data output_dir output
  data=$(timeout 5 termux-clipboard-get 2>/dev/null || true)
  if [[ -z $data ]]; then
    printf '%sGli appunti sono vuoti o non accessibili.%s\n' "$YELLOW" "$RESET"
    return 1
  fi
  output_dir="$HOME"
  [[ -d $HOME/storage/downloads ]] && output_dir="$HOME/storage/downloads"
  output="$output_dir/QR-$(date +%Y%m%d-%H%M%S).png"
  printf '%sQR degli appunti%s\n\n' "$CYAN" "$RESET"
  if have qrencode; then
    qrencode -t UTF8 "$data"
    qrencode -o "$output" -s 10 -m 2 "$data"
  else
    qr "$data"
    qr "$data" >"$output"
  fi
  printf '\n%sImmagine salvata:%s %s\n' "$GREEN" "$RESET" "$output"
}

clipboard_menu() {
  local choice text
  printf '%sAppunti e voce%s\n' "$CYAN" "$RESET"
  printf '  1) Mostra gli appunti\n'
  printf '  2) Copia un testo\n'
  printf '  3) Leggi gli appunti ad alta voce\n'
  printf '  0) Indietro\n'
  printf 'Scelta: '
  read -r choice
  case "$choice" in
    1) termux-clipboard-get 2>/dev/null || printf 'Appunti non disponibili.\n' ;;
    2)
      printf 'Testo: '
      read -r text
      printf '%s' "$text" | termux-clipboard-set
      printf 'Copiato.\n'
      ;;
    3)
      text=$(termux-clipboard-get 2>/dev/null || true)
      [[ -n $text ]] && termux-tts-speak "$text" || printf 'Appunti vuoti.\n'
      ;;
  esac
}

battery_check() {
  local data percentage status threshold reset_level
  local threshold_file="$CONFIG_DIR/battery-threshold"
  local marker="$STATE_DIR/battery-threshold-notified"
  have termux-battery-status || return 0
  have jq || return 0
  threshold=80
  [[ -r $threshold_file ]] && read -r threshold <"$threshold_file"
  if [[ ! $threshold =~ ^[0-9]+$ ]] || ((threshold < 1 || threshold > 100)); then
    threshold=80
  fi
  reset_level=$((threshold > 5 ? threshold - 5 : 0))
  data=$(timeout 8 termux-battery-status 2>/dev/null || true)
  [[ -n $data ]] || return 0
  percentage=$(jq -r '.percentage // 0' <<<"$data")
  status=$(jq -r '.status // "UNKNOWN"' <<<"$data")
  if [[ $percentage =~ ^[0-9]+$ ]] && ((percentage >= threshold)) && [[ $status == CHARGING || $status == FULL ]]; then
    if [[ ! -e $marker ]]; then
      termux-notification --id 80 --title "Batteria al ${threshold}%" \
        --content "Carica al ${percentage}%: soglia scelta raggiunta." \
        --priority high >/dev/null 2>&1 || true
      have termux-vibrate && termux-vibrate -d 300 >/dev/null 2>&1 || true
      touch "$marker"
    fi
  elif [[ $percentage =~ ^[0-9]+$ ]] && ((percentage < reset_level)); then
    rm -f "$marker"
  elif [[ $status != CHARGING && $status != FULL ]]; then
    rm -f "$marker"
  fi
}

battery_automation() {
  if ! have termux-job-scheduler; then
    printf '%sJob Scheduler non disponibile.%s\n' "$RED" "$RESET"
    return 1
  fi
  local choice threshold current_threshold=80
  local threshold_file="$CONFIG_DIR/battery-threshold"
  [[ -r $threshold_file ]] && read -r current_threshold <"$threshold_file"
  if [[ ! $current_threshold =~ ^[0-9]+$ ]] || ((current_threshold < 1 || current_threshold > 100)); then
    current_threshold=80
  fi
  printf '%sAvviso batteria configurabile%s\n' "$CYAN" "$RESET"
  printf 'Soglia attuale: %s%%\n\n' "$current_threshold"
  printf '  1) Attiva o modifica la soglia\n'
  printf '  2) Disattiva\n'
  printf '  3) Mostra attività pianificate\n'
  printf '  0) Indietro\n'
  printf 'Scelta: '
  read -r choice
  case "$choice" in
    1)
      printf 'Avvisami quando la batteria raggiunge [%s]: ' "$current_threshold"
      read -r threshold
      threshold=${threshold:-$current_threshold}
      if [[ ! $threshold =~ ^[0-9]+$ ]] || ((threshold < 1 || threshold > 100)); then
        printf '%sInserisci un numero compreso tra 1 e 100.%s\n' "$RED" "$RESET"
        return 1
      fi
      printf '%s\n' "$threshold" >"$threshold_file"
      rm -f "$STATE_DIR/battery-80-notified" "$STATE_DIR/battery-threshold-notified"
      termux-job-scheduler \
        --script "$HOME/.local/bin/termux-battery-check" \
        --job-id 80 --period-ms 900000 \
        --charging true --persisted true
      printf '%sAvviso attivato al %s%%.%s\n' "$GREEN" "$threshold" "$RESET"
      ;;
    2)
      termux-job-scheduler --cancel --job-id 80
      rm -f "$STATE_DIR/battery-80-notified" "$STATE_DIR/battery-threshold-notified"
      printf '%sAvviso disattivato.%s\n' "$GREEN" "$RESET"
      ;;
    3)
      printf 'Soglia configurata: %s%%\n\n' "$current_threshold"
      termux-job-scheduler --pending
      ;;
  esac
}

backup_termux() {
  local destination archive package_file
  destination="$HOME"
  [[ -d $HOME/storage/downloads ]] && destination="$HOME/storage/downloads"
  archive="$destination/termux-toolkit-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  package_file="$CONFIG_DIR/pacchetti-installati.txt"
  if have pkg; then
    pkg list-installed >"$package_file" 2>/dev/null || true
  fi

  local items=(.zshrc .config/starship.toml .config/termux-toolkit .local/bin)
  [[ -f $HOME/.zshrc.local ]] && items+=(.zshrc.local)
  if tar -czf "$archive" -C "$HOME" "${items[@]}"; then
    printf '%sBackup creato:%s %s\n' "$GREEN" "$RESET" "$archive"
    printf 'Sono esclusi volutamente chiavi SSH e altri segreti.\n'
    have termux-notification && termux-notification --id 282 --title 'Backup Termux completato' --content "$archive" >/dev/null 2>&1 || true
  else
    printf '%sBackup non riuscito.%s\n' "$RED" "$RESET"
    return 1
  fi
}

open_debian() {
  if have proot-distro; then
    proot-distro login debian
  else
    printf '%sproot-distro non è installato.%s\n' "$RED" "$RESET"
  fi
}

start_gui() {
  local display=':1' log_file="$CONFIG_DIR/termux-x11.log" session_command
  if ! have termux-x11; then
    printf '%sTermux:X11 non è installato nel terminale.%s\n' "$RED" "$RESET"
    printf 'Installa il pacchetto compatibile con la tua attuale app Termux:X11.\n'
    return 1
  fi
  if ! have xfce4-session; then
    printf '%sXFCE non è installato nel Termux principale.%s\n' "$RED" "$RESET"
    return 1
  fi

  export DISPLAY="$display"
  export XDG_RUNTIME_DIR="${TMPDIR:-$PREFIX/tmp}"
  # Validazione XDG_RUNTIME_DIR
  if [[ ! -d $XDG_RUNTIME_DIR ]]; then
    mkdir -p "$XDG_RUNTIME_DIR" || {
      printf '%sImpossibile creare XDG_RUNTIME_DIR: %s%s\n' "$RED" "$XDG_RUNTIME_DIR" "$RESET"
      return 1
    }
  fi
  chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

  if ! have pgrep || ! pgrep -x termux-x11 >/dev/null 2>&1; then
    printf '%sAvvio il server Termux:X11...%s\n' "$CYAN" "$RESET"
    nohup termux-x11 "$display" >>"$log_file" 2>&1 &
    sleep 2
  fi

  if ! have pgrep || ! pgrep -f '(^|/)xfce4-session([[:space:]]|$)' >/dev/null 2>&1; then
    printf '%sAvvio la sessione XFCE...%s\n' "$CYAN" "$RESET"
    if have dbus-launch; then
      session_command=(dbus-launch --exit-with-session xfce4-session)
    else
      session_command=(xfce4-session)
    fi
    nohup env DISPLAY="$display" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
      "${session_command[@]}" >>"$log_file" 2>&1 &
    sleep 2
  else
    printf '%sLa sessione XFCE è già attiva.%s\n' "$GREEN" "$RESET"
  fi

  if /system/bin/pm path com.termux.x11 >/dev/null 2>&1; then
    /system/bin/am start --user 0 \
      -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
  else
    /system/bin/am start --user 0 \
      -n com.termux/com.termux.x11.MainActivity >/dev/null 2>&1 || true
  fi
  printf '%sInterfaccia grafica avviata.%s\n' "$GREEN" "$RESET"
  printf 'Log: %s\n' "$log_file"
}

show_help() {
  cat <<'HELP'
Comandi rapidi:
  phone                  apre il menu
  phone-status           stato completo
  share                  condivide una cartella sulla Wi-Fi
  netcheck               controllo connessione
  lanscan                cerca dispositivi nella tua LAN
  compress-video FILE    comprime un video
  makeqr                 crea un QR dagli appunti
  battery-alert          sceglie e configura la soglia batteria
  termux-backup          salva la configurazione in Download
  gui                    avvia XFCE tramite Termux:X11
  debian                 entra in Debian
HELP
}

menu() {
  local startup=${1:-0} choice
  while true; do
    clear
    brief_status
    printf '\n%sAutomazioni%s\n' "$CYAN" "$RESET"
    printf '  %s1%s) Stato completo del telefono\n' "$GREEN" "$RESET"
    printf '  %s2%s) Appunti e lettura vocale\n' "$GREEN" "$RESET"
    printf '  %s3%s) Condividi una cartella sulla Wi-Fi\n' "$GREEN" "$RESET"
    printf '  %s4%s) Controlla Internet e rete\n' "$GREEN" "$RESET"
    printf '  %s5%s) Trova dispositivi nella tua LAN\n' "$GREEN" "$RESET"
    printf '  %s6%s) Comprimi un video\n' "$GREEN" "$RESET"
    printf '  %s7%s) Crea QR dagli appunti\n' "$GREEN" "$RESET"
    printf '  %s8%s) Avviso batteria configurabile\n' "$GREEN" "$RESET"
    printf '  %s9%s) Backup configurazione Termux\n' "$GREEN" "$RESET"
    printf '  %sG%s) Interfaccia grafica Termux:X11\n' "$BLUE" "$RESET"
    printf '  %sD%s) Entra in Debian\n' "$BLUE" "$RESET"
    printf '  %sF%s) Fastfetch\n' "$BLUE" "$RESET"
    printf '  %sH%s) Elenco comandi rapidi\n' "$BLUE" "$RESET"
    printf '  %s0%s) Vai alla shell\n\n' "$YELLOW" "$RESET"

    if [[ $startup == 1 ]]; then
      printf '%sScelta [Invio o 15s = shell]: %s' "$DIM" "$RESET"
      if ! read -r -t 15 choice; then
        choice=0
        printf '\n'
      fi
      startup=0
    else
      printf 'Scelta: '
      read -r choice
    fi
    choice=${choice:-0}

    case "$choice" in
      1) full_status; pause_hub ;;
      2) clear; clipboard_menu; pause_hub ;;
      3) clear; share_folder; pause_hub ;;
      4) clear; network_check; pause_hub ;;
      5) clear; lan_scan; pause_hub ;;
      6) clear; compress_video; pause_hub ;;
      7) clear; qr_from_clipboard; pause_hub ;;
      8) clear; battery_automation; pause_hub ;;
      9) clear; backup_termux; pause_hub ;;
      [gG]) clear; start_gui; pause_hub ;;
      [dD]) clear; open_debian; pause_hub ;;
      [fF]) clear; have fastfetch && fastfetch || printf 'fastfetch non installato.\n'; pause_hub ;;
      [hH]) clear; show_help; pause_hub ;;
      0|[qQ]) return 0 ;;
      *) printf '%sScelta non valida.%s\n' "$RED" "$RESET"; sleep 1 ;;
    esac
  done
}

case "${1:-menu}" in
  menu) menu 0 ;;
  --startup) menu 1 ;;
  status) full_status ;;
  share) shift; share_folder "$@" ;;
  netcheck) network_check ;;
  lanscan) lan_scan ;;
  compress) shift; compress_video "${1:-}" ;;
  qr) qr_from_clipboard ;;
  battery) battery_automation ;;
  backup) backup_termux ;;
  gui) start_gui ;;
  debian) open_debian ;;
  help|-h|--help) show_help ;;
  _battery-check) battery_check ;;
  *) show_help; exit 2 ;;
esac
HUB

cat >"$BIN_DIR/termux-battery-check" <<'BATTERY'
#!/usr/bin/env bash
exec "$HOME/.local/bin/termux-hub" _battery-check
BATTERY

chmod 700 "$BIN_DIR/termux-hub" "$BIN_DIR/termux-battery-check"

printf '\n[4/7] Creo la shell Zsh...\n'
cat >"$TERMUX_HOME/.zshrc" <<'ZSHRC'
# Termux Smartphone Shell
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nano
export VISUAL=nano
export PAGER=less
export COLORTERM=truecolor

HISTFILE="$HOME/.zsh_history"
HISTSIZE=20000
SAVEHIST=20000
setopt append_history share_history hist_ignore_all_dups hist_ignore_space
setopt autocd auto_pushd pushd_ignore_dups interactive_comments

bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
autoload -Uz compinit && compinit

for fzf_file in \
  "$PREFIX/share/fzf/key-bindings.zsh" \
  "$PREFIX/share/fzf/shell/key-bindings.zsh"; do
  [[ -r $fzf_file ]] && source "$fzf_file" && break
done
for fzf_file in \
  "$PREFIX/share/fzf/completion.zsh" \
  "$PREFIX/share/fzf/shell/completion.zsh"; do
  [[ -r $fzf_file ]] && source "$fzf_file" && break
done

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

if [[ -r $PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  source "$PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza --color=always --group-directories-first'
  alias ll='eza -lah --group-directories-first --git'
  alias la='eza -a --group-directories-first'
  alias lt='eza --tree --level=2 --group-directories-first'
else
  alias ls='ls --color=auto'
  alias ll='ls -lah --color=auto'
fi

command -v bat >/dev/null 2>&1 && alias view='bat --paging=never --style=plain'
alias grep='grep --color=auto'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias update='pkg update && pkg upgrade'

alias phone='termux-hub menu'
alias phone-status='termux-hub status'
alias share='termux-hub share'
alias netcheck='termux-hub netcheck'
alias lanscan='termux-hub lanscan'
alias compress-video='termux-hub compress'
alias makeqr='termux-hub qr'
alias battery-alert='termux-hub battery'
alias termux-backup='termux-hub backup'
alias gui='termux-hub gui'
alias debian='termux-hub debian'

mkcd() {
  [[ $# -eq 1 ]] || { printf 'Uso: mkcd cartella\n' >&2; return 2; }
  mkdir -p -- "$1" && cd -- "$1"
}

[[ -r $HOME/.zshrc.local ]] && source "$HOME/.zshrc.local"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  autoload -Uz colors && colors
  PROMPT=$'%F{green}╭─%f%F{cyan}TERMUX%f %F{blue}%~%f\n%F{green}╰─❯%f '
fi

if [[ -r $PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source "$PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Mostra il centro di controllo una volta all’apertura della sessione.
if [[ -z ${SSH_CONNECTION:-} && -z ${TERMUX_HUB_SHOWN:-} ]]; then
  export TERMUX_HUB_SHOWN=1
  command -v termux-hub >/dev/null 2>&1 && termux-hub --startup
fi
ZSHRC

printf '\n[5/7] Creo il tema Starship...\n'
cat >"$CONFIG_DIR/starship.toml" <<'STARSHIP'
add_newline = true
scan_timeout = 30
command_timeout = 700

format = """
[╭─](bold green)[TERMUX](bold cyan) $directory$git_branch$git_status$python$nodejs$cmd_duration$status$time
[╰─](bold green)$character"""

[directory]
style = "bold blue"
truncation_length = 4
truncate_to_repo = false
read_only = " RO"
format = "[$path]($style)[$read_only]($read_only_style) "

[git_branch]
symbol = "git:"
style = "bold purple"
format = "[$symbol$branch]($style) "

[git_status]
style = "bold yellow"
format = "[$all_status$ahead_behind]($style) "

[python]
symbol = "py:"
style = "bold cyan"
format = "[$symbol$version]($style) "

[nodejs]
symbol = "node:"
style = "bold green"
format = "[$symbol$version]($style) "

[cmd_duration]
min_time = 1200
style = "bold yellow"
format = "[took $duration]($style) "

[status]
disabled = false
style = "bold red"
format = "[exit $status]($style) "

[time]
disabled = false
time_format = "%H:%M"
style = "dimmed white"
format = "[$time]($style)"

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
vicmd_symbol = "[❮](bold yellow)"
STARSHIP

printf '\n[6/7] Configuro l’accesso alla memoria condivisa...\n'
if [[ ! -d $TERMUX_HOME/storage/shared ]]; then
  printf 'Android potrebbe chiederti il permesso di accesso ai file.\n'
  termux-setup-storage || true
fi

printf '\n[7/7] Imposto Zsh come shell predefinita...\n'
if command -v chsh >/dev/null 2>&1; then
  chsh -s zsh || printf 'Non sono riuscito a cambiare la shell: usa "exec zsh".\n' >&2
fi

printf '\nInstallazione Termux Smartphone Toolkit v%s completata.\n' "$TOOLKIT_RELEASE"
printf 'La vecchia configurazione, se presente, è stata salvata con suffisso backup-%s.\n' "$STAMP"
printf 'Avvia ora la nuova shell con:\n\n  unset TERMUX_HUB_SHOWN; exec zsh\n\n'
printf 'Il menu apparirà automaticamente; in seguito puoi riaprirlo con: phone\n'
